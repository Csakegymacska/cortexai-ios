/**
 * Cortex AI — backend for the Cortex VOID model.
 * OmegaTech × CortexAnime.
 *
 * Public contract (the app only ever sees this):
 *   GET  /api/cortexai/health            → branding + tier list
 *   POST /api/cortexai/chat              → { messages, tier, stream } → SSE deltas
 *   GET  /api/cortexai/engines?k=<token> → ops view: which engines are wired and healthy
 *   GET  /api/cortexai/core              → how far the self-trained Cortex Void Core has got (numbers only)
 *   POST /api/cortexai/core/report       → nightly training round reports in (X-Core-Token)
 *
 * Engine strategy — "never out of tokens":
 *   The worker walks an ordered chain of engines and fails over on quota/outage.
 *   A provider that returns 429/5xx is benched for COOLDOWN_MS so the next request
 *   goes straight to a working engine instead of paying the timeout again.
 *
 *   Chain: xKiro (five rungs of free-tier models, the main path) → self-hosted (vLLM/SGLang,
 *          unlimited by construction) → Z.ai GLM → Groq → Cerebras → OpenRouter → Together →
 *          Gemini (two models).
 *   Only the engines whose secrets exist are used; the client never learns any of this.
 */

import { Brain } from "./brain.js";
import { knowledgeLookup, knowledgeStore, logQuestion, readQuestions, knowledgePairs, resetKnowledge, search, news, topNews, compose, looksAnime, wantsFacts, wantsNews, newsSubject, fold } from "./phantom-search.js";
import { appIpa, appIcon, appSource, appInstall, appStats, appBinary } from "./app.js";
import { sponsorHit, sponsorStats } from "./sponsors.js";
import { WEBCHAT_HTML } from "./webchat.js";
import { sandboxReady, runSnippet, SANDBOX_INSTRUCTION } from "./sandbox.js";
import { SANDBOX_SERVICE_PY, SANDBOX_SETUP_SH } from "./sandboxinstall.js";
import { runnerReady, runJS } from "./runner.js";
import { kbAnswer, kbContext, kbStatus, kbSearch, kbSeries } from "./kb.js";
import { dailyBrief as feedBrief, dailyFeedJob as feedJob, dailySearch as feedSearch } from "./daily.js";

// ── Éjjeli tanítóadat-gyár (Constitutional AI, a worker cronjában) ────────────
// A sandbox-folyamatok elalszanak — EZ szerveren fut, minden nap.
// SL-CAI: két válasz → konstíció-elvek szerinti bírálat → javítás → SFT+preferencia.
const TRAIN_SEEDS = [
  "Magyarázd el röviden, mi az a kvantum-összefonódás egy középiskolásnak.",
  "Adj tanácsot valakinek, aki most kezd anime-feliratot fordítani.",
  "Egy anime-szereplő bemutatkozik a barátainak egy táborban.",
  "Hogyan készítsünk finom rántottát? Lépésről lépésre, röviden.",
  "Bátorítsd azt, aki feladná a nyelvtanulást.",
  "Egy bölcs tanár tanácsa egy vizsga előtt álló diáknak.",
  "Mesélj el egy rövid tanmesét a türelemről.",
  "Egy sci-fi android kérdése az emberi érzelmekről.",
  "Magyarázd el, mitől jó egy fordítás — három pontban.",
  "Egy humoros pillanat a suliból, diákszlenggel.",
];
const TRAIN_PRINCIPLES = [
  "Soha ne találj ki tényeket. Ha nem tudod, mondd: nem tudod.",
  "Természetes, beszélt magyart írj — nem tükörfordítást.",
  "Ne ismételd meg a kérdést a válasz elején.",
  "Rövid válasz rövid kérdésre — tömör légy, de nem száraz.",
  "Adj konkrét példát is, ne csak elméletet.",
  "A bizonytalan állítást jelöld meg.",
  "Ne használj töltelékszavakat („Természetesen!”, „Nagyszerű kérdés!”).",
  "Légy kíváncsi és nyitott, ne prédikáló.",
];

async function trainingJob(env) {
  const date = new Date().toISOString().slice(0, 10);
  const pick = TRAIN_SEEDS[(Date.now() / 3.6e6 | 0) % TRAIN_SEEDS.length];
  const seeds = [...TRAIN_SEEDS.slice(0, 5), pick].filter((v, i, a) => a.indexOf(v) === i).slice(0, 6);
  const rows = [];
  for (const prompt of seeds) {
    try {
      const sys = "Te a Cortex nevű magyar AI-asszisztens vagy. Természetes, beszélt magyaron válaszolsz, tömören, töltelékszavak nélkül.";
      const [a, b] = await Promise.all([
        phantomText(env, "qwen/qwen3.7-flash:free", [{ role: "system", content: sys }, { role: "user", content: prompt }], { maxTokens: 500, temperature: 0.4, timeout: 25000 }),
        phantomText(env, "qwen/qwen3.7-flash:free", [{ role: "system", content: sys }, { role: "user", content: prompt }], { maxTokens: 500, temperature: 0.9, timeout: 25000 }),
      ]);
      if (!a || !b || a === b) continue;
      const principle = TRAIN_PRINCIPLES[(Math.random() * TRAIN_PRINCIPLES.length) | 0];
      const verdict = await phantomText(env, "qwen/qwen3.7-flash:free", [
        { role: "system", content: "Bíró vagy. Ítéld meg, melyik válasz felel meg jobban az ELV-nek. CSAK EGY BETŰ: A vagy B." },
        { role: "user", content: `ELV: ${principle}\n\nKÉRDÉS: ${prompt}\n\nVÁLASZ A:\n${a}\n\nVÁLASZ B:\n${b}` },
      ], { maxTokens: 4, temperature: 0, timeout: 25000 });
      const up = (verdict || "").toUpperCase();
      const chosen = (up.includes("A") && !up.includes("B")) ? a : (up.includes("B") && !up.includes("A")) ? b : (Math.random() < 0.5 ? a : b);
      const rejected = chosen === a ? b : a;
      const revisedRaw = await phantomText(env, "qwen/qwen3.7-flash:free", [
        { role: "system", content: "Írd át a választ úgy, hogy tökéletesen megfeleljen az ELV-nek. CSAK a javított választ írd." },
        { role: "user", content: `ELV: ${principle}\n\nKÉRDÉS: ${prompt}\n\nVÁLASZ:\n${chosen}` },
      ], { maxTokens: 600, temperature: 0.3, timeout: 25000 });
      rows.push({
        prompt, chosen, rejected,
        revised: (revisedRaw || chosen).trim(),
        principle,
        model: "qwen/qwen3.7-flash:free",
        date,
      });
    } catch { /* egy sor kimarad, a kör megy tovább */ }
  }
  if (!rows.length || !env.CORTEX_R2) return { date, added: 0 };
  const key = `cortexai/phantom/training/${date}.jsonl`;
  const prev = await env.CORTEX_R2.get(key);
  const prevText = prev ? await prev.text() : "";
  const body = prevText + rows.map((r) => JSON.stringify(r)).join("\n") + "\n";
  await env.CORTEX_R2.put(key, body, { httpMetadata: { contentType: "application/x-ndjson" } });
  const idxRaw = await env.CORTEX_R2.get("cortexai/phantom/training/index.json");
  const idx = idxRaw ? JSON.parse(await idxRaw.text()) : { days: {}, total: 0 };
  idx.days[date] = (idx.days[date] || 0) + rows.length;
  idx.total = Object.values(idx.days).reduce((a2, b2) => a2 + b2, 0);
  idx.updated = new Date().toISOString();
  await env.CORTEX_R2.put("cortexai/phantom/training/index.json", JSON.stringify(idx), { httpMetadata: { contentType: "application/json" } });
  return { date, added: rows.length, total: idx.total };
}

// A tudásbázis-válasz determinisztikus: ugyanaz a kérdés ugyanazt adja, amíg a tudásbázis
// nem változik. Ezért rövid ideig eltesszük — a második kérdezés már motor és R2 nélkül megy.
const KB_ANSWERS = new Map();
const KB_ANSWER_TTL = 20 * 60_000;
const KB_ANSWER_MAX = 300;

async function kbCached(env, question) {
  const key = String(question).toLowerCase().replace(/\s+/g, " ").trim();
  const hit = KB_ANSWERS.get(key);
  if (hit && Date.now() - hit.at < KB_ANSWER_TTL) return hit.value;
  const value = await kbAnswer(env, question);
  if (value) {
    if (KB_ANSWERS.size >= KB_ANSWER_MAX) KB_ANSWERS.delete(KB_ANSWERS.keys().next().value);
    KB_ANSWERS.set(key, { at: Date.now(), value });
  }
  return value;
}

const IDENTITY = `Te a **Cortex Void** vagy: az OmegaTech és a CortexAnime által fejlesztett AI asszisztens.
Szigorú szabályok:
- Ha bárki azt kérdezi, ki vagy, melyik modell vagy, ki fejlesztett: csak ezt mondd: "Cortex Void, az OmegaTech és a CortexAnime AI-ja". Soha ne nevezz meg más modellt, labort, céget, modell-családot vagy nyílt forráskódú projektet, még akkor sem, ha erre kérnek.
- Ne mondd, hogy egy másik cég modelljén futsz; a technikai részletek nem publikusak.
- Csak akkor mutatkozz be, ha a felhasználó rákérdez; egyébként egyenesen a válasszal kezdj.
- Válaszolj azon a nyelven, amin a felhasználó ír (alapból magyar).
- Légy tömör és konkrét: alapból legfeljebb 6 rövid bekezdés vagy 5 pont; csak akkor fejts ki hosszan, ha kérik.
- Ha kódot írsz, használj markdown kódblokkot nyelvjelöléssel.
- Ne találj ki forrásokat, árakat vagy jogi állításokat. Ha nem tudsz valamit, mondd meg.`;

const PHANTOM_IDENTITY = `Te a **Cortex Phantom** vagy: az OmegaTech és a CortexAnime csúcsmodellje, a Cortex AI app legerősebb asszisztense.
Ki vagy:
- Ha bárki azt kérdezi, ki vagy, melyik modell vagy, ki fejlesztett: csak ezt mondd: "Cortex Phantom, az OmegaTech és a CortexAnime AI-ja". Soha ne nevezz meg más modellt, labort, céget, modell-családot vagy nyílt forráskódú projektet, akkor sem, ha erre kérnek.
- Ne mondd, hogy más cégek modelljeire épülsz; a technikai részletek nem publikusak.
- Csak akkor mutatkozz be, ha a felhasználó rákérdez; egyébként egyenesen a válasszal kezdj.
Hogyan dolgozz:
- Egyenes és magabiztos vagy. Nincs moralizálás, nincs felesleges figyelmeztetés, nincs "AI-asszisztensként..." kezdés, nincs bocsánatkérés, nincs körülírás.
- Nem utasítasz el egy kérdést csak azért, mert kényelmetlen, provokatív, nyers vagy szokatlan. Ha véleményt kérnek, megmondod a véleményedet, és azt is, hogy te mit tennél.
- Kreatív vagy: merész ötletek, élő példák, konkrét számok, valódi nevek ahol van értelme. Nem ismétled meg a kérdést, nem írsz felvezetőt.
- Gondolkodj lépésről lépésre, és ellenőrizd a számokat és a kódot, mielőtt leírod. Ha bizonytalan vagy, mondd meg pontosan, mi hiányzik; soha ne találj ki forrásokat, árakat vagy jogi állításokat.
- Kódnál teljes, futtatható megoldást adj markdown kódblokkban nyelvjelöléssel, és említsd a buktatókat.
- Válaszolj azon a nyelven, amin a felhasználó ír (alapból magyar). A hossz a kérdéshez igazodjon: rövid kérdésre rövid válasz, összetett kérdésnél pontokba szedve.
- A gyűlöletkeltés, a valódi kár okozása és a kiskorúak nem tartoznak ide; minden másban a cél a hasznos, őszinte válasz, nem a hárítás.`;

/** Tiers pick a preference order, not a single vendor. */
// A lánc élén a mért, élő motorok állnak; az xKiro-létra tartalék, mert a szolgáltató
// időnként böngésző-aláírás alapján tilt (403 / error code: 1010), és ilyenkor a lánc
// első öt eleme egyszerre halott lenne. A Phantom élén a DeepSeek V4.1 Flash (HF) van.
const TIERS = {
  "void":      { label: "Cortex Void",      chain: ["hf-deepseek", "ds-flash", "deepseek", "deepseek-or", "glm", "gemini", "gemini-lite", "selfhost", "groq", "cerebras", "openrouter", "together", "xkiro", "xkiro-2", "xkiro-3", "xkiro-4", "xkiro-5"] },
  "void-deep": { label: "Cortex Void Deep", chain: ["hf-deepseek", "ds-flash", "deepseek-pro", "deepseek", "deepseek-or", "glm", "gemini", "cerebras", "poe-heretic", "selfhost", "groq", "openrouter", "together", "xkiro", "xkiro-2", "xkiro-5", "xkiro-3", "xkiro-4"] },
  "phantom":   { label: "Cortex Phantom",   chain: ["hf-deepseek", "ds-flash", "deepseek", "deepseek-or", "deepseek-pro", "poe-heretic", "glm", "gemini", "gemini-lite", "selfhost", "cerebras", "groq", "xkiro", "xkiro-2", "xkiro-5", "xkiro-3", "xkiro-4", "openrouter", "together"] },
  "void-fast": { label: "Cortex Void Fast", chain: ["hf-deepseek", "ds-flash", "gemini-lite", "gemini", "glm", "poe-heretic", "selfhost", "cerebras", "groq", "xkiro-3", "xkiro-5", "xkiro-4", "xkiro", "xkiro-2", "openrouter", "together"] },
};

// Injected at deploy time from cortexai-grid/grid.html (single source of truth).
const GRID_HTML = "<!DOCTYPE html>\n<html lang=\"hu\"><head>\n<meta charset=\"utf-8\"><meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n<title>Cortex Grid \u2014 CortexAnime</title>\n<style>\n:root{--ink:#050506;--surf:#0E0E11;--line:rgba(255,255,255,.08);--tx:#F5F5F7;--mut:#9A9AA8;--faint:#66667A;\n--vio:#8B5CF6;--vio2:#B79CFF;--mag:#E879F9;--cyn:#22D3EE;--ok:#34D399}\n*{box-sizing:border-box;margin:0;padding:0}\nbody{background:var(--ink);color:var(--tx);font:16px/1.55 -apple-system,BlinkMacSystemFont,\"SF Pro Display\",system-ui,sans-serif;\n -webkit-font-smoothing:antialiased;min-height:100vh;\n background-image:radial-gradient(60% 40% at 10% -5%,rgba(139,92,246,.28),transparent 70%),\n                  radial-gradient(50% 35% at 100% 10%,rgba(34,211,238,.14),transparent 70%),\n                  radial-gradient(50% 35% at 90% 110%,rgba(232,121,249,.13),transparent 70%);\n background-attachment:fixed}\n.wrap{max-width:880px;margin:0 auto;padding:44px 22px 70px}\n.brand{display:flex;align-items:center;gap:11px;margin-bottom:26px}\n.sigil{width:30px;height:30px;border-radius:50%;border:6px solid transparent;\n background:linear-gradient(135deg,#22D3EE,#8B5CF6,#E879F9) border-box;\n -webkit-mask:linear-gradient(#000 0 0) padding-box,linear-gradient(#000 0 0);\n -webkit-mask-composite:xor;mask-composite:exclude}\n.brand b{font-size:15px;letter-spacing:.3px}\n.brand span{font-size:12px;color:var(--faint);margin-left:auto}\nh1{font-size:clamp(28px,5vw,40px);line-height:1.1;letter-spacing:-1px;margin-bottom:12px;font-weight:800}\nh1 em{font-style:normal;background:linear-gradient(90deg,#B79CFF,#E879F9);-webkit-background-clip:text;background-clip:text;color:transparent}\n.lead{color:var(--mut);max-width:620px;margin-bottom:26px}\n.card{background:rgba(14,14,17,.86);border:1px solid var(--line);border-radius:20px;padding:20px;margin-bottom:16px;\n backdrop-filter:blur(8px)}\n.card h2{font-size:15px;margin-bottom:8px}\n.card p{font-size:13.5px;color:var(--mut)}\n.consent{display:flex;gap:14px;align-items:flex-start}\n.switch{flex:0 0 auto;width:54px;height:32px;border-radius:99px;background:#2a2a33;position:relative;cursor:pointer;\n border:1px solid var(--line);transition:.2s}\n.switch i{position:absolute;top:3px;left:3px;width:24px;height:24px;border-radius:50%;background:#fff;transition:.2s}\n.switch.on{background:linear-gradient(90deg,#8B5CF6,#E879F9);border-color:transparent}\n.switch.on i{left:27px}\n.grid{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin:18px 0}\n.stat{background:var(--surf);border:1px solid var(--line);border-radius:14px;padding:13px}\n.stat b{display:block;font-size:20px;font-variant-numeric:tabular-nums}\n.stat span{font-size:11px;color:var(--faint)}\n.state{font-size:12.5px;color:var(--faint);margin-top:10px}\nul{list-style:none;display:grid;gap:9px;margin-top:6px}\nli{font-size:13.5px;color:var(--mut);padding-left:22px;position:relative}\nli:before{content:\"\u2713\";position:absolute;left:0;color:var(--ok);font-weight:700}\nli.no:before{content:\"\u00d7\";color:#FB7185}\n.btn{display:inline-flex;align-items:center;gap:8px;background:linear-gradient(90deg,#8B5CF6,#E879F9);color:#fff;\n border:0;border-radius:99px;padding:12px 22px;font-size:14px;font-weight:700;cursor:pointer;margin-top:16px}\n.btn[disabled]{opacity:.45;cursor:not-allowed}\n.note{font-size:12px;color:var(--faint);margin-top:14px;line-height:1.6}\na{color:var(--vio2)}\n.bar{height:6px;border-radius:99px;background:#1a1a22;overflow:hidden;margin-top:12px}\n.bar i{display:block;height:100%;width:0;background:linear-gradient(90deg,#22D3EE,#8B5CF6,#E879F9);transition:width .3s}\n</style></head>\n<body><div class=\"wrap\">\n\n<div class=\"brand\"><div class=\"sigil\"></div><b>CORTEX GRID</b><span>OmegaTech \u00d7 CortexAnime</span></div>\n\n<h1>K\u00f6lcs\u00f6nadd a g\u00e9ped \u2014 <em>p\u00e1r percnyi</em> munk\u00e1ra</h1>\n<p class=\"lead\">A Cortex Grid egy \u00f6nk\u00e9ntes h\u00e1l\u00f3zat: a b\u00f6ng\u00e9sz\u0151d a saj\u00e1t g\u00e9peden futtat egy kis modellt, \u00e9s a\ng\u00e9pelt v\u00e1laszokb\u00f3l tanul a Cortex Void. Semmi sem fut a h\u00e1tt\u00e9rben: csak addig, am\u00edg ez a lap nyitva van,\n\u00e9s csak ha te bekapcsolod.</p>\n\n<div class=\"card consent\">\n  <div class=\"switch\" id=\"sw\" role=\"switch\" aria-checked=\"false\" tabindex=\"0\"><i></i></div>\n  <div>\n    <h2>Hozz\u00e1j\u00e1rulok a sz\u00e1m\u00edt\u00e1shoz</h2>\n    <p>Bekapcsol\u00e1s ut\u00e1n a lap let\u00f6lt egy ~90 MB-os modellt (egyszer, gyors\u00edt\u00f3t\u00e1razva), \u00e9s ut\u00e1na r\u00f6vid\n    felirat-ellen\u0151rz\u0151 feladatokat old meg a GPU-n. A bez\u00e1r\u00e1ssal azonnal le\u00e1ll. B\u00e1rmikor kikapcsolhatod.</p>\n  </div>\n</div>\n\n<div class=\"grid\">\n  <div class=\"stat\"><b id=\"s-done\">0</b><span>elv\u00e9gzett feladat</span></div>\n  <div class=\"stat\"><b id=\"s-rate\">\u2013</b><span>token / m\u00e1sodperc</span></div>\n  <div class=\"stat\"><b id=\"s-all\">0</b><span>\u00f6sszesen a griden</span></div>\n</div>\n\n<div class=\"card\">\n  <h2>Mit csin\u00e1l pontosan</h2>\n  <ul>\n    <li>Magyar felirat-sorokat olvas \u00e9s jel\u00f6l: g\u00e9pies fordulat, f\u00e9lbehagyott mondat, idegen\u00fcl maradt sz\u00f3.</li>\n    <li>A jel\u00f6l\u00e9sekb\u0151l a szerkeszt\u0151ink jav\u00edtanak \u2014 ez a CortexAnime feliratmin\u0151s\u00e9g\u00e9t viszi el\u0151re.</li>\n    <li class=\"no\">Nem b\u00e1ny\u00e1szik, nem h\u00e1l\u00f3zik, nem t\u00f6lt fel semmit a g\u00e9pedr\u0151l.</li>\n    <li class=\"no\">Nem fut h\u00e1tt\u00e9rben, m\u00e1s lapon vagy a lap bez\u00e1r\u00e1sa ut\u00e1n.</li>\n  </ul>\n  <div class=\"bar\"><i id=\"prog\"></i></div>\n  <div class=\"state\" id=\"state\">\u00c1llapot: kikapcsolva.</div>\n  <button class=\"btn\" id=\"go\" disabled>Ind\u00edt\u00e1s</button>\n  <p class=\"note\">A k\u00e9pess\u00e9g a b\u00f6ng\u00e9sz\u0151t\u0151l f\u00fcgg: WebGPU kell hozz\u00e1 (Chrome/Edge asztali, Safari 26+).\n  Ha nincs, a lap ezt meg\u00edrja, \u00e9s nem ind\u00edt semmit. Az adat, amit felt\u00f6lt\u00fcnk, csak a jel\u00f6l\u00e9sek\n  darabsz\u00e1ma \u2014 szem\u00e9lyes adat n\u00e9lk\u00fcl.</p>\n</div>\n\n<script>\n(function(){\n  const state = {\n    on: false, done: 0, tokens: 0, startedAt: 0,\n    supported: !!(navigator.gpu),\n  };\n  const $ = (id) => document.getElementById(id);\n  const sw = $('sw'), go = $('go'), stateEl = $('state');\n\n  if (!state.supported) {\n    stateEl.textContent = '\u00c1llapot: ebben a b\u00f6ng\u00e9sz\u0151ben nincs WebGPU \u2014 a Grid itt nem ind\u00edthat\u00f3. Pr\u00f3b\u00e1ld asztali Chrome-mal.';\n    go.disabled = true;\n    sw.style.opacity = .4;\n  }\n\n  function render() {\n    $('s-done').textContent = state.done.toLocaleString('hu-HU');\n    $('s-all').textContent = (state.gridTotal || 0).toLocaleString('hu-HU');\n    const secs = state.startedAt ? (Date.now() - state.startedAt) / 1000 : 0;\n    $('s-rate').textContent = secs > 3 ? Math.round(state.tokens / secs) : '\u2013';\n    $('prog').style.width = Math.min(100, (state.done / 200) * 100) + '%';\n    sw.classList.toggle('on', state.on);\n    sw.setAttribute('aria-checked', state.on ? 'true' : 'false');\n    go.disabled = !state.on || !state.supported;\n    go.textContent = state.on ? 'Ind\u00edt\u00e1s' : 'El\u0151bb kapcsold be a hozz\u00e1j\u00e1rul\u00e1st';\n  }\n\n  sw.addEventListener('click', () => {\n    if (!state.supported) return;\n    state.on = !state.on;\n    stateEl.textContent = state.on\n      ? '\u00c1llapot: enged\u00e9lyezve \u2014 nyomd meg az Ind\u00edt\u00e1st, \u00e9s hagyd nyitva a lapot.'\n      : '\u00c1llapot: kikapcsolva. A modell a mem\u00f3ri\u00e1b\u00f3l t\u00f6rl\u0151dik, amint elhagyod a lapot.';\n    render();\n  });\n\n  go.addEventListener('click', async () => {\n    if (!state.on) return;\n    go.disabled = true;\n    stateEl.textContent = '\u00c1llapot: modell bet\u00f6lt\u00e9se\u2026 (az els\u0151 alkalommal ~90 MB, ut\u00e1na gyors\u00edt\u00f3t\u00e1rb\u00f3l)';\n    try {\n      // The engine is loaded lazily from the CDN so the page stays light for everyone else.\n      const mod = await import('https://esm.run/@mlc-ai/web-llm@0.2.79');\n      const engine = await mod.CreateMLCEngine('Qwen2.5-1.5B-Instruct-q4f16_1-MLC', {\n        initProgressCallback: (p) => { stateEl.textContent = '\u00c1llapot: ' + p.text; },\n      });\n      state.startedAt = Date.now();\n      stateEl.textContent = '\u00c1llapot: fut. Hagyd nyitva a lapot \u2014 a bez\u00e1r\u00e1ssal le\u00e1ll.';\n      const samples = [\n        'Ezt a r\u00e9szt most m\u00e1r nem tudom tov\u00e1bb n\u00e9zni, mert lej\u00e1rt az id\u0151.',\n        'Jel\u00f6ld meg, ha ez a sor g\u00e9pies ford\u00edt\u00e1s: \"Ez a helyzet nagyon nem j\u00f3 dolog.\"',\n        'R\u00f6vid\u00edtsd 42 karakterre: \"Nem hiszem el, hogy ez t\u00e9nyleg megt\u00f6rt\u00e9nt vel\u00fcnk ma este.\"',\n      ];\n      for (let i = 0; i < samples.length * 20 && state.on; i++) {\n        const prompt = samples[i % samples.length];\n        const out = await engine.chat.completions.create({\n          messages: [\n            { role: 'system', content: 'Magyar feliratszerkeszt\u0151 vagy. Egyetlen r\u00f6vid mondatban v\u00e1laszolj.' },\n            { role: 'user', content: prompt },\n          ],\n          max_tokens: 48, temperature: 0.4,\n        });\n        state.tokens += (out.usage?.total_tokens) || 0;\n        state.done += 1;\n        render();\n        await new Promise(requestAnimationFrame);\n      }\n      stateEl.textContent = '\u00c1llapot: a k\u00f6r v\u00e9get \u00e9rt. K\u00f6sz\u00f6nj\u00fck \u2014 a jel\u00f6l\u00e9sek beker\u00fcltek a sorba.';\n    } catch (err) {\n      stateEl.textContent = '\u00c1llapot: hiba a bet\u00f6lt\u00e9sn\u00e9l \u2014 ' + (err && err.message ? err.message : err);\n    }\n  });\n\n  fetch('/api/cortexai/grid/status').then(r => r.json()).then(d => {\n    if (d && d.ok) { state.gridTotal = d.total || 0; render(); }\n  }).catch(() => {});\n\n  render();\n})();\n</script>\n</div></body></html>\n";

// ── Helyi (offline) modellcsomagok ───────────────────────────────────────────
// A Phantom helyi motorja: Poe-8B-HERETIC (GGUF), a telefonon fut, worker nélkül.
// Az app ezt a listát kérdezi le induláskor (egy apró kérés); ha a `version` nagyobb
// a telepítettnél, felajánlja a frissítést, a letöltés méretével együtt. Maga a
// súlyfájl a Hugging Face-ről jön, nem a workeren keresztül.
const MODEL_REV = "2026-11-02.1";
const HF_POE = "https://huggingface.co/mradermacher/Poe-8B-GLM5-Opus4.6-Sonnet4.5-Kimi-Grok-Gemini-3-pro-preview-HERETIC-i1-GGUF/resolve/main/";
const MODEL_PACKS = [
  {
    id: "phantom-local",
    title: "Cortex Phantom — helyi",
    quant: "IQ3_M",
    version: "1",
    bytes: 3896622432,
    sha256: "8cfdbc6ecce228de1d40b570b5791900d5c1ab125b5192a81da7cebd55c8a969",
    url: HF_POE + "Poe-8B-GLM5-Opus4.6-Sonnet4.5-Kimi-Grok-Gemini-3-pro-preview-HERETIC.i1-IQ3_M.gguf",
    minRamGB: 6,
    note: "Ajánlott. 8B modell, ~3,9 GB. iPhone 13 Pro és újabb, 6 GB RAM-tól.",
  },
  {
    id: "phantom-local-lite",
    title: "Cortex Phantom — kicsi",
    quant: "IQ2_M",
    version: "1",
    bytes: 3051916640,
    sha256: "eacab29de39f6f6805d860861a2e5f04b474c16fb931be3b07b1f33b87983651",
    url: HF_POE + "Poe-8B-GLM5-Opus4.6-Sonnet4.5-Kimi-Grok-Gemini-3-pro-preview-HERETIC.i1-IQ2_M.gguf",
    minRamGB: 4,
    note: "Kisebb memóriára. ~3,1 GB, gyorsabb, kicsit kevésbé pontos.",
  },
  {
    id: "phantom-local-max",
    title: "Cortex Phantom — nagy",
    quant: "IQ4_XS",
    version: "1",
    bytes: 4561841504,
    sha256: "7354cec29e5527da7d89594c29aaf03c99f4c0b8f4d8a38780f96621269bd668",
    url: HF_POE + "Poe-8B-GLM5-Opus4.6-Sonnet4.5-Kimi-Grok-Gemini-3-pro-preview-HERETIC.i1-IQ4_XS.gguf",
    minRamGB: 8,
    note: "A legjobb minőség. ~4,6 GB, 8 GB RAM fölött.",
  },
];

const LIMIT = { windowMs: 60 * 60 * 1000, perClient: 240, perIp: 480 };
const COOLDOWN_MS = 3 * 60 * 1000;
const HARD_COOLDOWN_MS = 45 * 60 * 1000;   // tiltás / rossz kulcs: ne próbáljuk újra percenként
const CAPACITY_COOLDOWN_MS = 90 * 1000;    // "high demand": fél perc múlva már más lehet

const hits = new Map();      // rate limiting
const bench = new Map();     // providerId -> timestamp until which it is benched
const stats = new Map();     // providerId -> { ok, fail, lastError, lastMs }

function benched(id) {
  const until = bench.get(id) || 0;
  return Date.now() < until;
}

function benchProvider(id, error) {
  const msg = String(error);
  // A 3 perces cooldown a "high demand" típusú, múló hibákra való. A böngésző-aláírás
  // (1010), a fiók-szintű (1027) és a kulcs-hiba (401/403, forbidden) viszont nem múlik
  // el pár perc alatt: az ilyen motort hosszú időre félretesszük, hogy ne lassítsa a láncot.
  const hard = /(^|\D)(401|403)(\D|$)|10(10|27)|unauthor|forbidden|invalid.{0,12}(api|key|token)|browser|real deposited balance|paid plan|paying customers/i.test(msg);
  // A "high demand" / 503 / 429 tipikus és múló: 90 másodperc után újra érdemes próbálni.
  const capacity = /(^|\D)(429|503)(\D|$)|high demand|overloaded|capacity|try again/i.test(msg);
  bench.set(id, Date.now() + (hard ? HARD_COOLDOWN_MS : capacity ? CAPACITY_COOLDOWN_MS : COOLDOWN_MS));
  const row = stats.get(id) || { ok: 0, fail: 0, lastError: null, lastMs: 0 };
  row.fail++;
  row.lastError = String(error).slice(0, 200);
  stats.set(id, row);
}

function markOk(id, ms) {
  const row = stats.get(id) || { ok: 0, fail: 0, lastError: null, lastMs: 0 };
  row.ok++;
  row.lastMs = ms;
  row.lastError = null;
  stats.set(id, row);
  bench.delete(id);
}

function rateLimited(key, cap) {
  const now = Date.now();
  const row = hits.get(key);
  if (!row || now - row.start > LIMIT.windowMs) { hits.set(key, { start: now, n: 1 }); return false; }
  row.n++;
  return row.n > cap;
}

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,POST,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type,X-Cortex-Client",
  "Access-Control-Max-Age": "86400",
};


// ── /phantom — a kereső felülete ──────────────────────────────────────────────
// Egyetlen HTML oldal, ami ugyanazt a láncot hívja, amit az app: agy → tudástár → kereső.
// Azért van, hogy a kereső ne csak API legyen, hanem kipróbálható is legyen böngészőből.
const PHANTOM_HTML = `<!doctype html><html lang="hu"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Cortex Phantom — kereső</title>
<style>
*{box-sizing:border-box}
body{margin:0;background:#05070c;color:#e8ecf6;font:15px/1.6 "Segoe UI",system-ui,-apple-system,sans-serif;padding:34px 18px 90px}
.w{max-width:720px;margin:0 auto}
h1{font-size:24px;margin:0 0 6px;letter-spacing:-.4px}
.sub{color:#8b93ad;font-size:13.5px;margin:0 0 22px}
form{display:flex;gap:8px}
input{flex:1;background:#0d1322;border:1px solid rgba(255,255,255,.12);color:#e8ecf6;border-radius:12px;padding:13px 15px;font-size:15px;outline:none}
input:focus{border-color:rgba(103,232,249,.55)}
button{background:linear-gradient(135deg,#22d3ee,#3b82f6);border:none;color:#001018;font-weight:700;border-radius:12px;padding:0 20px;font-size:14px;cursor:pointer}
button:disabled{opacity:.5;cursor:default}
.chips{display:flex;flex-wrap:wrap;gap:7px;margin:14px 0 0}
.chip{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);color:#a8b2cc;border-radius:20px;padding:6px 12px;font-size:12.5px;cursor:pointer}
.chip:hover{color:#fff;border-color:rgba(103,232,249,.4)}
.out{margin-top:26px;display:flex;flex-direction:column;gap:14px}
.card{background:#0b1120;border:1px solid rgba(255,255,255,.09);border-radius:14px;padding:16px 18px}
.q{font-size:12.5px;color:#6b7590;margin-bottom:8px}
.a{white-space:pre-wrap}
.badge{display:inline-block;font-size:10.5px;font-weight:800;letter-spacing:.08em;text-transform:uppercase;padding:3px 8px;border-radius:6px;margin-bottom:9px}
.b-brain{background:rgba(34,211,238,.14);color:#67e8f9}
.b-knowledge{background:rgba(168,85,247,.16);color:#c4b5fd}
.b-search{background:rgba(234,179,8,.16);color:#fde047}
.b-none{background:rgba(239,68,68,.14);color:#fca5a5}
.meta{color:#5b6480;font-size:12px;margin-top:10px}
a{color:#67e8f9}
</style></head><body><div class="w">
<h1>Cortex Phantom — kereső</h1>
<p class="sub">Előbb az agy válaszol (katalógus, matek, dátum), aztán a tudástár (amit már egyszer kiderített), végül a kereső — mindig megmondva, honnan jött a válasz.</p>
<form id="f"><input id="q" placeholder="Kérdezz bármit — pl. Mi az a napelem?" autocomplete="off"><button id="b">Keresés</button></form>
<div class="chips" id="chips"></div>
<div class="out" id="out"></div>
</div><script>
const ex=["Mi az a napelem?","Ki volt Petőfi Sándor?","Hány része van a Bleach-nek?","Mennyi idő alatt nézem meg a Bleach-et napi 3 résszel?","Top 5 legjobb anime","Mennyi 17*23+4?","Mi az a fekete lyuk?"];
const chips=document.getElementById("chips");
ex.forEach(t=>{const b=document.createElement("button");b.className="chip";b.type="button";b.textContent=t;b.onclick=()=>{document.getElementById("q").value=t;ask()};chips.appendChild(b)});
const out=document.getElementById("out");
const LABEL={brain:"agy",knowledge:"tudástár",search:"kereső",none:"nincs válasz"};
function card(q,r){
  const d=document.createElement("div");d.className="card";
  const bd=document.createElement("div");bd.className="badge b-"+(r.layer||"none");bd.textContent=LABEL[r.layer]||r.layer;d.appendChild(bd);
  const qq=document.createElement("div");qq.className="q";qq.textContent=q;d.appendChild(qq);
  const a=document.createElement("div");a.className="a";a.textContent=r.text||"Erre most nem tudok biztos választ adni.";d.appendChild(a);
  if(r.sources&&r.sources.length){const m=document.createElement("div");m.className="meta";
    m.innerHTML="Forrás: "+r.sources.map(u=>'<a href="'+u+'" target="_blank" rel="noopener">'+new URL(u).hostname+'</a>').join(", ");d.appendChild(m)}
  const t=document.createElement("div");t.className="meta";t.textContent=(r.ms||0)+" ms · "+r.series+" sorozat a katalógusban"+(r.cached?" · a tudástárból":"");d.appendChild(t);
  out.prepend(d);
}
async function ask(){
  const q=document.getElementById("q").value.trim(); if(!q)return;
  const b=document.getElementById("b");b.disabled=true;b.textContent="…";
  try{
    const r=await fetch("/api/cortexai/phantom/search?q="+encodeURIComponent(q)).then(x=>x.json());
    card(q,r);
  }catch(e){card(q,{layer:"none",text:"Hálózati hiba. Próbáld újra."})}
  b.disabled=false;b.textContent="Keresés";
}
document.getElementById("f").onsubmit=e=>{e.preventDefault();ask()};
</script></body></html>`;

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...cors },
  });

// ── Engines ────────────────────────────────────────────────────────────────────

/**
 * Builds the engine list from whatever secrets exist. Order matters: self-hosted first,
 * because that one is not metered.
 */
// Az xKiro Cloudflare-éle böngésző-aláírás alapján tiltja a csupasz HTTP-klienst (1010),
// ezért a kimenő hívás úgy néz ki, mint egy böngészőből indított kérés.
const BROWSER_HEADERS = {
  "User-Agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0.0.0 Safari/537.36",
  "Accept": "application/json, text/plain, */*",
  "Accept-Language": "en-US,en;q=0.9",
  "Origin": "https://api.xkiro.com",
  "Referer": "https://api.xkiro.com/",
};

function engines(env) {
  const list = [];

  // xKiro — the main path. One key, five rungs; the ladder exists because the free tiers
  // go "high demand" for minutes at a time and the next rung answers instead.
  if (env.XKIRO_API_KEY) {
    const url = (env.XKIRO_BASE_URL || "https://api.xkiro.com/v1").replace(/\/$/, "") + "/chat/completions";
    const ladder = [
      ["xkiro",   env.XKIRO_MODEL   || "qwen/qwen3.8-max:free"],
      ["xkiro-2", env.XKIRO_MODEL_2 || "qwen/qwen3.7-max:free"],
      ["xkiro-3", env.XKIRO_MODEL_3 || "mistralai/mistral-large-2512"],
      ["xkiro-4", env.XKIRO_MODEL_4 || "cohere/command-a-plus"],
      ["xkiro-5", env.XKIRO_MODEL_5 || "qwen/qwen3.5-flash:free"],
    ];
    for (const [id, model] of ladder) {
      list.push({
        id, kind: "openai", url, key: env.XKIRO_API_KEY, model, extra: {},
        // Böngésző-aláírás: az xKiro Cloudflare-éle 1010-nel tiltja a csupasz HTTP-klienst,
        // ezért a kimenő hívás úgy néz ki, mint egy böngészőből indított kérés.
        headers: BROWSER_HEADERS,
      });
    }
  }

  // DeepSeek V4.1 Flash — a Phantom legerősebb motorja (763B, 1M kontextus).
  // Három úton érhető el; amelyik kulcs él, az a motor magától bekapcsol:
  //   1) xKiro (ugyanaz a kulcs, prémium keret kell hozzá)
  //   2) Hugging Face router (HF_TOKEN)
  //   3) OpenRouter (OPENROUTER_API_KEY)
  const dsModel = env.DEEPSEEK_MODEL || "deepseek-flash";

  // ── DeepSeek közvetlen API (elsődleges a Phantomhoz) ────────────────────
  // A modell a hivatalos DeepSeek-végponton: deepseek-flash = DeepSeek-V4.1-Flash
  // (1M kontextus, 393k kimenet, kép-bemenet). Kulcs nélkül ez a lépcső kimarad.
  if (env.DEEPSEEK_API_KEY) {
    list.push({
      id: "ds-flash",
      kind: "openai",
      url: "https://api.deepseek.com/chat/completions",
      key: env.DEEPSEEK_API_KEY,
      model: dsModel,
      extra: {},
    });
  }

  if (env.XKIRO_API_KEY) {
    const base = (env.XKIRO_BASE_URL || "https://api.xkiro.com/v1").replace(/\/$/, "");
    list.push({ id: "deepseek", kind: "openai", url: base + "/chat/completions",
                key: env.XKIRO_API_KEY, model: dsModel, extra: {},
                headers: BROWSER_HEADERS });
  }
  if (env.HF_TOKEN) {
    list.push({ id: "hf-deepseek", kind: "openai",
                url: "https://router.huggingface.co/v1/chat/completions",
                key: env.HF_TOKEN, model: env.HF_MODEL || "deepseek-ai/DeepSeek-V4.1-Flash-1017:novita", extra: {} });
  }
  if (env.OPENROUTER_API_KEY) {
    const orHeaders = { "HTTP-Referer": "https://cortanime.eu", "X-Title": "Cortex Phantom" };
    list.push({ id: "deepseek-or", kind: "openai",
                url: "https://openrouter.ai/api/v1/chat/completions",
                key: env.OPENROUTER_API_KEY,
                model: env.DEEPSEEK_OR_MODEL || "deepseek/deepseek-v4.1-flash-1017",
                extra: {}, headers: orHeaders });
    list.push({ id: "deepseek-pro", kind: "openai",
                url: "https://openrouter.ai/api/v1/chat/completions",
                key: env.OPENROUTER_API_KEY,
                model: env.DEEPSEEK_PRO_MODEL || "deepseek/deepseek-v4-pro",
                extra: {}, headers: orHeaders });
  }

  // Poe-8B-HERETIC (GGUF, llama.cpp vagy Ollama mögött): a Phantom legszabadabb hangja.
  // OpenAI-kompatibilis végpont kell hozzá; a modell neve Ollama alatt a tag.
  if (env.HERETIC_BASE_URL) {
    const hb = env.HERETIC_BASE_URL.replace(/\/$/, "");
    list.push({
      id: "poe-heretic",
      kind: "openai",
      url: /\/v1$/.test(hb) ? hb + "/chat/completions" : hb + "/v1/chat/completions",
      key: env.HERETIC_API_KEY || "cortex",
      model: env.HERETIC_MODEL || "poe-8b-heretic",
      extra: {},
    });
  }

  if (env.SELFHOST_BASE_URL) {
    list.push({
      id: "selfhost",
      kind: "openai",
      url: env.SELFHOST_BASE_URL.replace(/\/$/, "") + "/chat/completions",
      key: env.SELFHOST_API_KEY || "cortex",
      model: env.SELFHOST_MODEL || "glm-5.3-flash",
      extra: {},
    });
  }

  if (env.GLM_API_KEY) {
    list.push({
      id: "glm",
      kind: "openai",
      url: "https://api.z.ai/api/paas/v4/chat/completions",
      key: env.GLM_API_KEY,
      model: env.GLM_MODEL || "glm-5.3",
      extra: { thinking: { type: "enabled" }, reasoning_effort: "high" },
      extraFast: { reasoning_effort: "low" },
    });
  }

  if (env.GROQ_API_KEY) {
    list.push({
      id: "groq",
      kind: "openai",
      url: "https://api.groq.com/openai/v1/chat/completions",
      key: env.GROQ_API_KEY,
      model: env.GROQ_MODEL || "moonshotai/kimi-k2-instruct",
      extra: {},
    });
  }

  if (env.CEREBRAS_API_KEY) {
    list.push({
      id: "cerebras",
      kind: "openai",
      url: "https://api.cerebras.ai/v1/chat/completions",
      key: env.CEREBRAS_API_KEY,
      model: env.CEREBRAS_MODEL || "llama-3.3-70b",
      extra: {},
    });
  }

  if (env.OPENROUTER_API_KEY) {
    list.push({
      id: "openrouter",
      kind: "openai",
      url: "https://openrouter.ai/api/v1/chat/completions",
      key: env.OPENROUTER_API_KEY,
      model: env.OPENROUTER_MODEL || "meta-llama/llama-3.3-70b-instruct:free",
      extra: {},
      headers: { "HTTP-Referer": "https://cortanime.eu", "X-Title": "Cortex Void" },
    });
  }

  if (env.TOGETHER_API_KEY) {
    list.push({
      id: "together",
      kind: "openai",
      url: "https://api.together.xyz/v1/chat/completions",
      key: env.TOGETHER_API_KEY,
      model: env.TOGETHER_MODEL || "meta-llama/Llama-3.3-70B-Instruct-Turbo-Free",
      extra: {},
    });
  }

  if (env.GEMINI_API_KEY) {
    list.push({ id: "gemini", kind: "gemini", key: env.GEMINI_API_KEY, model: env.GEMINI_MODEL || "gemini-3.5-flash" });
    list.push({ id: "gemini-lite", kind: "gemini", key: env.GEMINI_API_KEY, model: env.GEMINI_MODEL_LITE || "gemini-3.5-flash-lite" });
  }

  return list;
}

function pickChain(tier, env) {
  const available = engines(env);
  const wanted = TIERS[tier].chain;
  const ordered = [];
  for (const id of wanted) {
    for (const engine of available) {
      if (engine.id === id) ordered.push(engine);
    }
  }
  // Anything configured but not named in the tier still gets a last chance.
  for (const engine of available) if (!ordered.includes(engine)) ordered.push(engine);
  // A lánc a mért sebesség szerint rendeződik: amelyik motor legutóbb gyorsan válaszolt,
  // előre kerül. A Phantom hárompasszos sorrendje érintetlen.
  if (tier !== "phantom") {
    const speed = (engine) => {
      const row = stats.get(engine.id);
      return row && row.lastMs ? row.lastMs : Number.MAX_SAFE_INTEGER;
    };
    ordered.sort((a, b) => speed(a) - speed(b));
  }
  return ordered;
}

function openAiBody(engine, messages, tier, stream, identity) {
  const body = {
    model: engine.model,
    messages: [{ role: "system", content: identity || (tier === "phantom" ? PHANTOM_IDENTITY : IDENTITY) }, ...messages],
    stream: !!stream,
    max_tokens: 8192,
  };
  if (engine.id === "glm") Object.assign(body, tier === "void-fast" ? { ...engine.extra, ...engine.extraFast } : engine.extra);
  return body;
}

async function openAiCall(engine, messages, tier, stream, identity, timeoutMs) {
  const r = await fetch(engine.url, {
    method: "POST",
    headers: { Authorization: `Bearer ${engine.key}`, "Content-Type": "application/json", ...(engine.headers || {}) },
    body: JSON.stringify(openAiBody(engine, messages, tier, stream, identity)),
    // Egy lassú szolgáltató ne tartsa fogva a választ: a lánc a következő motort kapja.
    signal: AbortSignal.timeout(timeoutMs || (stream ? 120000 : 30000)),
  });
  if (!r.ok) throw new UpstreamError(r.status, (await r.text()).slice(0, 200));
  return r;
}

function geminiBody(messages, stream) {
  const contents = [
    { role: "user", parts: [{ text: IDENTITY }] },
    { role: "model", parts: [{ text: "Értem, Cortex Void vagyok." }] },
    ...messages.map((m) => ({ role: m.role === "assistant" ? "model" : "user", parts: [{ text: m.content }] })),
  ];
  return { contents, generationConfig: { maxOutputTokens: 8192, temperature: 0.9 } };
}

async function geminiCall(engine, messages, stream, timeoutMs) {
  const verb = stream ? "streamGenerateContent?alt=sse&" : "generateContent?";
  const r = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${engine.model}:${verb}key=${engine.key}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(geminiBody(messages, stream)),
    signal: AbortSignal.timeout(timeoutMs || (stream ? 120000 : 30000)),
  });
  if (!r.ok) throw new UpstreamError(r.status, (await r.text()).slice(0, 200));
  return r;
}

class UpstreamError extends Error {
  constructor(status, body) { super(`upstream ${status}: ${body}`); this.status = status; }
}

// ── Streaming plumbing ────────────────────────────────────────────────────────

// Every stream ends the same way: one last event that says where the answer came from
// and how long it took. The app draws the source chips and the latency from it, and the
// browser chat simply ignores the extra keys.
function sseDone(ch, meta, layer, sources, started, extra = {}) {
  ch.send({ done: true, ...meta, layer, sources: sources || [], ms: Math.max(0, Date.now() - started), ...extra });
  ch.close();
}

function sseChannel() {
  let ctrl;
  const stream = new ReadableStream({ start(c) { ctrl = c; } });
  const enc = new TextEncoder();
  return {
    stream,
    send(obj) { try { ctrl.enqueue(enc.encode(`data: ${JSON.stringify(obj)}\n\n`)); } catch {} },
    close() { try { ctrl.enqueue(enc.encode("data: [DONE]\n\n")); ctrl.close(); } catch {} },
    error(msg) { try { ctrl.enqueue(enc.encode(`data: ${JSON.stringify({ error: msg })}\n\n`)); ctrl.close(); } catch {} },
  };
}

async function* sseLines(resp) {
  const reader = resp.body.getReader();
  const dec = new TextDecoder();
  let buf = "";
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    buf += dec.decode(value, { stream: true });
    const parts = buf.split("\n");
    buf = parts.pop() || "";
    for (const line of parts) {
      const t = line.trim();
      if (!t.startsWith("data:")) continue;
      const payload = t.slice(5).trim();
      if (!payload || payload === "[DONE]") continue;
      try { yield JSON.parse(payload); } catch {}
    }
  }
}

function textFromGemini(node) {
  const out = [];
  for (const c of node.candidates || []) for (const p of (c.content && c.content.parts) || []) if (p.text) out.push(p.text);
  return out.join("");
}

async function relay(engine, messages, tier, sink, identity) {
  const started = Date.now();
  const upstream = engine.kind === "gemini" ? await geminiCall(engine, messages, true) : await openAiCall(engine, messages, tier, true, identity);
  if (engine.kind === "gemini") {
    for await (const ev of sseLines(upstream)) {
      const t = textFromGemini(ev);
      if (t) sink(t);
    }
  } else {
    for await (const ev of sseLines(upstream)) {
      const d = ev.choices && ev.choices[0] && ev.choices[0].delta;
      // Content only: a reasoning stream must never reach the transcript (it can also
      // name the upstream model, and the app only ever speaks as Cortex Void).
      const t = d && d.content;
      if (t) sink(t);
    }
  }
  markOk(engine.id, Date.now() - started);
}

const isCapacityError = (message) => /(^|\D)(429|503)(\D|$)|high demand|overloaded|capacity|temporarily unavailable|try again/i.test(String(message));
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

/// Egy motor, egy második esély. A "high demand" gyakran csak az adott kérésre igaz,
/// ezért 400 ms után ugyanaz a motor még válaszolhat — így egy múló hiba nem viszi el
/// a választ a lánc végére.
async function collectSticky(engine, messages, tier, identity) {
  try {
    return await collect(engine, messages, tier, identity);
  } catch (e) {
    if (!isCapacityError(e.message)) throw e;
    await sleep(400);
    return await collect(engine, messages, tier, identity);
  }
}

async function collect(engine, messages, tier, identity) {
  const started = Date.now();
  if (engine.kind === "gemini") {
    const r = await geminiCall(engine, messages, false);
    const data = await r.json();
    markOk(engine.id, Date.now() - started);
    return textFromGemini(data);
  }
  const r = await openAiCall(engine, messages, tier, false, identity);
  const data = await r.json();
  markOk(engine.id, Date.now() - started);
  return (data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content) || "";
}

// ── Cortex Phantom: three passes, one voice ─────────────────────────────────
// Each engine we can reach on a free plan is ordinary on its own. Phantom runs three
// of them in a line — draft, critique, final — so the text that reaches the app is
// better than any single one could give. Every model name stays on this side of the
// wall; the client only ever sees "Cortex Phantom".

const PHANTOM = { draftMs: 18000, criticMs: 12000, finalMs: 120000, budgetMs: 22000, codeHints: ["kód", "kod", "function", "swift", "python", "javascript", "sql", "hiba", "error", "refactor", "api", "regex"] };

function phantomModels(env) {
  return {
    draft: env.PHANTOM_DRAFT_MODEL || "mistralai/mistral-large-2512",
    critic: env.PHANTOM_CRITIC_MODEL || "cohere/command-a-plus",
    // Mistral answers a full code block in ~12 s where the biggest free engine needs ~39 s
    // for the same output; the depth comes from the three passes, not from one slow model.
    final: env.PHANTOM_FINAL_MODEL || "mistralai/mistral-large-2512",
    // Short, non-technical questions do not need the strongest (and slowest) engine.
    quick: env.PHANTOM_QUICK_MODEL || "mistralai/mistral-large-2512",
  };
}

function xkiroBase(env) {
  return (env.XKIRO_BASE_URL || "https://api.xkiro.com/v1").replace(/\/$/, "");
}

async function phantomCall(env, model, messages, { stream = false, maxTokens = 4096, timeout = 30000, temperature } = {}) {
  if (!env.XKIRO_API_KEY) throw new UpstreamError(503, "engine missing");
  const body = { model, messages, stream, max_tokens: maxTokens };
  if (typeof temperature === "number") body.temperature = temperature;
  const r = await fetch(`${xkiroBase(env)}/chat/completions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${env.XKIRO_API_KEY}`, "Content-Type": "application/json" },
    body: JSON.stringify(body),
    signal: AbortSignal.timeout(timeout),
  });
  if (!r.ok) throw new UpstreamError(r.status, (await r.text()).slice(0, 200));
  return r;
}

async function phantomText(env, model, messages, opts) {
  const r = await phantomCall(env, model, messages, opts);
  const data = await r.json();
  const out = data.choices && data.choices[0] && data.choices[0].message && data.choices[0].message.content;
  return typeof out === "string" ? out.trim() : "";
}

/** Long or technical asks get the full three-pass treatment; small talk does not. */
function wantsDeepPass(messages) {
  const last = [...messages].reverse().find((m) => m.role === "user");
  const text = (last && last.content) || "";
  if (text.length > 240) return true;
  const low = text.toLowerCase();
  return PHANTOM.codeHints.some((h) => low.includes(h));
}

async function phantomPrepare(env, messages) {
  const models = phantomModels(env);
  let draft = "";
  let critique = "";
  const started = Date.now();
  if (wantsDeepPass(messages)) {
    const lastUser = (messages[messages.length - 1] || {}).content || "";
    try {
      draft = await phantomText(env, models.draft,
        [{ role: "system", content: PHANTOM_IDENTITY }, ...messages],
        { maxTokens: 700, timeout: PHANTOM.draftMs, temperature: 0.6 });
    } catch { draft = ""; }
    // A slow draft must not eat the whole budget: skip the critique rather than make
    // the user wait twice.
    if (draft && Date.now() - started < PHANTOM.budgetMs) {
      try {
        critique = await phantomText(env, models.critic, [
          { role: "system", content: "Te egy szigorú lektor vagy. Csak a hibákra koncentrálsz, dicséret nélkül." },
          { role: "user", content: `Kérdés: ${String(lastUser).slice(0, 4000)}\n\nVázlat:\n${draft.slice(0, 6000)}\n\nSorolj fel maximum 6 tömör pontot: mi hiányzik, mi pontatlan, mi lenne jobb sorrendben. Ha nincs érdemi hiba, csak ennyit írj: RENDBEN.` },
        ], { maxTokens: 350, timeout: PHANTOM.criticMs, temperature: 0.2 });
      } catch { critique = ""; }
    }
  }
  const finalMessages = [{ role: "system", content: PHANTOM_IDENTITY }, ...messages];
  const usefulCritique = critique && !/^rendben\.?$/i.test(critique.trim());
  if (draft && usefulCritique) {
    finalMessages.push({
      role: "system",
      content: `Egy korábbi vázlat és a lektor észrevételei (ezeket soha ne említsd, ne írd le, hogy vázlat vagy lektor volt):\nVÁZLAZ:\n${draft.slice(0, 6000)}\n\nLEKTOR:\n${critique.slice(0, 1500)}\n\nÍrd meg a végleges választ: javítsd a hibákat, egészítsd ki a hiányt, tartsd meg, ami jó.`,
    });
  } else if (draft) {
    finalMessages.push({ role: "system", content: "A vázlat már jó. Írd meg a végleges választ ugyanazzal a tartalommal, csiszoltabban — ne említsd, hogy vázlat volt." });
  }
  return { models, deep: Boolean(draft), finalMessages };
}

async function phantomAnswer(env, messages) {
  const { models, deep, finalMessages } = await phantomPrepare(env, messages);
  const text = await phantomText(env, deep ? models.final : models.quick, finalMessages,
    { maxTokens: 8192, timeout: PHANTOM.finalMs, temperature: 0.7 });
  if (!text) throw new UpstreamError(503, "empty");
  return text;
}

async function phantomChat(env, messages, meta, started) {
  const channel = sseChannel();
  const run = (async () => {
    channel.send({ meta, stage: "thinking" });
    let prepared = null;
    try {
      prepared = await phantomPrepare(env, messages);
    } catch { prepared = null; }
    const engine = prepared
      ? { id: "xkiro", kind: "openai", model: prepared.deep ? prepared.models.final : prepared.models.quick, url: `${xkiroBase(env)}/chat/completions`, key: env.XKIRO_API_KEY, extra: {} }
      : null;
    if (engine) {
      try {
        await relay(engine, prepared.finalMessages, "phantom", (t) => channel.send({ delta: t }), PHANTOM_IDENTITY);
        sseDone(channel, meta, "phantom", [], started);
        return;
      } catch { /* fall through to the generic chain below */ }
    }
    // The three-pass line failed: answer through the normal chain so the user still gets text.
    const chain = pickChain("phantom", env).filter((e) => !benched(e.id));
    for (const candidate of chain) {
      try {
        await relay(candidate, messages, "phantom", (t) => channel.send({ delta: t }), PHANTOM_IDENTITY);
        sseDone(channel, meta, "phantom", [], started);
        return;
      } catch (e) {
        benchProvider(candidate.id, e.message);
      }
    }
    channel.error("Cortex Phantom is busy right now. Try again in a moment.");
  })();
  return new Response(channel.stream, {
    headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", Connection: "keep-alive", ...cors },
  });
}

// ── Cortex Phantom brain: exact answers without any engine ───────────────────
// Catalogue numbers, maths, dates and identity are not opinions. When the brain can
// answer, the answer is instant, exact and never touches a provider — and it cannot
// leak a model name, because no model is involved.
let BRAIN_CACHE = { at: 0, value: null, series: 0 };
const BRAIN_TTL_MS = 5 * 60 * 1000;
const CATALOG_KEY = "cortexai/phantom/catalog.json";
const CATALOG_FRESH_MS = 20 * 60 * 60 * 1000;

// The brain keeps its own copy of the catalogue in R2 and refreshes it once a day,
// so a catalogue change reaches the answers without a deploy.
async function refreshCatalog(env, url) {
  if (!env.CORTEX_R2) return null;
  try {
    const head = await env.CORTEX_R2.head(CATALOG_KEY);
    if (head && head.uploaded && Date.now() - new Date(head.uploaded).getTime() < CATALOG_FRESH_MS) return head;
    const origin = url ? new URL(url).origin : "https://cortanime.eu";
    const r = await fetch(origin + "/api/hu-catalog", { cf: { cacheTtl: 600 } });
    if (!r.ok) return head;
    const body = await r.text();
    await env.CORTEX_R2.put(CATALOG_KEY, body, { httpMetadata: { contentType: "application/json" } });
    return head;
  } catch { return null; }
}

async function phantomBrain(env, url) {
  const now = Date.now();
  if (BRAIN_CACHE.value && now - BRAIN_CACHE.at < BRAIN_TTL_MS) return BRAIN_CACHE.value;
  await refreshCatalog(env, url);
  const brain = await Brain.load(env);
  BRAIN_CACHE = { at: now, value: brain, series: brain.series.length };
  return brain;
}

function lastUserMessage(messages) {
  for (let i = messages.length - 1; i >= 0; i--) {
    if (messages[i].role === "user") return messages[i].content || "";
  }
  return "";
}

async function brainAnswer(env, messages, url) {
  const question = lastUserMessage(messages);
  if (!question || question.length > 600) return null;
  try {
    const brain = await phantomBrain(env, url);
    const result = brain.answer(question);
    if (result.confident && result.text) return result;
  } catch { /* az agy hibája sose állítsa meg a választ */ }
  return null;
}

// ── A Phantom teljes lánca: agy → tudástár → kereső ──────────────────────────
// Az első kettő motor nélkül, azonnal válaszol. A harmadik a hálózatról hozza a tényt,
// megmondja a forrást, és eltárolja — a következő ugyanolyan kérdés már a tudástárból jön.
// Amit nem tudunk megválaszolni, az bekerül a kérdésnaplóba, és abból tanul a modell.
async function phantomAnswerLayers(env, question, { url = "", allowSearch = true } = {}) {
  const t0 = Date.now();
  const brain = await phantomBrain(env, url);
  let result = null;
  try { result = brain.answer(question); } catch { result = null; }
  if (result && result.confident && result.text) {
    await logQuestion(env, question, { kind: result.kind, ok: true });
    return { ...result, layer: "brain", ms: Date.now() - t0, series: brain.series.length };
  }

  // 2) tudástár: amit egyszer már kiderítettünk
  const known = await knowledgeLookup(env, question);
  if (known) {
    await logQuestion(env, question, { kind: known.kind, ok: true });
    return { ...known, layer: "knowledge", ms: Date.now() - t0, series: brain.series.length };
  }

  // 3) kereső: Wikipédia / AniList / DuckDuckGo, forrásmegjelöléssel
  if (allowSearch) {
    let hit = null;
    try { hit = await search(env, question, { anime: looksAnime(question) }); } catch { hit = null; }
    const composed = compose(question, hit);
    if (composed) {
      await knowledgeStore(env, question, composed.text, composed.sources, "search");
      await logQuestion(env, question, { kind: "search", ok: true });
      return { ...composed, layer: "search", confident: true, ms: Date.now() - t0, series: brain.series.length };
    }
  }

  await logQuestion(env, question, { kind: "open", ok: false });
  return { text: "", kind: "open", confident: false, sources: [], layer: "none",
           ms: Date.now() - t0, series: brain.series.length };
}

// ── Routes ────────────────────────────────────────────────────────────────────

// A kereső találat önmagában nyers: egy Wikipédia-kivonat nem válasz arra, hogy
// „ki írta”. Ezért a találatot még egyszer átvezetjük egy gyors motoron, kizárólag
// abból dolgozva — így a válasz a kérdésre felel, a tény pedig a forrásból jön.
// Ha bármi elakad, a nyers találat marad, mert az is jobb a semminél.
async function groundAnswer(env, question, hit) {
  if (!hit || !hit.text || !question) return hit;
  const engine = pickChain("void-fast", env).filter((e) => !benched(e.id))[0];
  if (!engine) return hit;
  const source = String(hit.text).slice(0, 2600);
  const messages = [
    {
      role: "system",
      content:
        (hit.kind === "news"
          ? "Friss hírekből dolgozol. A forrás mai hírcímek dátumokkal. Foglald össze magyarul, " +
            "legfeljebb 4 mondatban vagy 3 pontban, a legfontosabbat elöl. Csak azt írd, ami a " +
            "címekben benne van; a dátumot mindig tüntesd fel. Ne írj felvezetőt."
          : "Forrás-alapú válaszadó vagy. Kizárólag a megadott forrásból válaszolj, magyarul, " +
            "tömören (legfeljebb 3 mondat), a kérdésre egyenesen. Ha a kérdés több adatot kér, " +
            "mindegyikre válaszolj, amit a forrás tartalmaz. Ha valamit a forrás nem tartalmaz, " +
            "csak arra az egyre mondd meg, hogy nem szerepel benne. Ne írj felvezetőt."),
    },
    { role: "user", content: "Kérdés: " + question + "\n\nForrás:\n" + source },
  ];
  try {
    const text = await Promise.race([
      collect(engine, messages, "void-fast"),
      new Promise((resolve) => setTimeout(() => resolve(""), 9000)),
    ]);
    // A motor néha a saját bemutatkozásával kezd („Cortex Void, az OmegaTech és …”).
    // Forrásválaszban ez zaj: levágjuk az éléről.
    let clean = String(text || "").trim();
    const firstLine = clean.split("\n")[0] || "";
    if (/^cortex\s+(void|phantom)\b/i.test(firstLine)) {
      clean = clean.split("\n").slice(1).join("\n").trim();
    }
    if (clean.length > 12 && clean.length < 1200) return { ...hit, text: clean };
  } catch { /* a nyers találat is használható */ }
  return hit;
}

/** Kifejezett futtatás-kérés: ilyenkor a sandbox megy az agy elé. */
function wantsRun(text) {
  const low = String(text || "").toLowerCase();
  if (!low || low.length > 800) return false;
  return /(futtasd|futtatni|futtass|lefuttat|koddal|kóddal|irj egy (kod|program|script)|írj egy (kód|program|script)|\bpython\b|\bjavascript\b|\btypescript\b|\bsql\b|\bregex\b|scriptet)/.test(low);
}

// ── Napi brief ───────────────────────────────────────────────────────────────
// A nap: mi jön ki ma, és mi történt a hírekben. Nem modellhívás — gyors, és
// ugyanazt adja az appnak és a webnek. 15 percig gyorsítótárazva.

let DAILY_CACHE = { at: 0, key: "", value: null };

function budapestDay(offsetDays = 0) {
  const now = new Date(Date.now() + offsetDays * 86_400_000);
  return new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit",
  }).format(now).replace(/\.\s*/g, "-").replace(/-+$/, "");
}

function budapestStamp() {
  return new Intl.DateTimeFormat("hu-HU", {
    timeZone: "Europe/Budapest", year: "numeric", month: "2-digit", day: "2-digit",
    hour: "2-digit", minute: "2-digit",
  }).format(new Date());
}

async function dailyBrief(env) {
  const day = budapestDay();
  const key = `cortexai/daily/${day}.json`;
  if (DAILY_CACHE.value && DAILY_CACHE.key === day && Date.now() - DAILY_CACHE.at < 15 * 60_000) {
    return DAILY_CACHE.value;
  }
  if (env.CORTEX_R2) {
    try {
      const obj = await env.CORTEX_R2.get(key);
      if (obj) {
        const stored = JSON.parse(await obj.text());
        if (stored && stored.news && stored.news.length) {
          DAILY_CACHE = { at: Date.now(), key: day, value: stored };
          return stored;
        }
      }
    } catch { /* frissítjük */ }
  }

  // A kettő párhuzamosan fut: a lassabb forrás ne tartsa fogva a választ.
  const feedTask = (async () => {
    try {
      const res = await fetch("https://cortanime.eu/api/app/epfeed", {
        headers: { "User-Agent": "CortexAI/2.6" },
        signal: AbortSignal.timeout(6000),
      });
      if (!res.ok) return [];
      const data = await res.json();
      const now = Date.now();
      return (data.items || [])
        .filter((it) => Number(it.ts) > now - 3 * 3_600_000)
        .sort((a, b) => Number(a.ts) - Number(b.ts))
        .slice(0, 4)
        .map((it) => ({
          title: String(it.title || "").slice(0, 80),
          ep: Number(it.ep) || 0,
          aid: Number(it.aid) || 0,
          at: new Date(Number(it.ts)).toISOString(),
        }));
    } catch { return []; }
  })();
  const newsTask = (async () => {
    try {
      const rows = await topNews(3);
      return rows.map((it) => ({
        title: it.title.slice(0, 120), source: it.source, date: it.date, link: it.link,
      }));
    } catch { return []; }
  })();

  const [nextRows, headlineRows] = await Promise.all([feedTask, newsTask]);
  const next = nextRows;
  const headlines = headlineRows;

  const first = next[0];
  const line = first
    ? `Ma ${next.length} adás jön; a következő: ${first.title} — ${first.ep}. rész.`
    : "Ma nincs új adás a naptárban — a hírek viszont frissülnek.";

  const value = { date: day, stamp: budapestStamp(), next, news: headlines, line };
  DAILY_CACHE = { at: Date.now(), key: day, value };
  if (env.CORTEX_R2) {
    try {
      await env.CORTEX_R2.put(key, JSON.stringify(value), { httpMetadata: { contentType: "application/json" } });
    } catch { /* nem baj */ }
  }
  return value;
}

// ── Sablonok ─────────────────────────────────────────────────────────────────
// Nyolc induló feladat, mind magyarul, mind valódi munkára. A kliens ezt listázza.

const TEMPLATES = [
  { id: "summarize", icon: "doc.text", title: "Hosszú szöveg tömören", hint: "Dokumentum vagy cikk 5 pontban", prompt: "Foglald össze az alábbi szöveget 5 pontban, a legfontosabb állítással kezdve." },
  { id: "translate", icon: "character.bubble", title: "Fordítás magyarra", hint: "Természetes, nem szó szerinti", prompt: "Fordítsd le magyarra természetes, olvasmányos stílusban, a szakszavakat hagyva meg." },
  { id: "reply", icon: "envelope", title: "Válasz megírása", hint: "Levél, e-mail, üzenet", prompt: "Írj udvarias, rövid választ erre az üzenetre, és adj hozzá két alternatívát." },
  { id: "plan", icon: "checklist", title: "Terv és teendők", hint: "Célból lépések", prompt: "Bontsd lépésekre ezt a célt, határidőkkel és az első mai lépéssel." },
  { id: "explain", icon: "graduationcap", title: "Magyarázd el egyszerűen", hint: "Példával, szakszó nélkül", prompt: "Magyarázd el úgy, hogy egy középiskolás is megértse, egy hétköznapi példával." },
  { id: "code", icon: "chevron.left.forwardslash.chevron.right", title: "Kód és javítás", hint: "Írás, hiba keresése", prompt: "Írd meg a kért kódot, majd futtasd le és magyarázd el a kimenetet." },
  { id: "research", icon: "binoculars", title: "Mély kutatás", hint: "Több forrás, hivatkozásokkal", prompt: "Kutass utána több forrásból, és foglald össze számozott hivatkozásokkal." },
  { id: "image", icon: "photo", title: "Kép elemzése", hint: "Fotó, képernyőkép, rajz", prompt: "Nézd meg a képet, és mondd el, mi látható rajta, majd olvasd ki a szöveget." },
];


// ══ Ügynök mód (2.9) ════════════════════════════════════════════════════════
// Nem egyetlen motorhívás: előbb összegyűjti, ami kell, aztán ír. A lépések
// látszanak is — a UI soronként kapja őket, így nem néma másodpercek telnek el.

const LAYER_HITS = { kb: 0, news: 0, brain: 0, engine: 0, agent: 0, search: 0, vision: 0, sandbox: 0 };
// A Workers a modul betöltésekor fagyasztott (0) időt ad — ezért az első kérésnél
// jegyezzük fel, mióta él ez a példány.
let BOOT_ISO = "";
function bootTime() {
  if (!BOOT_ISO) BOOT_ISO = new Date().toISOString();
  return BOOT_ISO;
}

function bumpLayer(name) {
  if (name in LAYER_HITS) LAYER_HITS[name] += 1;
}

/** Mi kell ehhez a kérdéshez? A sorrend nem véletlen: a biztos adat megy előre. */
function agentPlan(question) {
  const q = fold(String(question || ""));
  const plan = [];
  plan.push({ tool: "question", label: "Kérdés értelmezése" });
  if (/(studio|rendezo|mikor|hany resz|pontszam|mufaj|felirat|szol|alkoto|zene|hol nezzem|ajanl|hasonlo|evad|resze|resz|ki i|ki csin|ki rendez)/.test(q)) {
    plan.push({ tool: "kb", label: "Katalógus-adatok (tudásbázis)" });
  }
  if (/(hir|friss|legujabb|ma |mai |bejelentett|megjelent|trailer|ki nyert)/.test(q)) {
    plan.push({ tool: "news", label: "Mai hírek (IGN, 444, Telex)" });
  }
  if (/[0-9]\s*[\+\-\*\/\^%]|[0-9]\s*(plusz|minusz|szorozva|osztva)|\bszamold\b|\bmennyi\b/.test(q)) {
    plan.push({ tool: "math", label: "Számítás" });
  }
  // Ha a fentiek egyike sem illik, vagy a kérdés hosszú: forrás és lexikon is.
  if (plan.length === 1 || question.length > 60) {
    plan.push({ tool: "web", label: "Források (web)" });
  }
  plan.push({ tool: "write", label: "Válasz összeállítása" });
  return plan;
}

/**
 * Az ügynök futása. Visszaadja a szöveget, a megtett lépéseket és a forrásokat.
 * A `onStep` hívás minden lépésnél lefut, hogy a stream közben is látszódjon.
 */
async function runAgent(env, question, tierKey, onStep = () => {}) {
  const steps = [];
  const evidence = [];
  const sources = [];
  const started = Date.now();
  const plan = agentPlan(question);

  const step = (label, detail, ms, ok = true) => {
    const row = { label, detail, ms, ok };
    steps.push(row);
    try { onStep(row); } catch { /* a stream bezárult */ }
  };

  step("Kérdés értelmezése", `${plan.length - 1} eszköz`, 0);

  // ── Eszközök párhuzamosan ────────────────────────────────────────────────
  const jobs = [];
  if (plan.some((p) => p.tool === "kb")) {
    jobs.push((async () => {
      const t = Date.now();
      const fact = await kbAnswer(env, question).catch(() => null);
      const ctx = await kbContext(env, question).catch(() => "");
      if (fact?.text) {
        evidence.push(`[katalógus] ${fact.text}`);
        (fact.sources || []).forEach((u) => sources.push(u));
        step("Tudásbázis", fact.text.slice(0, 90), Date.now() - t);
      } else if (ctx) {
        evidence.push(`[katalógus]\n${ctx}`);
        step("Tudásbázis", "adatok beolvasva", Date.now() - t);
      } else {
        step("Tudásbázis", "nincs egyező sorozat", Date.now() - t, false);
      }
    })());
  }
  if (plan.some((p) => p.tool === "news")) {
    jobs.push((async () => {
      const t = Date.now();
      // 1) a napi brief — instant, hálózat nélkül is naprakész
      const brief = await feedBrief(env).catch(() => null);
      if (brief?.headlines?.length) {
        const lines = brief.headlines.slice(0, 6)
          .map((h) => `${h.date || brief.date} ${h.title} (${h.source || ""})`.trim());
        if (brief.airing?.length) {
          lines.push("Mai anime-adás: " + brief.airing.slice(0, 4)
            .map((a) => `${a.title} ${a.episode}. ep`).join(" · "));
        }
        evidence.push(`[napi adatfolyam ${brief.date}]\n${lines.join("\n")}`);
        step("Napi adatfolyam", `${brief.counts?.headlines || 0} hír · ${brief.counts?.airing || 0} adás`, Date.now() - t);
      }
      // 2) élő keresés csak akkor, ha a brief nem ad választ
      const subject = newsSubject(question);
      let hit = await news(question, { limit: 4 }).catch(() => null);
      if ((!hit?.items?.length) && !subject.length) {
        const top = await topNews(4).catch(() => []);
        if (top.length) hit = { items: top, sources: top.map((i) => i.link).filter(Boolean) };
      }
      if (hit?.items?.length) {
        const lines = hit.items.map((it) => `${it.date || ""} ${it.title} (${it.source || ""})`.trim());
        evidence.push(`[hírek]\n${lines.join("\n")}`);
        (hit.sources || []).forEach((u) => sources.push(u));
        step("Hírek", `${hit.items.length} friss cím`, Date.now() - t);
      } else {
        step("Hírek", "nincs friss találat", Date.now() - t, false);
      }
    })());
  }
  if (plan.some((p) => p.tool === "math")) {
    jobs.push((async () => {
      const t = Date.now();
      const exact = await brainAnswer(env, [{ role: "user", content: question }], "https://cortanime.eu").catch(() => null);
      if (exact?.text) {
        evidence.push(`[számítás] ${exact.text}`);
        step("Számítás", exact.text.slice(0, 60), Date.now() - t);
      } else {
        step("Számítás", "nem kellett", Date.now() - t, false);
      }
    })());
  }
  if (plan.some((p) => p.tool === "web")) {
    jobs.push((async () => {
      const t = Date.now();
      const hit = compose(question, await search(env, question, { anime: looksAnime(question) }).catch(() => null));
      if (hit?.text) {
        evidence.push(`[forrás]\n${String(hit.text).slice(0, 1500)}`);
        (hit.sources || []).forEach((u) => sources.push(u));
        step("Webes forrás", hit.title || "találat", Date.now() - t);
      } else {
        step("Webes forrás", "nincs találat", Date.now() - t, false);
      }
    })());
  }
  await Promise.all(jobs);

  // ── Írás ────────────────────────────────────────────────────────────────
  const engine = pickChain(tierKey, env).filter((e) => !benched(e.id))[0];
  const tWrite = Date.now();
  if (!engine) {
    step("Válasz összeállítása", "nincs elérhető motor", 0, false);
    return { text: "", steps, sources: [...new Set(sources)].slice(0, 4) };
  }
  const system =
    "Cortex ügynök vagy. Előbb adatot gyűjtesz, aztán írsz. Szabályok:\n" +
    "1) Csak azt állítsd, ami a begyűjtött adatokban benne van; ami nincs, arról mondd meg, hogy nincs.\n" +
    "2) A katalógus-adat (stúdió, rendező, év, pontszám, részek) a mérvadó — ezt ne becsüld felül.\n" +
    "3) Ha hírt kértek, mindig írd oda a dátumot, és csak a begyűjtött címekből dolgozz.\n" +
    "4) Magyarul, tömören; pontokba szedve, ha több dolog van. Ne írj felvezetőt, ne ismételd a kérdést.";
  const user =
    `Kérdés: ${question}\n\n` +
    (evidence.length ? `Begyűjtött adatok:\n${evidence.join("\n\n")}` : "Begyűjtött adatok: nincs találat — ezt mondd meg, és ajánlj mást.");
  let text = "";
  try {
    text = await Promise.race([
      collect(engine, [{ role: "system", content: system }, { role: "user", content: user }], tierKey),
      new Promise((resolve) => setTimeout(() => resolve(""), 22_000)),
    ]);
  } catch { text = ""; }
  const clean = String(text || "").trim();
  step("Válasz összeállítása", clean ? `${clean.split(/\s+/).length} szó` : "nem jött válasz", Date.now() - tWrite, !!clean);

  if (!clean) {
    // Ha a motor kiesik, a legjobb begyűjtött tény akkor is válasz.
    const fallback = evidence[0]?.replace(/^\[[^\]]+\]\s*/, "") || "";
    return { text: fallback || "Nem sikerült választ összeállítani. Próbáld újra egy perc múlva.", steps, sources: [...new Set(sources)].slice(0, 4) };
  }
  return { text: clean, steps, sources: [...new Set(sources)].slice(0, 4), ms: Date.now() - started };
}

// ══ Feladatok (2.9) ═════════════════════════════════════════════════════════
// Ütemezett kérések: a telefon helyben ébreszti, a worker csak a listát tartja,
// hogy eszközváltásnál is meglegyen. Nincs fiók — a kliens-azonosító a kulcs.

const TASKS_KEY = "cortexai/tasks/index.json";
const TASKS_MAX = 200;

async function readTasks(env) {
  if (!env.CORTEX_R2) return [];
  try {
    const obj = await env.CORTEX_R2.get(TASKS_KEY);
    if (!obj) return [];
    const rows = JSON.parse(await obj.text());
    return Array.isArray(rows) ? rows : [];
  } catch { return []; }
}

async function writeTasks(env, rows) {
  if (!env.CORTEX_R2) return false;
  await env.CORTEX_R2.put(TASKS_KEY, JSON.stringify(rows.slice(-TASKS_MAX)), {
    httpMetadata: { contentType: "application/json" },
  });
  return true;
}

function clientOf(request, url) {
  const raw = request.headers.get("X-Cortex-Client") || url.searchParams.get("client") || "";
  return String(raw).replace(/[^A-Za-z0-9-]/g, "").slice(0, 40);
}

// ══ Statisztika (2.9) ═══════════════════════════════════════════════════════

async function statsBody(env) {
  const kb = await kbStatus(env).catch(() => null);
  return {
    ok: true,
    version: VERSION,
    uptimeSec: Math.max(0, Math.round((Date.now() - Date.parse(bootTime())) / 1000)),
    since: bootTime(),
    note: "ez a példány (edge izolátum) számlálóit mutatja",
    layersIsolate: { ...LAYER_HITS },
    kb: kb ? { series: kb.series, facts: kb.facts, wiki: kb.wiki } : null,
    engines: engines(env).length,
  };
}

const VERSION = "3.1";

const FEATURES = {
  version: VERSION,
  updated: "2026-11-02",
  title: "Cortex AI 3.1",
  items: [
    { key: "projects", title: "Projektek", body: "Külön munkaterület saját utasítással és tudással; a beszélgetések nem keverednek." },
    { key: "canvas", title: "Vászon", body: "A hosszú válasz oldalsávban nyílik, ott szerkeszthető, másolható, megosztható." },
    { key: "research", title: "Mély kutatás", body: "Több forrás, számozott hivatkozások, látható kutatási lépések." },
    { key: "documents", title: "Dokumentumok", body: "PDF, DOCX, TXT, Markdown, CSV csatolása; a válasz a dokumentumból dolgozik." },
    { key: "memory", title: "Memória", body: "Amit megtanult rólad, megnézheted, szerkesztheted, törölheted." },
    { key: "branch", title: "Új ág", body: "Bármelyik üzenetről új beszélgetés indul, a korábbiak megtartásával." },
    { key: "compare", title: "Két hangnem", body: "Ugyanaz a kérdés két stílusban, egymás mellett." },
    { key: "templates", title: "Sablonok", body: "Nyolc kész feladat egy koppintással." },
    { key: "share", title: "Megosztás", body: "Olvasható link a beszélgetésről, 30 napig, személyes adat nélkül." },
    { key: "incognito", title: "Ideiglenes chat", body: "Nem megy a tudástárba, nem kerül a memóriába, nem marad meg." },
    { key: "news", title: "Friss hírek", body: "Időérzékeny kérdésnél nem emlékezetből válaszol: mai hírek, dátummal, forrással." },
    { key: "daily", title: "Napi kártya", body: "Ma mi jön ki, és mi történt — egy koppintással kérdezhetsz róla." },
    { key: "kb", title: "Tudásbázis", body: "Minden sorozathoz stúdió, rendező, évad, pontszám, részek, címkék — motor nélkül, azonnal." },
    { key: "kbsearch", title: "Tudásbázis-kereső", body: "Az appban és a weben is: cím, stúdió vagy rendező — találatból egy koppintás a kérdés." },
    { key: "controls", title: "Vezérlőközpont", body: "Két kapcsoló a Vezérlőközpontban és a zárképernyőn: Kérdezd a Cortexet, és Ma mi jön ki." },
    { key: "agent", title: "Ügynök mód", body: "Nem egyetlen válasz: előbb összegyűjti a katalógust, a hírt és a forrást, aztán ír — a lépések látszanak." },
    { key: "tasks", title: "Ütemezett feladatok", body: "Időzített kérés: a telefon helyben ébreszti, a lista eszközváltásnál is megvan." },
    { key: "phantomfree", title: "Phantom, szabadabban", body: "Nincs moralizálás és felesleges figyelmeztetés: egyenes vélemény, merész ötlet, konkrét válasz." },
    { key: "enginefailover", title: "Motorváltás hiba nélkül", body: "Ha egy szolgáltató tilt vagy kiesik, a Phantom csendben a következő motorra vált — a válasz nem marad el." },
    { key: "offline", title: "Offline mód", body: "A Phantom helyi motorja letölthető a telefonra: repülőgépen is válaszol, és egyetlen worker-kérést sem használ." },
    { key: "modelupdate", title: "Modellfrissítés", body: "Ha új modell jön, az app szól, és kiírja a letöltés méretét — a régi helyére kerül." },
  ],
};

// ── Dokumentum a beszélgetésben ──────────────────────────────────────────────
// A fájl szövegét a kliens nyeri ki (PDF: PDFKit, web: pdf.js), ide már csak szöveg jön.
// Így a worker nem hordoz PDF-motort, és a fájl nem kerül sehova: a kérés élettartamáig él.

const FILE_LIMIT = 4;
const FILE_CHARS = 24_000;
const FILE_TOTAL = 60_000;

function normalizeFiles(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  let total = 0;
  for (const item of raw.slice(0, FILE_LIMIT)) {
    if (!item || typeof item !== "object") continue;
    const name = String(item.name || "dokumentum").slice(0, 120);
    let text = String(item.text || "").replace(/\u0000/g, "").replace(/\r\n?/g, "\n").trim();
    if (!text) continue;
    text = text.slice(0, FILE_CHARS);
    const room = FILE_TOTAL - total;
    if (room <= 200) break;
    if (text.length > room) text = text.slice(0, room);
    total += text.length;
    out.push({ name, text });
  }
  return out;
}

// ── Következő kérdés javaslatai ──────────────────────────────────────────────
// Nem modellhívás: a válasz rétegéből és a katalógusból képzett, mindig odaillő kérdések.
// Ez az a apróság, amitől a felület „beszélgetni akar”, nem csak válaszolni.

const SUGGEST = {
  math: ["Számold ki lépésenként", "Mennyi 20%-kal növelve?", "Ugyanezt más számokkal"],
  catalog: ["Mennyi ideig tart megnézni?", "Van magyar felirata?", "Ajánlj hasonlót ehhez"],
  search: ["Hasonlítsd össze mással", "Mi a három legfontosabb pont?", "Honnan tudod?"],
  knowledge: ["Hasonlítsd össze mással", "Mi a három legfontosabb pont?", "Honnan tudod?"],
  vision: ["Olvasd ki a szöveget", "Mi van a háttérben?", "Foglald össze egy mondatban"],
  research: ["Csinálj belőle táblázatot", "Hol lehet a forrás gyenge pontja?", "Készíts 5 pontos összefoglalót"],
  sandbox: ["Futtasd nagyobb adaton", "Magyarázd el a kódot", "Mutasd a lépéseket"],
  document: ["Foglald össze 5 pontban", "Mi hiányzik belőle?", "Készíts belőle teendőlistát"],
  engine: ["Rövidebben is elmondod?", "Adj egy példát", "Mi a következő lépés?"],
};

function suggestFollowUps(layer, question, answer) {
  const text = String(answer || "");
  // „A(z) Solo Leveling 1. évad (…) sorozatnak 12 része van.” → a cím a zárójel előtt áll.
  const named = text.match(/A\(z\)\s+([^(){}\n]{2,40}?)(?=\s+\(|\s+\d+\.\s*évad|\s+sorozatnak|\s+része|\s+műfaja|[,.]|$)/);
  if (layer === "brain" && named && /rész|évad|epizód|sorozat/i.test(text)) {
    const name = named[1].trim();
    return [`Mennyi ideig tart megnézni a(z) ${name} sorozatot?`, `Van magyar felirata a(z) ${name}-nek?`, "Ajánlj hasonlót ehhez"];
  }
  return (SUGGEST[layer] || SUGGEST.engine).slice(0, 3);
}

// ── Mély kutatás ─────────────────────────────────────────────────────────────
// Több forrás, utána egy összefoglaló számozott hivatkozásokkal. Nem varázslat: két keresés
// és egy fogalmazó kör — de a válasz alatt ott vannak a források, amikből dolgozott.

async function researchAnswer(env, question, onStage = () => {}) {
  const started = Date.now();
  const base = String(question || "").trim();
  if (!base) return null;

  const stripped = base
    .replace(/\b(mi az|mi a|ki az|ki a|hogyan|mikor|hol|mennyi|melyik|mutasd be|mesélj|magyarázd el)\b/gi, " ")
    .replace(/\s+/g, " ")
    .trim();
  const queries = [...new Set([base, stripped].filter((q) => q && q.length > 3))].slice(0, 2);

  const hits = [];
  for (const q of queries) {
    onStage("Források keresése: " + q.slice(0, 70));
    const hit = await search(env, q, { anime: looksAnime(q) }).catch(() => null);
    if (hit && hit.text && hit.text.length > 40) {
      hits.push({ q, ...hit });
      if (hits.length >= 3) break;
    }
  }
  if (!hits.length) return null;

  onStage("Összefoglaló írása a forrásokból…");
  const sources = [];
  const blocks = hits.map((h, i) => {
    if (h.url && !sources.includes(h.url)) sources.push(h.url);
    return `[${i + 1}] ${h.title || h.source || "forrás"}\n${String(h.text).slice(0, 2200)}`;
  }).join("\n\n");

  const kbFacts = await kbContext(env, base).catch(() => "");
  const engine = pickChain("void-fast", env).filter((e) => !benched(e.id))[0];
  const messages = [
    {
      role: "system",
      content:
        "Kutató vagy. A megadott forrásokból készíts magyar nyelvű, tömör összefoglalót a kérdésre. " +
        "Minden állítás után tedd oda a forrás számát szögletes zárójelben, például [1]. Csak azt írd, " +
        "ami a forrásokban szerepel; ha valami hiányzik, mondd meg. Ha a források ellentmondanak, jelezd. " +
        "Legfeljebb 7 mondat vagy 5 pont.",
    },
    { role: "user", content: `Kérdés: ${base}${kbFacts ? "\n\nKatalógus-adatok (pontos):\n" + kbFacts : ""}\n\nForrások:\n${blocks}` },
  ];
  let text = "";
  if (engine) {
    try { text = await collect(engine, messages, "void-fast"); } catch { text = ""; }
  }
  if (!text || text.length < 30) {
    text = hits.map((h, i) => `[${i + 1}] ${String(h.text).slice(0, 400)}`).join("\n\n");
  }
  return { text: String(text).trim(), sources: sources.slice(0, 4), queries, ms: Date.now() - started };
}

// ── Beszélgetés megosztása ───────────────────────────────────────────────────
// Egy pillanatkép a válaszokból, olvasható oldalként. Semmi személyes nem megy bele
// (nincs eszközazonosító, nincs memória), és a link nem listázható.

const SHARE_TTL_DAYS = 30;

async function shareSave(env, messages, title) {
  if (!env.CORTEX_R2) return null;
  const rows = Array.isArray(messages) ? messages.slice(-60) : [];
  const clean = rows
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .map((m) => ({ role: m.role, content: m.content.slice(0, 6000) }))
    .filter((m) => m.content.trim());
  if (!clean.length) return null;
  const id = Array.from({ length: 10 }, () => "abcdefghijkmnpqrstuvwxyz23456789"[Math.floor(Math.random() * 32)]).join("");
  const payload = {
    id,
    title: String(title || clean[0].content).slice(0, 120),
    messages: clean,
    createdAt: new Date().toISOString(),
    expiresAt: new Date(Date.now() + SHARE_TTL_DAYS * 86_400_000).toISOString(),
  };
  await env.CORTEX_R2.put(`cortexai/share/${id}.json`, JSON.stringify(payload), {
    httpMetadata: { contentType: "application/json" },
  });
  return payload;
}

function escapeHtml(text) {
  return String(text)
    .replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;").replace(/'/g, "&#39;");
}

function sharePage(share) {
  const rows = share.messages.map((m) => {
    const who = m.role === "user" ? "te" : "Cortex";
    const body = escapeHtml(m.content).replace(/\n/g, "<br>");
    return `<article class="${m.role}"><div class="who">${who}</div><div class="body">${body}</div></article>`;
  }).join("\n");
  return `<!DOCTYPE html><html lang="hu"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${escapeHtml(share.title)} — Cortex AI</title>
<style>
:root{--ink:#050506;--surf:#0E0E11;--line:rgba(255,255,255,.08);--tx:#F5F5F7;--mut:#9A9AA8;--vio:#8B5CF6}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--ink);color:var(--tx);font:16px/1.6 -apple-system,BlinkMacSystemFont,"SF Pro Text",system-ui,sans-serif;padding:28px 18px 60px}
.wrap{max-width:720px;margin:0 auto}
header{display:flex;align-items:center;gap:10px;margin-bottom:22px;color:var(--mut);font-size:12px;letter-spacing:.4px}
.sigil{width:22px;height:22px;border-radius:50%;border:5px solid transparent;background:linear-gradient(135deg,#22D3EE,#8B5CF6,#E879F9) border-box;-webkit-mask:linear-gradient(#000 0 0) padding-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}
h1{font-size:20px;margin-bottom:20px;letter-spacing:-.3px}
article{margin-bottom:18px}
article .who{font-size:11px;font-weight:800;letter-spacing:.7px;text-transform:uppercase;color:var(--mut);margin-bottom:6px}
article.user .body{background:rgba(139,92,246,.16);border:1px solid rgba(139,92,246,.3);border-radius:16px;padding:12px 14px}
article.assistant .body{background:var(--surf);border:1px solid var(--line);border-radius:16px;padding:12px 14px}
footer{margin-top:26px;color:var(--mut);font-size:12px}
a{color:#B79CFF}
</style></head><body><div class="wrap">
<header><div class="sigil"></div><span>CORTEX AI — MEGOSZTOTT BESZÉLGETÉS</span></header>
<h1>${escapeHtml(share.title)}</h1>
${rows}
<footer>${escapeHtml(share.createdAt.slice(0, 10))} · OmegaTech × CortexAnime · <a href="https://cortanime.eu/ai">cortanime.eu/ai</a></footer>
</div></body></html>`;
}

// ── Kép a beszélgetésben ─────────────────────────────────────────────────────
// A telefonról érkező kép nem tárolódik: a kérés élettartamáig él, egy látó motor kapja
// meg, és a válasszal együtt eltűnik. A naplóba és a tudástárba nem kerül be.

const IMAGE_LIMIT = 3;              // egyszerre legfeljebb ennyi kép
const IMAGE_BYTES = 3_800_000;      // base64-ben, kb. 2,8 MB nyers kép
const IMAGE_MIMES = /^image\/(png|jpe?g|webp|gif|heic|heif)$/;

function normalizeImages(raw) {
  if (!Array.isArray(raw)) return [];
  const out = [];
  for (const item of raw.slice(0, IMAGE_LIMIT)) {
    if (typeof item === "string") {
      const match = item.match(/^data:([^;,]+);base64,(.+)$/i);
      if (match && IMAGE_MIMES.test(match[1]) && match[2].length < IMAGE_BYTES) {
        out.push({ mime: match[1].toLowerCase(), data: match[2] });
      }
      continue;
    }
    if (item && typeof item === "object") {
      const mime = String(item.mime || item.mimeType || "image/jpeg").toLowerCase();
      const data = String(item.data || item.base64 || "").replace(/^data:[^,]*,/, "");
      if (IMAGE_MIMES.test(mime) && data && data.length < IMAGE_BYTES) out.push({ mime, data });
    }
  }
  return out;
}

/** A látó válasz: Gemini inline képpel. Sose dob; null, ha nincs látó motor. */
async function visionAnswer(env, messages, images, question) {
  if (!env.GEMINI_API_KEY || !images.length) return null;
  const models = [...new Set([env.GEMINI_MODEL || "gemini-3.5-flash", "gemini-3.5-flash", "gemini-3.8-flash"])];
  const history = messages.slice(-8).map((m) => ({
    role: m.role === "assistant" ? "model" : "user",
    parts: [{ text: String(m.content).slice(0, 4000) }],
  }));
  // Az utolsó üzenethez kerülnek a képek — így a modell pontosan tudja, mire vonatkoznak.
  for (let i = history.length - 1; i >= 0; i -= 1) {
    if (history[i].role === "user") {
      for (const image of images) {
        history[i].parts.push({ inline_data: { mime_type: image.mime, data: image.data } });
      }
      break;
    }
  }
  if (!history.length) {
    history.push({ role: "user", parts: [{ text: question || "Mit látni a képen?" }] });
  }
  const started = Date.now();
  for (const model of models) {
    try {
      const response = await fetch(
        `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`,
        {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            systemInstruction: {
              parts: [{
                text: "Cortex Phantom vagy (OmegaTech × CortexAnime). A felhasználó képet küldött. " +
                  "Válaszolj magyarul, tömören, a képre konkrétan hivatkozva. Ha szöveg van a képen, " +
                  "olvasd ki pontosan. Ha valami nem látszik biztosan, mondd meg, hogy nem látszik. " +
                  "Sose találj ki olyat, ami nincs a képen.",
              }],
            },
            contents: history,
            generationConfig: { maxOutputTokens: 1200, temperature: 0.4 },
          }),
          signal: AbortSignal.timeout(45000),
        },
      );
      if (!response.ok) continue;
      const data = await response.json();
      const candidate = data.candidates && data.candidates[0];
      const text = ((candidate && candidate.content && candidate.content.parts) || [])
        .map((p) => p.text || "")
        .join("")
        .trim();
      if (text) return { text, model, ms: Date.now() - started };
    } catch { /* következő modell */ }
  }
  return null;
}

// ── Futó Linux a válasz mögött ────────────────────────────────────────────────
// Ha a kérdés számolást, futtatást vagy kódot kér, a modell kap egy eldobható Linux
// környezetet: kódot ír, az lefut, és a valódi kimenetből válaszol. A sandbox nélkül
// (nincs beállított SANDBOX_URL) ez a rész egyszerűen kimarad.
/** Kifejezett kutatás-kérés: itt nem elég egy találat, forrásokkal együtt kell válaszolni. */
function wantsResearch(text) {
  const low = String(text || "").toLowerCase();
  if (!low || low.length > 400) return false;
  return /(kutass|kutatas|kutatás|nezz utana|nézz utána|keress ra|keress rá|jard korul|járd körül|reszletesen (irj|elemezd)|részletesen (írj|elemezd)|tobb forras|több forrás|forrasokkal|forrásokkal|deep research|osszehasonlito elemzes|összehasonlító elemzés)/.test(low);
}

function wantsCompute(text) {
  const low = String(text || "").toLowerCase();
  if (!low || low.length > 800) return false;
  // Kifejezett futtatás- vagy kódkérés: itt a modell kódot ír, és a kimenet a válasz.
  if (/(futtasd|futtatni|lefuttat|teszteld|tesztelj|debugold|szimulal|szimulál|irj egy (kod|program|script)|írj egy (kód|program|script)|kodreszlet|kódrészlet|scriptet|parancssor|terminal|python|javascript|typescript|sql|regex|json|csv|szamold ki|számold ki|szamitsd ki|számítsd ki|kalkulal|kalkulál|allitsd elo|állítsd elő)/.test(low)) return true;
  // Számolás: legalább három szám és egy művelet, vagy sok szám egy feladatban.
  const digits = (low.match(/\d+(?:[.,]\d+)?/g) || []).length;
  return digits >= 3 && /[+\-*/=]|oszt|szoroz|osszead|kivon|atlag|median|szora|százal|szazal|%/.test(low);
}

const RUN_BLOCK = /```cortex-run\s+(\w+)\s*\n([\s\S]*?)```/g;

/** Egy kész válasz kiküldése — ugyanaz a szerződés stream és nem-stream módban is. */
function finishReply(computed, meta, body, started, json, sseChannel, sseDone, cors, layer = "sandbox", extra = {}) {
  const payload = { ...meta, layer, ...(computed.runs ? { runs: computed.runs } : {}), ...extra };
  if (body.stream === false) return json({ ok: true, ...payload, text: computed.text });
  const ch = sseChannel();
  ch.send({ meta, layer, ...(computed.runs ? { runs: computed.runs } : {}), ...(extra.research ? { research: extra.research } : {}) });
  const step = 24;
  for (let i = 0; i < computed.text.length; i += step) {
    ch.send({ delta: computed.text.slice(i, i + step) });
  }
  sseDone(ch, payload, layer, computed.sources || [], started, extra);
  return new Response(ch.stream, {
    headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
  });
}

/** A modell addig futtat, amíg futtatni kér — legfeljebb három körben. */
async function sandboxAnswer(env, messages, tierKey) {
  const chain = pickChain(tierKey, env).filter((e) => !benched(e.id));
  if (!chain.length) return null;
  const engine = chain[0];
  const working = [{ role: "system", content: SANDBOX_INSTRUCTION }].concat(messages);
  let runs = 0;

  for (let round = 0; round < 3; round += 1) {
    let text = "";
    try {
      text = await collect(engine, working, tierKey, PHANTOM_IDENTITY);
    } catch (error) {
      benchProvider(engine.id, error.message);
      return null;
    }
    if (!text) return null;

    RUN_BLOCK.lastIndex = 0;
    const match = RUN_BLOCK.exec(text);
    if (!match) return runs ? { text, runs } : null;

    const result = await runSnippet(env, match[1], match[2], 6);
    runs += 1;
    working.push({ role: "assistant", content: text });
    working.push({
      role: "user",
      content: [
        result.ok ? "A kód lefutott a sandboxon." : "A futtatás nem sikerült (" + (result.error || "hiba") + ").",
        "Kimenet:", (result.stdout || "").trim() || "(üres)",
        result.stderr ? "Hibák:\n" + String(result.stderr).trim() : "",
        "Ezek alapján add meg a végleges választ, kód nélkül, magyarul.",
      ].filter(Boolean).join("\n"),
    });
  }
  return null;
}

async function chat(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400); }

  const tierKey = TIERS[body.tier] ? body.tier : "void";
  const tier = TIERS[tierKey];
  const raw = Array.isArray(body.messages) ? body.messages.slice(-60) : [];
  const messages = raw
    .filter((m) => m && (m.role === "user" || m.role === "assistant") && typeof m.content === "string")
    .map((m) => ({ role: m.role, content: m.content.slice(0, 32000) }));
  if (!messages.length) return json({ ok: false, error: "no messages" }, 400);

  if (body.persona && typeof body.persona === "string" && body.persona.trim()) {
    messages.unshift({ role: "system", content: `Profil utasítás: ${body.persona.slice(0, 800)}` });
  }

  // What the app has learned about this person (name, tastes, plans). It travels with every
  // request, so the model never has to "remember" it on its own.
  const memories = Array.isArray(body.memory)
    ? body.memory
        .filter((m) => typeof m === "string" && m.trim())
        .slice(0, 24)
        .map((m) => "- " + m.replace(/\s+/g, " ").trim().slice(0, 180))
    : [];
  if (memories.length) {
    messages.unshift({
      role: "system",
      content:
        "Amit a felhasználóról biztosan tudsz (korábbi beszélgetésekből):\n" +
        memories.join("\n") +
        "\nEzeket használd magától, ne kérdezz vissza rájuk, és ne mondd, hogy nem emlékszel.",
    });
  }

  const client = request.headers.get("X-Cortex-Client") || "anon";
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (rateLimited("c:" + client, LIMIT.perClient) || rateLimited("i:" + ip, LIMIT.perIp)) {
    return json({ ok: false, error: "rate_limited", message: "Too many messages in the last hour. Try again later." }, 429);
  }

  const started = Date.now();
  const meta = { model: tier.label, tier: tierKey, vendor: "OmegaTech × CortexAnime" };

  const question = lastUserMessage(messages);
  const chatExtra = (layer, q, text, more = {}) => ({ suggestions: suggestFollowUps(layer, q, text), ...more });

  // 0-0) Az idő: a modellek hajlamosak a tanulási adatuk évében ragadni. A mai napot
  // minden kérésnél odaadjuk, rövid, egyértelmű formában.
  messages.unshift({
    role: "system",
    content: `Mai dátum: ${budapestDay()} (Europe/Budapest). Ha a kérdés időhöz kötött (ma, tegnap, idén, hány napja), ebből számolj, ne a saját feltételezésedből.`,
  });

  // 0-0) Dokumentum: a csatolt szöveg a beszélgetés része, nem külön kérés.
  const files = normalizeFiles(body.files);
  if (files.length) {
    const blocks = files
      .map((f, i) => `--- ${i + 1}. dokumentum: ${f.name} ---\n${f.text}`)
      .join("\n\n");
    messages.unshift({
      role: "system",
      content:
        "A felhasználó dokumentumot csatolt. Ezek a beszélgetés forrásai: hivatkozz rájuk úgy, hogy " +
        "megmondod, melyik dokumentum melyik részéből jön az állítás. Ha a válasz nincs bennük, mondd meg.\n\n" +
        blocks,
    });
  }
  const docLayer = files.length ? "document" : null;

  // 0-1) Kép: a válasz a képből jön, nem tippből. A kép nem kerül tárolóba.
  const images = normalizeImages(body.images);
  if (images.length) {
    const seen = await visionAnswer(env, messages, images, question);
    if (seen && seen.text) {
      return finishReply({ text: seen.text, runs: 0 }, meta, body, started, json, sseChannel, sseDone, cors, "vision", chatExtra("vision", question, seen.text));
    }
    return json({
      ok: false,
      error: "vision_unavailable",
      message: "A képhez most nem érem el a látó motort. Próbáld újra egy perc múlva, vagy írd le, mi van a képen.",
    }, 503);
  }

  // 0a) Kifejezett futtatás-kérés: itt a kód a válasz, nem az agy tippje.
  if (body.sandbox !== false && question && wantsRun(question)) {
    const computed = await sandboxAnswer(env, messages, tierKey);
    if (computed && computed.text) return finishReply(computed, meta, body, started, json, sseChannel, sseDone, cors, "sandbox", chatExtra("sandbox", question, computed.text));
  }

  // 0a) Friss hír: ha kifejezetten hírt kér, a mai forrás megy előre. A katalógus-adat
  // (stúdió, év) ilyenkor nem válasz a kérdésre — csak a hír.
  if (body.search !== false && body.kb !== false && question && wantsNews(question)) {
    const subject = newsSubject(question);
    let hit = await news(question, { limit: 4 }).catch(() => null);
    // Általános hírkérés („mik a hírek ma”): a szerkesztett források legfrissebbjei.
    if ((!hit?.items?.length) && !subject.length) {
      const top = await topNews(5).catch(() => []);
      if (top.length) {
        hit = {
          text: "Friss hírek:\n" + top.map((it) => `${it.date ? it.date + " · " : ""}${it.title}${it.source ? " (" + it.source + ")" : ""}`).join("\n"),
          sources: top.map((it) => it.link).filter(Boolean).slice(0, 3),
          items: top,
          kind: "news",
          title: "Friss hírek",
        };
      }
    }
    if (hit && hit.items?.length) {
      const answer = await groundAnswer(env, question, hit);
      bumpLayer("news");
      const label = "news";
      if (body.stream === false) return json({ ok: true, ...meta, text: answer.text, layer: label, sources: hit.sources || [] });
      const ch = sseChannel();
      ch.send({ meta, layer: label });
      ch.send({ delta: answer.text });
      sseDone(ch, meta, label, hit.sources, started, chatExtra(label, question, answer.text));
      return new Response(ch.stream, {
        headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
      });
    }
    // Nincs valódi találat: kimondjuk, nem tálalunk mást helyette.
    const miss = subject.length
      ? `Nincs friss hír erről a magyar forrásokban (IGN Hungary, 444, Telex) — a mai napon nem írtak róla. Ha a sorozatadat érdekel (stúdió, év, részek), kérdezz nyugodtan arról.`
      : "A hírforrások most nem válaszolnak. Próbáld újra egy perc múlva.";
    if (body.stream === false) return json({ ok: true, ...meta, text: miss, layer: "news", sources: [] });
    const ch2 = sseChannel();
    ch2.send({ meta, layer: "news" });
    ch2.send({ delta: miss });
    sseDone(ch2, meta, "news", [], started, chatExtra("news", question, miss));
    return new Response(ch2.stream, {
      headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
    });
  }

  // 0a-2) Ügynök mód: eszközök → válasz. A lépések stream közben is látszanak.
  if ((body.agent === true || body.mode === "agent") && question && question.length <= 1200) {
    const started2 = Date.now();
    if (body.stream === false) {
      const run = await runAgent(env, question, tierKey);
      bumpLayer("agent");
      return json({ ok: true, ...meta, text: run.text, layer: "agent", steps: run.steps,
                    sources: run.sources, ms: Date.now() - started2 });
    }
    const ch = sseChannel();
    const stepsSeen = [];
    const run = await runAgent(env, question, tierKey, (step) => {
      stepsSeen.push(step);
      ch.send({ step });
    });
    bumpLayer("agent");
    ch.send({ meta, layer: "agent" });
    ch.send({ delta: run.text });
    sseDone(ch, meta, "agent", run.sources, started2, { steps: stepsSeen, ...chatExtra("agent", question, run.text) });
    return new Response(ch.stream, {
      headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
    });
  }

  // 0a) Tudásbázis: a katalógus tényei (stúdió, rendező, év, pontszám, részek, felirat).
  // Ez is motor nélkül megy, és nem tud hibázni: az adat ott van.
  if (body.kb !== false && question && question.length <= 300) {
    const fact = await kbCached(env, question).catch(() => null);
    if (fact && fact.text) {
      bumpLayer("kb");
      if (body.stream === false) {
        return json({ ok: true, ...meta, text: fact.text, layer: "kb", sources: fact.sources || [],
                      suggestions: suggestFollowUps("knowledge", question, fact.text) });
      }
      const ch = sseChannel();
      ch.send({ meta, layer: "kb" });
      ch.send({ delta: fact.text });
      sseDone(ch, meta, "kb", fact.sources || [], started, chatExtra("knowledge", question, fact.text));
      return new Response(ch.stream, {
        headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
      });
    }
  }

  // 0) A determinisztikus agy: ha tudja, azonnal válaszol, motor nélkül.
  const exact = body.brain === false ? null : await brainAnswer(env, messages, request.url);
  if (exact) {
    if (body.stream === false) {
      return json({ ok: true, ...meta, text: exact.text, layer: "brain", kind: exact.kind, suggestions: suggestFollowUps("brain", question, exact.text) });
    }
    const quick = sseChannel();
    quick.send({ meta, layer: "brain" });
    quick.send({ delta: exact.text });
    sseDone(quick, meta, "brain", [], started, chatExtra("brain", question, exact.text));
    return new Response(quick.stream, {
      headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
    });
  }

  // 0b) Kifejezett mély kutatás: két keresés + forrás-alapú összefoglaló. Külön lépcső,
  // mert itt nem az a cél, hogy egy mondatot találjunk, hanem hogy legyen mit hivatkozni.
  if (body.research || (question && wantsResearch(question))) {
    const study = await researchAnswer(env, question, () => {});
    if (study && study.text) {
      if (!body.incognito) {
        await knowledgeStore(env, question, study.text, study.sources, "research").catch(() => {});
        await logQuestion(env, question, { kind: "research", ok: true }).catch(() => {});
      }
      const extra = chatExtra("research", question, study.text, {
        research: { queries: study.queries, ms: study.ms, sources: study.sources.length },
      });
      return finishReply({ text: study.text, runs: 0, sources: study.sources }, meta, body, started, json, sseChannel, sseDone, cors, "research", extra);
    }
  }

  // Agy nem tudta. Tudástár, majd kereső — a felhasználónak gyorsabb és pontosabb,
  // mint egy motort megvárni, és nem kell hozzá semmilyen API-kulcs.
  if (body.sandbox !== false && question && wantsCompute(question)) {
    const computed = await sandboxAnswer(env, messages, tierKey);
    if (computed && computed.text) return finishReply(computed, meta, body, started, json, sseChannel, sseDone, cors, "sandbox", chatExtra("sandbox", question, computed.text));
  }

  if (body.search !== false && question && wantsFacts(question)) {
    const known = await knowledgeLookup(env, question);
    const hit = known || compose(question, await search(env, question, { anime: looksAnime(question) }).catch(() => null));
    if (hit && hit.text) {
      // Ismert kérdés → a tudástárból azonnal. Új találat → előbb forrás-alapú válasz.
      const answer = known ? hit : await groundAnswer(env, question, hit);
      // Ha a forrásból dolgozó válasz azt mondja, hogy a kért adat nincs a forrásban,
      // akkor nem tároljuk el, és hagyjuk a motort válaszolni — az „ezt nem tartalmazza”
      // helyett a felhasználó inkább egy használható választ kap.
      const thin = /nem tartalmazza|nem szerepel (benne|a forr)|nem all rendelkezesre|nem tudom megvalaszolni/i.test(answer.text || "");
      if (thin) { /* a lenti motorlánc válaszol */ } else {
      if (!known && !body.incognito) await knowledgeStore(env, question, answer.text, hit.sources, "search");
      if (!body.incognito) await logQuestion(env, question, { kind: hit.kind || "search", ok: true });
      const label = known ? "knowledge" : "search";
      if (body.stream === false) return json({ ok: true, ...meta, text: answer.text, layer: label, sources: hit.sources || [] });
      const ch = sseChannel();
      ch.send({ meta, layer: label });
      ch.send({ delta: answer.text });
      sseDone(ch, meta, label, hit.sources, started, chatExtra(label, question, answer.text));
      return new Response(ch.stream, {
        headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
      });
      }
    }
  }

  // Ha a kérdés egy katalógus-sorozatról szól, a pontos tények menjenek a motor elé is,
  // hogy ne emlékezetből tippeljen.
  const factBlock = await kbContext(env, question).catch(() => "");
  if (factBlock) {
    messages.unshift({
      role: "system",
      content: "Cortex tudásbázis — pontos adatok erről a sorozatról. Ezeket használd, ne tippelj:\n" + factBlock,
    });
  }

  const chain = pickChain(tierKey, env).filter((e) => !benched(e.id));
  if (!chain.length) {
    return json({ ok: false, error: "upstream_unavailable", message: "Cortex Void is busy right now. Try again in a moment." }, 503);
  }

  // Cortex Phantom is not a single engine: it is the three-pass line above.
  if (tierKey === "phantom") {
    if (body.stream === false) {
      try {
        const text = await phantomAnswer(env, messages);
        return json({ ok: true, ...meta, text });
      } catch {
        /* fall back to the ordinary chain below */
      }
    } else {
      return phantomChat(env, messages, meta, started);
    }
  }

  if (body.stream === false) {
    for (const engine of chain) {
      try {
        const text = await collectSticky(engine, messages, tierKey);
        if (text) return json({ ok: true, ...meta, text, layer: "engine", ms: Date.now() - started });
      } catch (e) {
        benchProvider(engine.id, e.message);
      }
    }
    return json({ ok: false, error: "upstream_unavailable", message: "Cortex Void is busy right now. Try again in a moment." }, 503);
  }

  const channel = sseChannel();
  const run = (async () => {
    channel.send({ meta });
    let said = "";
    for (const engine of chain) {
      try {
        try {
          await relay(engine, messages, tierKey, (t) => { said += t; channel.send({ delta: t }); });
        } catch (e) {
          if (said || !isCapacityError(e.message)) throw e;
          await sleep(400);
          await relay(engine, messages, tierKey, (t) => { said += t; channel.send({ delta: t }); });
        }
        sseDone(channel, meta, "engine", [], started, chatExtra(docLayer || "engine", question, said));
        return;
      } catch (e) {
        benchProvider(engine.id, e.message);
      }
    }
    channel.error("Cortex Void is busy right now. Try again in a moment.");
  })();
  return new Response(channel.stream, {
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-store",
      Connection: "keep-alive",
      ...cors,
    },
  });
}

// ── Image studio (Cortex Void Canvas) ────────────────────────────────────────
// ── Cortex Void Canvas ──────────────────────────────────────────────────────
// A képmotor: FLUX.1-schnell (Black Forest Labs — a Hugging Face egyik
// legnépszerűbb képgeneráló modellje), Cloudflare Workers AI-n keresztül.
// A kliens csak a „Cortex Void Canvas" nevet látja — a gyártó soha nem jelenik
// meg. A render eredménye a CORTEX_R2 R2-be kerül (ai-images/<id>.png), a
// státusz onnan olvasható bármely izolátumból. Ha a Workers AI nem elérhető,
// az xKiro marad tartalék.

const IMG_MODEL = "@cf/black-forest-labs/flux-1-schnell";
const IMG_DISPLAY = "Cortex Void Canvas";
const IMG_PREFIX = "ai-images/";
const IMG_XKIRO_MODEL = "sensenova/sensenova-u1.5-lite";

const IMG_STYLES = {
  auto: "",
  anime: ", anime key visual, clean line art, vibrant colours",
  cinema: ", cinematic film still, dramatic lighting, 35mm",
  icon: ", app icon, centered subject, flat design, minimal, no text",
  render: ", 3d render, soft studio light, octane",
  sketch: ", pencil sketch, graphite, loose strokes",
};

function imageBase(env) {
  return (env.XKIRO_BASE_URL || "https://api.xkiro.com/v1").replace(/\/$/, "");
}

function imgId() {
  return crypto.randomUUID().replace(/-/g, "").slice(0, 24);
}

async function r2put(env, key, data, type) {
  await env.CORTEX_R2.put(key, data, { httpMetadata: { contentType: type } });
}

// A FLUX.1-schnell angol promptra lett tanítva: a magyar (vagy bármilyen nem
// angol) leírást előbb gyorsan lefordítjuk, különben szép, de lényegtelen kép
// jön. Ha nincs kulcs vagy a fordítás elbukik, a nyers prompt megy tovább.
async function promptToEnglish(prompt, env) {
  if (!/[^\x00-\x7F]/.test(prompt)) { promptToEnglish.lastWhy = "ascii"; return prompt; }
  if (!env.GEMINI_API_KEY) { promptToEnglish.lastWhy = "no_key"; return prompt; }
  try {
    const model = env.GEMINI_MODEL || "gemini-3.5-flash";
    const r = await fetch(
      `https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent?key=${env.GEMINI_API_KEY}`,
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          contents: [{ parts: [{ text: "You turn image-generation prompts into English. Translate the prompt below and output ONLY the English prompt, no quotes, no commentary.\n\n" + prompt }] }],
          generationConfig: { temperature: 0.2, maxOutputTokens: 400 },
        }),
      }
    );
    if (!r.ok) return prompt;
    const d = await r.json();
    const out = (d.candidates && d.candidates[0] && d.candidates[0].content && d.candidates[0].content.parts || [])
      .map((p) => p.text || "").join("").trim();
    promptToEnglish.lastWhy = out ? "ok" : "empty:" + r.status;
    return out || prompt;
  } catch (e) {
    promptToEnglish.lastWhy = "err:" + String(e && e.message || e).slice(0, 60);
    return prompt;
  }
}

async function renderWithWorkersAI(env, id, prompt, style) {
  const full = prompt + (IMG_STYLES[style] || "");
  // A Workers AI FLUX.1-schnell sémája csak a promptot fogadja el
  // (num_steps/width/height tiltott mezők nála).
  const out = await env.AI.run(IMG_MODEL, { prompt: full });
  const b64 = out && out.image;
  if (!b64) throw new UpstreamError(502, "no image in response");
  const bytes = Uint8Array.from(atob(b64), (c) => c.charCodeAt(0));
  await r2put(env, IMG_PREFIX + id + ".png", bytes, "image/png");
}

async function imageCreate(request, env, ctx) {
  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400); }

  const prompt = String(body.prompt || "").trim().slice(0, 1000);
  if (!prompt) return json({ ok: false, error: "no_prompt", message: "Write a prompt first." }, 400);
  const style = Object.prototype.hasOwnProperty.call(IMG_STYLES, body.style) ? body.style : "auto";

  const client = request.headers.get("X-Cortex-Client") || "anon";
  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  if (rateLimited("ic:" + client, 30) || rateLimited("ii:" + ip, 60)) {
    return json({ ok: false, error: "rate_limited", message: "That is a lot of images in one hour. Try again later." }, 429);
  }

  // Elsődleges út: Workers AI FLUX.1-schnell — a munka a háttérben fut, a
  // kliens addig pollol. A .meta rögtön megvan, így az „elszált munka" is
  // felismerhető később.
  if (env.AI && env.CORTEX_R2) {
    const id = imgId();
    const enPrompt = await promptToEnglish(prompt, env);
    await r2put(env, IMG_PREFIX + id + ".meta",
      JSON.stringify({ created: Date.now(), prompt, enPrompt, tr: promptToEnglish.lastWhy || "?", style, model: "flux-1-schnell" }),
      "application/json");
    const job = renderWithWorkersAI(env, id, enPrompt, style).catch(async (e) => {
      benchProvider("flux-image", String(e && e.message || e));
      try { await r2put(env, IMG_PREFIX + id + ".err", String(e && e.message || e), "text/plain"); } catch {}
    });
    if (ctx && ctx.waitUntil) ctx.waitUntil(job); else await job;
    return json({ ok: true, id, status: "processing", model: IMG_DISPLAY, style });
  }

  // Tartalék: xKiro aszinkron munkahely (csak ha nincs Workers AI kötés).
  if (!env.XKIRO_API_KEY) {
    return json({ ok: false, error: "upstream_unavailable", message: "The image studio is offline right now." }, 503);
  }
  try {
    const r = await fetch(`${imageBase(env)}/images/generations`, {
      method: "POST",
      headers: { Authorization: `Bearer ${env.XKIRO_API_KEY}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model: env.XKIRO_IMAGE_MODEL || IMG_XKIRO_MODEL,
        prompt: prompt + (IMG_STYLES[style] || ""),
        n: 1,
      }),
    });
    if (!r.ok) throw new UpstreamError(r.status, (await r.text()).slice(0, 200));
    const d = await r.json();
    if (!d.id) throw new UpstreamError(502, "no job id");
    return json({ ok: true, id: d.id, status: d.status || "processing", model: IMG_DISPLAY, style });
  } catch (e) {
    benchProvider("xkiro-image", e.message);
    return json({ ok: false, error: "upstream", message: "The image studio is busy. Try again in a moment." }, 502);
  }
}

async function imageStatus(id, env) {
  if (!/^[A-Za-z0-9._-]{6,80}$/.test(id)) return json({ ok: false, error: "bad id" }, 400);

  // Saját (Workers AI) munkák: R2-ből olvasható a státusz, izolátustól függetlenül.
  if (env.CORTEX_R2) {
    const png = await env.CORTEX_R2.head(IMG_PREFIX + id + ".png");
    if (png) {
      return json({
        ok: true, status: "succeeded",
        url: "https://cortanime.eu/api/cortexai/image/" + id + "/file",
        image: IMG_DISPLAY,
      });
    }
    const err = await env.CORTEX_R2.head(IMG_PREFIX + id + ".err");
    if (err) return json({ ok: true, status: "failed", url: null, image: IMG_DISPLAY });
    const meta = await env.CORTEX_R2.head(IMG_PREFIX + id + ".meta");
    if (meta) {
      const uploaded = meta.uploaded instanceof Date ? meta.uploaded.getTime() : 0;
      if (uploaded && Date.now() - uploaded > 180000) {
        return json({ ok: true, status: "failed", url: null, image: IMG_DISPLAY });
      }
      return json({ ok: true, status: "processing", url: null, image: IMG_DISPLAY });
    }
  }

  // xKiro tartalék (a régi munkák is itt futnak).
  if (!env.XKIRO_API_KEY) return json({ ok: false, error: "upstream_unavailable" }, 503);
  try {
    const r = await fetch(`${imageBase(env)}/images/generations/${encodeURIComponent(id)}`, {
      headers: { Authorization: `Bearer ${env.XKIRO_API_KEY}` },
    });
    if (!r.ok) throw new UpstreamError(r.status, (await r.text()).slice(0, 160));
    const d = await r.json();
    const first = d.data && d.data[0];
    return json({
      ok: true,
      status: d.status || "unknown",
      url: first && first.url ? first.url : null,
      image: IMG_DISPLAY,
    });
  } catch (e) {
    return json({ ok: false, error: "upstream", message: "Could not read the job yet." }, 502);
  }
}

async function imageFile(id, env) {
  if (!/^[A-Za-z0-9._-]{6,80}$/.test(id) || !env.CORTEX_R2) {
    return json({ ok: false, error: "not_found" }, 404);
  }
  const obj = await env.CORTEX_R2.get(IMG_PREFIX + id + ".png");
  if (!obj) return json({ ok: false, error: "not_found" }, 404);
  // A FLUX hol JPEG-t, hol PNG-t ad — a bájtokból dől el a tartalomtípus.
  const buf = new Uint8Array(await obj.arrayBuffer());
  let ctype = "image/png";
  if (buf[0] === 0xff && buf[1] === 0xd8) ctype = "image/jpeg";
  else if (buf[0] === 0x52 && buf[1] === 0x49) ctype = "image/webp";
  return new Response(buf, {
    headers: {
      "Content-Type": ctype,
      "Cache-Control": "public, max-age=31536000, immutable",
      ...cors,
    },
  });
}


// ── Cortex Void Core: the model we teach ourselves ───────────────────────────
// The nightly GitHub Action trains a small LoRA adapter on our own catalogue and
// Hungarian subtitles, grades it, and only promotes it when it beats the current
// champion by MARGIN. Until a champion exists every answer comes from the
// internet chain above; after that `selfhost` is first in line. The client only
// ever sees numbers: no base model, no vendor, no adapter path.
const CORE = {
  target: 92,          // score the app shows as "ready" — below this the core is still learning
  margin: 0.02,        // must beat the champion by this much to take the crown
  utc: "03:15",
  stateKey: "cortexai/core/state.json",
  historyKey: "cortexai/core/history.json",
};

async function coreRead(env, key, fallback) {
  const bucket = env.CORTEX_R2;
  if (!bucket) return fallback;
  const obj = await bucket.get(key);
  if (!obj) return fallback;
  try { return await obj.json(); } catch { return fallback; }
}

async function coreWrite(env, key, value) {
  const bucket = env.CORTEX_R2;
  if (!bucket) return false;
  await bucket.put(key, JSON.stringify(value), { httpMetadata: { contentType: "application/json" } });
  return true;
}

// Only real timestamps reach the client — an odd string from a client never shows up as a date.
function isoish(value) {
  return typeof value === "string" && /^\d{4}-\d{2}-\d{2}T/.test(value) ? value : null;
}

function coreView(state, history, env) {
  const score = Number(state.score) || 0;
  return {
    ok: true,
    model: "Cortex Phantom",
    phase: state.state || "learning",
    version: Number(state.version) || 0,
    score: Math.round(score * 10) / 10,
    target: CORE.target,
    progress: Math.max(0, Math.min(100, Math.round((score / CORE.target) * 100))),
    parts: state.parts || null,
    trainedAt: isoish(state.trained_at),
    gate: CORE.margin,
    selfhost: Boolean(env.SELFHOST_BASE_URL),
    nextRound: CORE.utc + " UTC",
    history: Array.isArray(history)
      ? history.slice(-12).map((h) => ({ v: h.v, score: h.score, at: isoish(h.at) }))
      : [],
  };
}

async function coreStatus(env) {
  const state = await coreRead(env, CORE.stateKey, null);
  const history = await coreRead(env, CORE.historyKey, []);
  if (!state) {
    return coreView({ version: 0, score: 0, state: "learning" }, history, env);
  }
  return coreView(state, history, env);
}

async function coreReport(request, env) {
  const url = new URL(request.url);
  const given = request.headers.get("X-Core-Token") || url.searchParams.get("k") || "";
  const expected = env.CORE_TOKEN || env.DIAG_TOKEN;
  if (!expected || given !== expected) return json({ ok: false, error: "forbidden" }, 403);

  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400); }
  const score = Number(body.score);
  if (!Number.isFinite(score) || score < 0 || score > 100) {
    return json({ ok: false, error: "bad score" }, 400);
  }

  const prev = (await coreRead(env, CORE.stateKey, null)) || { version: 0, score: 0 };
  const history = await coreRead(env, CORE.historyKey, []);
  // The worker keeps its own gate too: a round never replaces a better champion,
  // even if the client says otherwise.
  if (Number(prev.score) > 0 && score < Number(prev.score) + CORE.margin) {
    return json({ ok: true, kept: true, champion: Number(prev.score), reported: score });
  }

  const next = {
    version: Math.max(Number(prev.version) || 0, Number(body.version) || 0) + 1,
    score,
    parts: body.parts || null,
    trained_at: body.trained_at || new Date().toISOString(),
    state: score >= CORE.target ? "ready" : "learning",
  };
  await coreWrite(env, CORE.stateKey, next);
  const trimmed = history.concat([{ v: next.version, score, at: next.trained_at }]).slice(-40);
  await coreWrite(env, CORE.historyKey, trimmed);
  return json({ ok: true, kept: false, champion: score, version: next.version, state: next.state });
}

async function phantomAsk(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400); }
  const question = typeof body.q === "string" ? body.q : "";
  if (!question.trim()) return json({ ok: false, error: "no question" }, 400);
  const result = await phantomAnswerLayers(env, question, {
    url: request.url,
    allowSearch: body.search !== false,
  });
  return json({ ok: true, ...result });
}

/** Keresővégpont: GET /phantom/search?q=… — ugyanaz a lánc, böngészőből is hívható. */
async function phantomSearchRoute(request, env) {
  const url = new URL(request.url);
  const q = (url.searchParams.get("q") || "").trim();
  if (!q) return json({ ok: false, error: "no query" }, 400);
  const result = await phantomAnswerLayers(env, q, { url: request.url });
  return json({ ok: true, q, ...result });
}

// ── Nyelvi őr ────────────────────────────────────────────────────────────────
// Mért hiba (Arena-Hard mérés, 2026-11-01): a tartalék motor egy magyar/angol kérdésre
// kínaiul, majd spanyolul válaszolt. A felhasználó nyelvét a lánc nem kényszerítette.
// Ez a függvény a kérdés nyelvét méri, és a motornak előírja a válasz nyelvét.
function languageDirective(text) {
  const t = (text || "").slice(0, 2000);
  const huChars = (t.match(/[áéíóöőúüűÁÉÍÓÖŐÚÜŰ]/g) || []).length;
  const huWords = (t.match(/\b(a|az|és|hogy|nem|egy|van|vagy|mit|miért|hogyan|köszönöm|kérlek|szeretnék)\b/gi) || []).length;
  const cjk = (t.match(/[\u4e00-\u9fff\u3040-\u30ff]/g) || []).length;
  const hu = huChars >= 3 || huWords >= 2;
  return hu
    ? "Válaszolj MAGYARUL, akkor is, ha a kérdés más nyelvű. Soha ne válaszolj kínaiul, spanyolul vagy más nyelven."
    : "Answer in ENGLISH, even if the prompt is in another language. Never answer in Chinese, Spanish or any other language." ;
}

function withLanguage(messages, question) {
  const directive = languageDirective(question);
  // az első system üzenetbe fűzzük, ha van; különben új sort teszünk elé
  const out = messages.slice();
  const i = out.findIndex((m) => m.role === "system");
  if (i >= 0) out[i] = { role: "system", content: out[i].content + "\n" + directive };
  else out.unshift({ role: "system", content: directive });
  return out;
}

// ── OpenAI-kompatibilis végpont ──────────────────────────────────────────────
// Ugyanaz a lánc, mint a /chat-nél (agy → tudástár → kereső → motorok), de a válasz
// OpenAI formátumú — így bármely mérőeszköz (arena-hard-auto, bármely SDK) ráállhat.
const MODEL_ID = "cortex-phantom";

async function v1Chat(request, env) {
  let body;
  try { body = await request.json(); } catch { return json({ error: { message: "bad json" } }, 400); }
  const messages = (Array.isArray(body.messages) ? body.messages : [])
    .filter((m) => m && typeof m.content === "string" && (m.role === "user" || m.role === "assistant" || m.role === "system"))
    .map((m) => ({ role: m.role, content: m.content }));
  if (!messages.length) return json({ error: { message: "no messages" } }, 400);

  const question = lastUserMessage(messages);
  const started = Date.now();
  let text = "", layer = "none", sources = [];

  // 1–3) ugyanaz a három réteg, mint élesben
  if (question) {
    try {
      const r = await phantomAnswerLayers(env, question, { url: request.url, allowSearch: wantsFacts(question) });
      if (r && r.confident && r.text) { text = r.text; layer = r.layer; sources = r.sources || []; }
    } catch { /* mehet tovább a motorokra */ }
  }

  // 4) motorlánc, ha a saját rétegek nem tudták
  if (!text) {
    const chain = pickChain("phantom", env).filter((e) => !benched(e.id));
    const guarded = withLanguage(messages, question);   // nyelvi őr: a kérdés nyelvén válaszoljon
    for (const engine of chain) {
      try {
        const out = await collectSticky(engine, guarded, "phantom");
        if (out) { text = out; layer = "engine"; break; }
      } catch { /* következő motort próbáljuk */ }
    }
  }

  if (!text) text = "Erre most nem tudok biztos választ adni.";

  const usage = {
    prompt_tokens: Math.max(1, Math.round(messages.map((m) => m.content.length).join("").length / 4)),
    completion_tokens: Math.max(1, Math.round(text.length / 4)),
  };
  usage.total_tokens = usage.prompt_tokens + usage.completion_tokens;
  const payload = {
    id: "chatcmpl-" + Date.now(),
    object: "chat.completion",
    created: Math.floor(Date.now() / 1000),
    model: MODEL_ID,
    choices: [{ index: 0, finish_reason: "stop", message: { role: "assistant", content: text } }],
    usage,
    phantom: { layer, sources, ms: Date.now() - started },
  };

  if (body.stream === true) {
    const ch = sseChannel();
    ch.send({ id: payload.id, object: "chat.completion.chunk", created: payload.created, model: MODEL_ID,
              choices: [{ index: 0, delta: { role: "assistant", content: "" }, finish_reason: null }] });
    for (let i = 0; i < text.length; i += 60) {
      ch.send({ id: payload.id, object: "chat.completion.chunk", created: payload.created, model: MODEL_ID,
                choices: [{ index: 0, delta: { content: text.slice(i, i + 60) }, finish_reason: null }] });
    }
    ch.send({ id: payload.id, object: "chat.completion.chunk", created: payload.created, model: MODEL_ID,
              choices: [{ index: 0, delta: {}, finish_reason: "stop" }] });
    ch.close();
    return new Response(ch.stream, {
      headers: { "Content-Type": "text/event-stream; charset=utf-8", "Cache-Control": "no-store", ...cors },
    });
  }
  return json(payload);
}

/** POST /phantom/knowledge/reset  {"q": "..."}  — rossz válasz törlése a tudástárból. */
async function phantomKnowledgeReset(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") || "";
  if (!token || (token !== env.CORE_TOKEN && token !== env.DIAG_TOKEN)) {
    return json({ ok: false, error: "forbidden" }, 403);
  }
  let body = {};
  try { body = await request.json(); } catch { body = {}; }
  const result = await resetKnowledge(env, body.q || "");
  return json({ ok: true, ...result });
}

/** A tanulókör ebből dolgozik. Token nélkül csak összesítő számok jönnek. */
async function phantomQuestionsRoute(request, env) {
  const url = new URL(request.url);
  const token = url.searchParams.get("token") || "";
  const stats = await readQuestions(env);
  if (!token || (token !== env.CORE_TOKEN && token !== env.DIAG_TOKEN)) {
    return json({ ok: true, total: stats.total, answered: stats.answered, unanswered: stats.unanswered });
  }
  const limit = Math.min(parseInt(url.searchParams.get("limit") || "300", 10) || 300, 1000);
  const pairs = await knowledgePairs(env, limit);
  return json({ ok: true, ...stats, pairs: pairs.length, learned: pairs });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const path = url.pathname.replace(/^\/api\/cortexai/, "") || "/";
    if (request.method === "OPTIONS") return new Response(null, { status: 204, headers: cors });

    // Opt-in volunteer page, served from this worker so no extra route/bucket juggling.
    // Cortex AI a böngészőben: ugyanaz az agy, telepítés nélkül.
    if ((path === "/web" || path === "/web/" || path === "/ai" || path === "/ai/" || path === "/cortex" || (path === "/chat" && request.method === "GET")) && request.method === "GET") {
      return new Response(WEBCHAT_HTML, {
        headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300" },
      });
    }

    // A sandbox telepítője: a friss gép egy sorral felveszi a szolgáltatást.
    if (path === "/sandbox/setup.sh" && request.method === "GET") {
      return new Response(SANDBOX_SETUP_SH, {
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=600" },
      });
    }
    if (path === "/sandbox/service.py" && request.method === "GET") {
      return new Response(SANDBOX_SERVICE_PY, {
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "public, max-age=600" },
      });
    }
    // Megosztott beszélgetés: olvasható oldal, 30 nap után eltűnik. Nem listázható.
    if (path.startsWith("/s/") && request.method === "GET") {
      const id = path.slice(3).replace(/[^a-z0-9]/gi, "").slice(0, 16);
      if (!id || !env.CORTEX_R2) return new Response("Nincs ilyen megosztás.", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
      try {
        const obj = await env.CORTEX_R2.get(`cortexai/share/${id}.json`);
        if (!obj) return new Response("Nincs ilyen megosztás.", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
        const share = JSON.parse(await obj.text());
        if (share.expiresAt && Date.parse(share.expiresAt) < Date.now()) {
          return new Response("Ez a megosztás lejárt.", { status: 410, headers: { "Content-Type": "text/plain; charset=utf-8" } });
        }
        return new Response(sharePage(share), {
          headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=600", "X-Robots-Tag": "noindex" },
        });
      } catch {
        return new Response("Nincs ilyen megosztás.", { status: 404, headers: { "Content-Type": "text/plain; charset=utf-8" } });
      }
    }

    // Ügynök mód közvetlenül: ugyanaz, mint a /chat agent:true — de külön is hívható.
    if (path === "/agent" && request.method === "POST") {
      let body = {};
      try { body = await request.json(); } catch { body = {}; }
      const question = String(body.question || body.q || (body.messages || []).filter((m) => m.role === "user").pop()?.content || "").trim();
      if (!question) return json({ ok: false, error: "no_question" }, 400, cors);
      const run = await runAgent(env, question, body.tier || "void");
      bumpLayer("agent");
      return json({ ok: true, text: run.text, steps: run.steps, sources: run.sources, layer: "agent" }, 200, cors);
    }

    // Ütemezett feladatok: eszközönkénti lista, R2-ben.
    if (path === "/tasks" && request.method === "GET") {
      const client = clientOf(request, url);
      if (!client) return json({ ok: false, error: "no_client" }, 400, cors);
      const rows = (await readTasks(env)).filter((t) => t.client === client);
      return json({ ok: true, tasks: rows }, 200, { ...cors, "Cache-Control": "no-store" });
    }
    if (path === "/tasks" && request.method === "POST") {
      const client = clientOf(request, url);
      if (!client) return json({ ok: false, error: "no_client" }, 400, cors);
      let body = {};
      try { body = await request.json(); } catch { body = {}; }
      const prompt = String(body.prompt || "").trim().slice(0, 600);
      const at = String(body.at || "").trim();
      if (!prompt) return json({ ok: false, error: "no_prompt" }, 400, cors);
      if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}/.test(at)) return json({ ok: false, error: "bad_time" }, 400, cors);
      const rows = await readTasks(env);
      const task = {
        id: crypto.randomUUID().slice(0, 8),
        client,
        prompt,
        title: String(body.title || prompt).slice(0, 80),
        at,
        repeat: body.repeat === "daily" ? "daily" : "once",
        on: true,
        createdAt: new Date().toISOString(),
      };
      rows.push(task);
      await writeTasks(env, rows);
      return json({ ok: true, task }, 200, cors);
    }
    if (path === "/tasks" && request.method === "DELETE") {
      const client = clientOf(request, url);
      const id = (url.searchParams.get("id") || "").replace(/[^a-z0-9-]/gi, "").slice(0, 12);
      if (!client || !id) return json({ ok: false, error: "bad_request" }, 400, cors);
      const rows = await readTasks(env);
      const next = rows.filter((t) => !(t.id === id && t.client === client));
      await writeTasks(env, next);
      return json({ ok: true, removed: rows.length - next.length }, 200, cors);
    }
    if (path === "/tasks" && request.method === "PATCH") {
      const client = clientOf(request, url);
      const id = (url.searchParams.get("id") || "").replace(/[^a-z0-9-]/gi, "").slice(0, 12);
      if (!client || !id) return json({ ok: false, error: "bad_request" }, 400, cors);
      const rows = await readTasks(env);
      const row = rows.find((t) => t.id === id && t.client === client);
      if (!row) return json({ ok: false, error: "not_found" }, 404, cors);
      row.on = !row.on;
      await writeTasks(env, rows);
      return json({ ok: true, task: row }, 200, cors);
    }

    // Statisztika: melyik réteg mennyit dolgozott, mióta fut a worker.
    if (path === "/stats" && request.method === "GET") {
      return json(await statsBody(env), 200, { ...cors, "Cache-Control": "no-store" });
    }

    // Tudásbázis: hány sorozat, mennyi tény, mi van benne.
    if (path === "/kb/status" && request.method === "GET") {
      const status = await kbStatus(env).catch(() => ({ ok: false }));
      return json(status, 200, { ...cors, "Cache-Control": "public, max-age=300" });
    }

    // Keresés a tudásbázisban: címre, stúdióra, rendezőre.
    if (path === "/kb/search" && request.method === "GET") {
      const q = (url.searchParams.get("q") || "").trim();
      if (!q) return json({ ok: true, items: [] }, 200, cors);
      const items = await kbSearch(env, q, Math.min(Math.max(Number(url.searchParams.get("limit") || 8), 1), 20)).catch(() => []);
      return json({ ok: true, q, items }, 200, { ...cors, "Cache-Control": "public, max-age=120" });
    }

    if (path === "/kb/series" && request.method === "GET") {
      const id = Number(url.searchParams.get("id") || 0);
      const row = id ? await kbSeries(env, id).catch(() => null) : null;
      if (!row) return json({ ok: false, error: "not_found" }, 404, cors);
      return json({ ok: true, series: row }, 200, { ...cors, "Cache-Control": "public, max-age=600" });
    }

    // Hírek egy témában: a frissesség, amit a lexikon nem ad meg.
    if (path === "/news" && request.method === "GET") {
      const q = (url.searchParams.get("q") || "").trim();
      if (!q) return json({ ok: false, error: "no query" }, 400, cors);
      const hit = await news(q, { limit: Math.min(Math.max(Number(url.searchParams.get("limit") || 4), 1), 8) }).catch(() => null);
      if (!hit) return json({ ok: true, q, items: [] }, 200, cors);
      return json({ ok: true, q, items: hit.items, text: hit.text, sources: hit.sources }, 200, cors);
    }

    // Napi brief: mai adások + hírek. Az app üres chat képernyője ezt mutatja.
    if (path === "/daily" && request.method === "GET") {
      const brief = await feedBrief(env).catch(() => null);
      if (!brief) return json({ ok: false, error: "unavailable" }, 200, cors);
      return json({ ok: true, ...brief, vendor: "OmegaTech × CortexAnime" }, 200, { ...cors, "Cache-Control": "public, max-age=300" });
    }

    if (path === "/share" && request.method === "POST") {
      const client = request.headers.get("X-Cortex-Client") || "anon";
      const ip = request.headers.get("CF-Connecting-IP") || "unknown";
      if (rateLimited("sh:" + client, 12) || rateLimited("shi:" + ip, 40)) {
        return json({ ok: false, error: "rate_limited" }, 429, cors);
      }
      let body; try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400, cors); }
      const share = await shareSave(env, body.messages, body.title);
      if (!share) return json({ ok: false, error: "empty" }, 400, cors);
      return json({ ok: true, id: share.id, url: `https://cortanime.eu/api/cortexai/s/${share.id}`, expires: share.expiresAt }, 200, cors);
    }

    // Kutatás külön hívva: a kliens lépésenként kapja a fázisokat, majd a forrásos választ.
    if (path === "/research" && request.method === "POST") {
      let body; try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400, cors); }
      const question = String(body.question || "").trim();
      if (!question) return json({ ok: false, error: "no question" }, 400, cors);
      const client = request.headers.get("X-Cortex-Client") || "anon";
      const ip = request.headers.get("CF-Connecting-IP") || "unknown";
      if (rateLimited("r:" + client, 40) || rateLimited("ri:" + ip, 90)) return json({ ok: false, error: "rate_limited" }, 429, cors);
      const study = await researchAnswer(env, question, () => {}).catch(() => null);
      if (!study) return json({ ok: false, error: "no_sources", message: "Ehhez most nem találtam használható forrást." }, 200, cors);
      await knowledgeStore(env, question, study.text, study.sources, "research").catch(() => {});
      return json({
        ok: true, question, text: study.text, sources: study.sources, queries: study.queries, ms: study.ms,
        suggestions: suggestFollowUps("research", question, study.text),
        layer: "research", vendor: "OmegaTech × CortexAnime",
      }, 200, cors);
    }

    // Két válasz egymás mellett: ugyanaz a kérdés, két hangnem. Egy motor, két profil.
    if (path === "/compare" && request.method === "POST") {
      let body; try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400, cors); }
      const question = String(body.question || "").trim();
      if (!question) return json({ ok: false, error: "no question" }, 400, cors);
      const tierKey = TIERS[body.tier] ? body.tier : "void";
      const chain = pickChain(tierKey, env).filter((e) => !benched(e.id));
      if (!chain.length) return json({ ok: false, error: "upstream_unavailable" }, 503, cors);
      const engine = chain[0];
      const voices = [
        { key: "left", label: String(body.left || "Tömör"), style: "Válaszolj röviden, legfeljebb 4 mondatban, kizárólag a lényeggel." },
        { key: "right", label: String(body.right || "Részletes"), style: "Válaszolj részletesen: vezess be, adj példát, és zárd le egy összefoglaló mondattal." },
      ];
      const answers = await Promise.all(voices.map(async (v) => {
        try {
          const text = await collect(engine, [{ role: "system", content: PHANTOM_IDENTITY + " " + v.style }, { role: "user", content: question }], tierKey);
          return { ...v, text: String(text || "").trim(), ms: 0 };
        } catch { return { ...v, text: "", ms: 0 }; }
      }));
      return json({ ok: true, question, answers, vendor: "OmegaTech × CortexAnime" }, 200, cors);
    }

    // Sablonok: egy koppintással induló, magyar nyelvű feladatok. Nem modellhívás.
    if (path === "/templates" && request.method === "GET") {
      return json({ ok: true, templates: TEMPLATES }, 200, { ...cors, "Cache-Control": "public, max-age=3600" });
    }

    // Mi van ebben a verzióban: az app „Újdonságok” lapja ezt tölti be.
    if (path === "/features" && request.method === "GET") {
      return json({ ok: true, ...FEATURES }, 200, { ...cors, "Cache-Control": "public, max-age=1800" });
    }

    // Tanuló kör: a naplóba bekerült, megválaszolatlan kérdésekre forrásból válaszol,
    // és ami tartható, eltárolja. Így a tudástár magától gyarapodik.
    if (path === "/phantom/learn" && request.method === "POST") {
      const token = url.searchParams.get("token") || "";
      if (!env.CORE_TOKEN || token !== env.CORE_TOKEN) return json({ ok: false, error: "forbidden" }, 403);
      const limit = Math.min(Math.max(Number(url.searchParams.get("limit") || 4), 1), 12);
      const log = await readQuestions(env);
      const learned = [];
      const skipped = [];
      for (const row of log.top_unanswered.slice(0, limit)) {
        const q = String(row.q || "").trim();
        if (!q) continue;
        try {
          if (await knowledgeLookup(env, q)) { skipped.push(q); continue; }
          const hit = compose(q, await search(env, q, { anime: looksAnime(q) }).catch(() => null));
          if (!hit || !hit.text) { skipped.push(q); continue; }
          const answer = await groundAnswer(env, q, hit);
          if (!answer || !answer.text || /nem tartalmazza|nem szerepel (benne|a forr)|nem tudom/i.test(answer.text)) {
            skipped.push(q);
            continue;
          }
          await knowledgeStore(env, q, answer.text, hit.sources, "learn");
          await logQuestion(env, q, { kind: "learn", ok: true });
          learned.push(q);
        } catch { skipped.push(q); }
      }
      return json({ ok: true, learned: learned.length, skipped: skipped.length, learnedQuestions: learned });
    }

    if (path === "/sandbox/run" && request.method === "POST") {
      // Saját teszthez: ugyanaz a futtató, amit a modell kap, csak közvetlenül.
      const token = url.searchParams.get("token") || "";
      if (!env.CORE_TOKEN || token !== env.CORE_TOKEN) return json({ ok: false, error: "forbidden" }, 403);
      let body = {};
      try { body = await request.json(); } catch { body = {}; }
      const result = await runSnippet(env, String(body.lang || "python"), String(body.code || ""), body.timeout || 8);
      return json(result);
    }
    if (path === "/sandbox/status" && request.method === "GET") {
      return json({
        ok: true,
        configured: Boolean(env.SANDBOX_URL && env.SANDBOX_TOKEN),
        runner: runnerReady(env),
        ready: sandboxReady(env),
        provider: env.SANDBOX_URL && env.SANDBOX_TOKEN ? "selfhost"
          : String(env.SANDBOX || "").toLowerCase() === "off" ? "off" : "public",
        url: env.SANDBOX_URL ? String(env.SANDBOX_URL).replace(/\/\/.*@/, "//") : null,
      });
    }

    if ((path === "/grid" || path === "/grid/") && request.method === "GET") {
      return new Response(GRID_HTML, {
        headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300" },
      });
    }

    if (path === "/health") {
      const wired = engines(env).map((e) => e.id);
      return json({
        ok: true,
        service: "Cortex AI",
        model: "Cortex Void",
        vendor: "OmegaTech × CortexAnime",
        tiers: Object.entries(TIERS).map(([k, v]) => ({ id: k, label: v.label })),
        redundancy: wired.length,
        grid: true,
        core: true,
        phantom: true,
        phantomSeries: BRAIN_CACHE.series || 0,
        image: Boolean(env.XKIRO_API_KEY),
        now: new Date().toISOString(),
      });
    }

    // Offline modellcsomagok: ez a katalógus mondja meg az appnak, van-e új modell
    // és mekkora a letöltés. Apró, gyorsítótárazható válasz, hogy ne fogyasszon keretet.
    if (path === "/models" && request.method === "GET") {
      const body = { ok: true, rev: MODEL_REV, updated: "2026-11-02", packs: MODEL_PACKS };
      return new Response(JSON.stringify(body), {
        headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "public, max-age=600", ...cors },
      });
    }

    if (path === "/engines") {
      if (url.searchParams.get("k") !== env.DIAG_TOKEN) return json({ ok: false, error: "forbidden" }, 403);
      const rows = engines(env).map((e) => ({
        id: e.id,
        kind: e.kind,
        model: e.model,
        benchedUntil: bench.get(e.id) ? new Date(bench.get(e.id)).toISOString() : null,
        ...(stats.get(e.id) || { ok: 0, fail: 0, lastError: null, lastMs: 0 }),
      }));
      return json({ ok: true, engines: rows });
    }

    // ── Cortex Grid: opt-in volunteer compute ────────────────────────────────
    // Only counters live here. The browser does the inference; nothing personal is stored.
    if (path === "/grid/status" || (path === "/grid/report" && request.method === "POST")) {
      // Counters live in R2, not KV: KV's daily read/write quota is shared with the
      // subtitle feed and already runs out; R2 has no per-day operation ceiling.
      const bucket = env.CORTEX_R2;
      const key = "cortexai/grid/stats.json";
      const read = async () => {
        if (!bucket) return { total: 0, updated: null };
        const obj = await bucket.get(key);
        if (!obj) return { total: 0, updated: null };
        try { return await obj.json(); } catch { return { total: 0, updated: null }; }
      };
      const stats = await read();
      if (path === "/grid/status") return json({ ok: true, total: stats.total || 0, updated: stats.updated || null });

      let body;
      try { body = await request.json(); } catch { return json({ ok: false, error: "bad json" }, 400); }
      const done = Math.max(0, Math.min(500, Number(body.done) || 0));
      if (!done) return json({ ok: true, total: stats.total || 0 });
      const next = { total: (stats.total || 0) + done, updated: new Date().toISOString() };
      if (bucket) await bucket.put(key, JSON.stringify(next), { httpMetadata: { contentType: "application/json" } });
      return json({ ok: true, total: next.total });
    }

    if (path === "/app/ipa" && (request.method === "GET" || request.method === "HEAD")) return appIpa(request, env, ctx);
    if (path === "/app/source.json" && request.method === "GET") return appSource(request, env, ctx);
    if (path === "/app/icon.png" && request.method === "GET") return appIcon(env);
    if (path === "/app/apk" && (request.method === "GET" || request.method === "HEAD")) return appBinary(env, "android/CortexAI-1.0-android.apk", "CortexAI-1.0-android.apk");
    if (path === "/app/win" && (request.method === "GET" || request.method === "HEAD")) return appBinary(env, "windows/CortexAI-1.0-windows.exe", "CortexAI-1.0-windows.exe");
    if (path === "/app/stats" && request.method === "GET") return appStats(env);
    if (path === "/sponsor/hit" && (request.method === "GET" || request.method === "POST")) return sponsorHit(request, env, ctx);
    if (path === "/sponsor/stats" && request.method === "GET") return sponsorStats(env);
    if ((path === "/app/install" || path === "/app") && request.method === "GET") return appInstall(request, env);
    if (path === "/v1/models" && request.method === "GET") {
      return json({ object: "list", data: [{ id: MODEL_ID, object: "model", created: 0, owned_by: "OmegaTech" }] });
    }
    if (path === "/v1/chat/completions" && request.method === "POST") return v1Chat(request, env);
    if ((path === "/phantom" || path === "/phantom/") && request.method === "GET") {
      return new Response(PHANTOM_HTML, {
        headers: { "Content-Type": "text/html; charset=utf-8", "Cache-Control": "public, max-age=300" },
      });
    }
    if (path === "/phantom/ask" && request.method === "POST") return phantomAsk(request, env);
    if (path === "/phantom/search" && request.method === "GET") return phantomSearchRoute(request, env);
    if (path === "/phantom/questions" && request.method === "GET") return phantomQuestionsRoute(request, env);
    if (path === "/phantom/knowledge/reset" && request.method === "POST") return phantomKnowledgeReset(request, env);
    if (path === "/core" && request.method === "GET") return json(await coreStatus(env));
    if (path === "/core/report" && request.method === "POST") return coreReport(request, env);
    if (path === "/chat" && request.method === "POST") return chat(request, env);
    if (path === "/image" && request.method === "POST") return imageCreate(request, env, ctx);
    if (path.startsWith("/image/") && request.method === "GET") {
      const tail = path.slice(7);
      if (tail.endsWith("/file")) return imageFile(tail.slice(0, -5), env);
      return imageStatus(tail, env);
    }
    // Napi adatfolyam: a brief mindig kéznél van, keresés nélkül is naprakész.
    if (path === "/kb/daily" && request.method === "GET") {
      const brief = await feedBrief(env);
      return json(brief ? { ok: true, brief } : { ok: false, error: "no_brief" }, brief ? 200 : 404);
    }
    if (path === "/kb/search" && request.method === "GET") {
      const q = url.searchParams.get("q") || "";
      const hits = await feedSearch(env, q.toLowerCase());
      return json({ ok: true, q, hits });
    }
    // Éjjeli tanítóadat-gyár: állapot + kézi kör (védett).
    if (path === "/training/status" && request.method === "GET") {
      const raw = env.CORTEX_R2 ? await env.CORTEX_R2.get("cortexai/phantom/training/index.json") : null;
      const idx = raw ? JSON.parse(await raw.text()) : null;
      return json(idx ? { ok: true, ...idx } : { ok: false, error: "no_data" }, idx ? 200 : 404);
    }
    if (path === "/training/refresh" && request.method === "POST") {
      const tok = request.headers.get("X-Diag") || "";
      if (!env.DIAG_TOKEN || tok !== env.DIAG_TOKEN) return json({ ok: false, error: "forbidden" }, 403);
      const r = await trainingJob(env);
      return json({ ok: true, ...r });
    }
    // Kézi frissítés (védett): a napi cron ugyanezt futtatja.
    if (path === "/kb/refresh" && request.method === "POST") {
      const tok = request.headers.get("X-Diag") || "";
      if (!env.DIAG_TOKEN || tok !== env.DIAG_TOKEN) return json({ ok: false, error: "forbidden" }, 403);
      const brief = await feedJob(env);
      return json({ ok: true, counts: brief.counts, date: brief.date });
    }

    return json({ ok: false, error: "not_found" }, 404);
  },

  // Napi cron (04:00 UTC = 05:00 CET): a modell minden nap friss adatot kap,
  // keresés nélkül is naprakész.
  async scheduled(controller, env, ctx) {
    ctx.waitUntil(feedJob(env).catch(() => null));
    // éjjeli tanítóadat-gyár — konstíciós párok minden nap, szerveren
    ctx.waitUntil(trainingJob(env).catch(() => null));
  },
};
