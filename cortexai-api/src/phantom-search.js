// Cortex Phantom — kereső réteg.
//
// Három dolgot csinál, és mind a három a "tanulás közben" része:
//
//   1. TUDÁSTÁR (R2): amit egyszer már megkerestünk, eltároljuk. A következő ugyanolyan
//      kérdésre már nem megy ki a hálózatra — azonnal válaszolunk. Minél többen kérdeznek,
//      annál okosabb lesz, és annál kevesebb külső hívás kell. Ez a tanulás első formája:
//      a válasz megmarad, nem vész el a beszélgetés végén.
//
//   2. KERESŐ: kulcs nélküli források, hogy semmitől ne függjön —
//      Wikipédia (magyar, aztán angol), AniList (animéhez), DuckDuckGo (rövid válasz).
//      A válasz nem "modell-találgatás", hanem a forrás szövege, a forrás megnevezésével.
//
//   3. KÉRDÉSNAPLÓ (R2): minden kérdés bekerül, akár tudtuk, akár nem. Az éjszakai
//      tanulókör ebből épít példákat — vagyis a modell a valódi kérdésekből tanul,
//      nem a fejlesztő fantáziájából.
//
// A réteg szándékosan hibatűrő: ha bármelyik forrás vagy az R2 nem elérhető,
// a válasz egyszerűen "nem tudom" lesz, nem hiba.

// v2: a v1-be teszt közben rossz válasz (Barnet kerület) került, és az izolátumok
// memóriája visszaírta. Új kulcs = tiszta tudástár, a régi magától elavul.
const KNOWLEDGE_KEY = "cortexai/phantom/knowledge.v3.json";
const QUESTIONS_KEY = "cortexai/phantom/questions.json";
const KNOWLEDGE_MAX = 4000;
const QUESTIONS_MAX = 3000;

// ── szöveg-normalizálás ──────────────────────────────────────────────────────
export function fold(text) {
  return (text || "")
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-z0-9\s]/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

const STOP = new Set(("a az es meg hogy nem egy van is de ezt azt csak mar meg itt ott vagy lesz " +
  "mi mit ki kit hol mikor mennyi hany milyen melyik van-e neked nekem tudsz tudod " +
  "kerlek mondd mond el nekem valamit valami rola olyan mint szerint kb").split(" "));

function contentTokens(text) {
  return fold(text).split(" ").filter((t) => t.length > 1 && !STOP.has(t));
}

function overlap(aTokens, bTokens) {
  if (!aTokens.length || !bTokens.length) return 0;
  const set = new Set(bTokens);
  let hit = 0;
  for (const t of aTokens) if (set.has(t)) hit++;
  return hit / Math.max(aTokens.length, bTokens.length);
}

// ── R2 segédek ───────────────────────────────────────────────────────────────
export async function readJson(env, key, fallback) {
  if (!env.CORTEX_R2) return fallback;
  try {
    const obj = await env.CORTEX_R2.get(key);
    if (!obj) return fallback;
    return JSON.parse(await obj.text());
  } catch { return fallback; }
}

export async function writeJson(env, key, value) {
  if (!env.CORTEX_R2) return false;
  try {
    await env.CORTEX_R2.put(key, JSON.stringify(value), {
      httpMetadata: { contentType: "application/json" },
    });
    return true;
  } catch { return false; }
}

// ── 1. tudástár ──────────────────────────────────────────────────────────────
let KNOW_CACHE = { at: 0, rows: null };
const KNOW_TTL_MS = 60 * 1000;

async function knowledge(env) {
  const now = Date.now();
  if (KNOW_CACHE.rows && now - KNOW_CACHE.at < KNOW_TTL_MS) return KNOW_CACHE.rows;
  const rows = await readJson(env, KNOWLEDGE_KEY, []);
  KNOW_CACHE = { at: now, rows: Array.isArray(rows) ? rows : [] };
  return KNOW_CACHE.rows;
}

/** Ismert kérdés? A token-átfedés 0,8 felett már ugyanaz a kérdés. */
export async function knowledgeLookup(env, question) {
  const qTok = contentTokens(question);
  if (!qTok.length) return null;
  const rows = await knowledge(env);
  let best = null;
  let bestScore = 0;
  const fresh = Date.now() - 6 * 3600_000;
  for (const row of rows) {
    // Régi hír-válasz: nem tudás, hanem emlék. Hat óra után nem adjuk ki.
    if (row.k === "news" && Date.parse(row.at || 0) < fresh) continue;
    const score = overlap(qTok, row.t || []);
    if (score > bestScore) { bestScore = score; best = row; }
  }
  if (best && bestScore >= 0.8) {
    best.hits = (best.hits || 1) + 1;
    return { text: best.a, sources: best.src || [], kind: best.k || "search", cached: true, score: bestScore };
  }
  return null;
}

/** Új tudás eltárolása. Ugyanaz a kérdés nem kerül be kétszer. */
export async function knowledgeStore(env, question, answer, sources, kind = "search") {
  if (!question || !answer) return false;
  // A hír időérzékeny: holnapra hamis. Ezért a hír-válasz nem kerül a tudástárba.
  if (kind === "news") return false;
  const qTok = contentTokens(question);
  if (!qTok.length) return false;
  const rows = await knowledge(env);
  const at = new Date().toISOString();
  const existing = rows.find((r) => overlap(qTok, r.t || []) >= 0.8);
  if (existing) {
    existing.a = answer;
    existing.src = sources;
    existing.at = at;
    existing.hits = (existing.hits || 1) + 1;
  } else {
    rows.push({ q: question.slice(0, 300), t: qTok, a: answer, src: sources, k: kind, at, hits: 1 });
    while (rows.length > KNOWLEDGE_MAX) rows.shift();
  }
  KNOW_CACHE = { at: Date.now(), rows };
  return writeJson(env, KNOWLEDGE_KEY, rows);
}

// ── 3. kérdésnapló ───────────────────────────────────────────────────────────
export async function logQuestion(env, question, info = {}) {
  if (!question) return false;
  const rows = await readJson(env, QUESTIONS_KEY, []);
  const list = Array.isArray(rows) ? rows : [];
  const q = question.slice(0, 300);
  const existing = list.find((r) => r.q === q);
  const at = new Date().toISOString();
  if (existing) {
    existing.n = (existing.n || 1) + 1;
    existing.at = at;
    existing.kind = info.kind || existing.kind;
    existing.ok = info.ok === undefined ? existing.ok : info.ok;
  } else {
    list.push({ q, t: contentTokens(q), n: 1, at, kind: info.kind || "open", ok: !!info.ok });
    while (list.length > QUESTIONS_MAX) list.shift();
  }
  return writeJson(env, QUESTIONS_KEY, list);
}

/** A tudástár párokban — ebből tanul a modell. */
export async function knowledgePairs(env, limit = 300) {
  const rows = await knowledge(env);
  return rows
    .filter((r) => r.q && r.a && (r.a || "").length > 40 && (r.a || "").length < 1200)
    .sort((a, b) => (b.hits || 1) - (a.hits || 1))
    .slice(0, limit)
    .map((r) => ({ q: r.q, a: r.a, src: r.src || [], kind: r.k || "search", hits: r.hits || 1 }));
}

/** A napló tartalma a tanulókörnek (a hívó felel a jogosultságért). */
export async function readQuestions(env) {
  const rows = await readJson(env, QUESTIONS_KEY, []);
  const list = Array.isArray(rows) ? rows : [];
  const unanswered = list.filter((r) => !r.ok).sort((a, b) => (b.n || 1) - (a.n || 1));
  return {
    total: list.length,
    answered: list.filter((r) => r.ok).length,
    unanswered: unanswered.length,
    top_unanswered: unanswered.slice(0, 50).map((r) => ({ q: r.q, n: r.n || 1 })),
    rows: list.slice(-500),
  };
}

// ── 2. kereső ────────────────────────────────────────────────────────────────
const UA = "CortexPhantom/1.0 (+https://cortanime.eu; contact: support)";

// Kérdésből entitás. A Wikipédia a "hány része van a Frierennek" szó szerinti keresésére
// semmit nem talál, a "Frieren"-re viszont mindent. Ezért tokenenként dobáljuk ki a
// kérdőszavakat, a névelőket és a magyar toldalékokat — a maradék a keresett dolog.
const DROP = new Set(("hany mennyi mi mit ki kik milyen melyik mikor hol hogyan miert mibol " +
  "a az egy van volt vannak voltak neki nekem tudod kerlek mondd meg el meselj meseld keresd " +
  "keresem szerinted mutasd add foglald ossze magyarazd resze reszei resz reszet epizod epizodja " +
  "epizodbol evad evadja evadbol sorozat sorozatnak sorozatban anime animenak animeben pontszama " +
  "pontszam ertekelse mufaja mufaj kategoria tortenete tortenet mirol szol szarmazik keszult " +
  "jatszodik ki kivel mennyit meddig mire mikorra hanyadik hogy s miert tudsz tudom tudnal " +
  "valamit valami valakir erdekel mondanal meselnel kerdeznem szeretnek akarok nezd megtudni " +
  "szeretnem szeretned tudnank lehet legyen lenne voltal").split(" "));

// csak hosszú szavakról vágjuk le, és csak akkor, ha marad elég — a "piece" nem lesz "piec"
const SUFFIXES = ["atok", "etek", "otok", "nak", "nek", "ban", "ben", "bol", "rol", "tol",
  "hoz", "hez", "nal", "nel", "ert", "val", "vel", "ra", "re", "ot", "et", "at", "ja", "je"];

function stripSuffix(word) {
  if (word.length < 7) return word;
  for (const suf of SUFFIXES) {
    if (word.endsWith(suf) && word.length - suf.length >= 5) return word.slice(0, -suf.length);
  }
  return word;
}

export function extractEntity(question) {
  const raw = (question || "").trim().replace(/[?!.:]+$/, "");
  const words = raw.split(/[\s,]+/).filter(Boolean);
  const kept = [];
  for (const w of words) {
    // "Bleach-et" → "Bleach"
    const parts = w.split("-");
    const head = parts.length > 1 && parts[parts.length - 1].length <= 4 ? parts.slice(0, -1).join("-") : w;
    const low = fold(head);
    if (!low || DROP.has(low)) continue;
    kept.push({ orig: head, low: stripSuffix(low), stripped: stripSuffix(low) !== low });
  }
  // a toldalékot levágva keressük (Frierennek → Frieren), a nagybetűt megtartva
  const entity = kept.map((k) => (k.stripped
    ? (k.orig[0] === k.orig[0].toUpperCase() ? k.low.charAt(0).toUpperCase() + k.low.slice(1) : k.low)
    : k.orig))
    .join(" ").trim();
  if (entity.length >= 3) return entity;
  // ha minden kiesett (pl. "hány része van?"), az eredeti kérdés marad
  return raw;
}

/**
 * Ténykérdés-e? A kereső csak ilyenkor szólal meg a beszélgetésben — versre, kódra,
 * fordítésre nem hozunk wikipédiás bekezdést, azt a modell írja.
 */
export function wantsFacts(question) {
  const f = fold(question);
  if (/(irj|fogalmazz|mese|kepzelj|fordits|kodold|kodot irj|swift|javascript|python|verset|dalt|viccet|levelt)/.test(f)) return false;
  // A frissesség is ténykérdés: „mi a helyzet most”, „mik a hírek” — ide forrás kell, nem emlékezet.
  if (/(hir|hír|hirek|hírek|legfrissebb|friss|mi tortent|mi történt|bejelentett|megjelent|ki nyert|trailer|elozetes|előzetes)/.test(f)) {
    return /(anime|manga|sorozat|resze|jatek|film|sport|meccs|hirek|hírek|mi tortent|mi történt|legfrissebb|friss|bejelentett|megjelent)/.test(f);
  }
  return /(mi az|mi a|ki az|ki volt|mikor|hol van|hol talal|mennyi az|hany|melyik evben|miert|hogyan mukodik|magyarazd|definiald|jelentese|what is|who is|when did|how many)/.test(f);
}

/** Kifejezetten friss hírt kér? Ilyenkor a hírforrás megy a katalógus elé. */
export function wantsNews(question) {
  const f = fold(question);
  if (!/(hir|hirek|legfrissebb|friss|mi tortent|bejelentett|megjelent|ki nyert|trailer|elozetes)/.test(f)) return false;
  return /(anime|manga|sorozat|jatek|film|sport|meccs|hirek|mi tortent|legfrissebb|friss|bejelentett|megjelent)/.test(f);
}

/** Animéra utaló jel? Ha igen, az AniList az első forrás. */
export function looksAnime(question) {
  return /(anime|manga|resze|reszei|epizod|evad|sorozat|mufaj|studio|mangaka|seiyuu|ova|ona|felirat)/.test(fold(question));
}

async function getJson(url, timeoutMs = 9000) {
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const r = await fetch(url, { headers: { "User-Agent": UA, Accept: "application/json" }, signal: ctrl.signal });
    if (!r.ok) return null;
    return await r.json();
  } catch { return null; } finally { clearTimeout(timer); }
}

/** A cikk bevezetője a régi API-n, ha a REST summary épp nem ad semmit. */
async function wikiExtractFallback(title, lang) {
  const u = `https://${lang}.wikipedia.org/w/api.php?action=query&format=json&prop=extracts&exintro=1&explaintext=1&titles=${encodeURIComponent(title)}`;
  const d = await getJson(u);
  const page = d?.query?.pages ? Object.values(d.query.pages)[0] : null;
  return (page?.extract || "").trim();
}

/** Wikipédia: magyar előbb, aztán angol. Rövid, tényleges kivonat. */
async function wikipedia(term, lang) {
  const searchUrl = `https://${lang}.wikipedia.org/w/api.php?action=query&format=json&list=search&srlimit=3&srsearch=${encodeURIComponent(term)}`;
  const found = await getJson(searchUrl);
  const candidates = found?.query?.search || [];
  if (!candidates.length) return null;

  // Relevancia-kapu: a talált cikk címe osszon meg legalább egy szót a keresettel.
  // Enélkül a "fekete lyuk" angolul egy budapesti szórakozóhelyet hozott (Fekete Lyuk).
  const want = new Set(contentTokens(term));
  const relevant = candidates.filter((c) => contentTokens(c.title).some((t) => want.has(t)));
  if (!relevant.length) return null;   // a "Frieren" magyar wikin semmit nem ad: inkább nincs válasz
  const title = relevant[0].title;

  const sum = await getJson(`https://${lang}.wikipedia.org/api/rest_v1/page/summary/${encodeURIComponent(title)}`);
  let extract = (sum?.extract || "").trim();
  if (!extract) extract = await wikiExtractFallback(title, lang);
  // Az egyértelműsítő lap ("Szent István" → 12 jelentés) nem rossz válasz, ha megmondjuk,
  // hogy választani kell. Ez őszintébb, mint egy találomra kiválasztott cikk.
  if (sum?.type === "disambiguation") {
    if (!extract) {
      return {
        text: `A(z) ${sum?.title || title} több dolgot is jelent. Pontosítsd, melyikre gondolsz.`,
        title: sum?.title || title, url: "", source: lang === "hu" ? "Wikipédia" : "Wikipedia",
        disambiguation: true,
      };
    }
    return {
      text: `A(z) ${sum?.title || title} több dolgot is jelent: ${extract}`,
      title: sum?.title || title,
      url: sum?.content_urls?.desktop?.page || "",
      source: lang === "hu" ? "Wikipédia" : "Wikipedia",
      disambiguation: true,
    };
  }
  if (!extract) return null;
  return {
    text: extract,
    title: sum?.title || title,
    url: sum.content_urls?.desktop?.page || `https://${lang}.wikipedia.org/wiki/${encodeURIComponent(title)}`,
    source: lang === "hu" ? "Wikipédia" : "Wikipedia",
  };
}

/** AniList: ha a saját katalógusban nincs benne a sorozat. */
async function anilist(term) {
  const first = await anilistOnce(term);
  if (first !== undefined) return first;
  return anilistOnce(term);      // átmeneti hiba (429/5xx) esetén még egyszer
}

/** undefined = átmeneti hiba (érdemes újra), null = nincs ilyen anime */
async function anilistOnce(term) {
  const query = `query($s:String){ Page(perPage:1){ media(search:$s, type:ANIME){
    title{ romaji english native } episodes format status averageScore genres description(asHtml:false) startDate{ year } } } }`;
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), 9000);
  try {
    const r = await fetch("https://graphql.anilist.co", {
      method: "POST",
      headers: { "Content-Type": "application/json", Accept: "application/json", "User-Agent": UA },
      body: JSON.stringify({ query, variables: { s: term } }),
      signal: ctrl.signal,
    });
    if (!r.ok) return r.status === 429 || r.status >= 500 ? undefined : null;
    const data = await r.json();
    const m = data?.data?.Page?.media?.[0];
    if (!m) return null;
    const title = m.title?.english || m.title?.romaji || m.title?.native;
    const bits = [];
    if (m.episodes) bits.push(`${m.episodes} rész`);
    if (m.format) bits.push({ TV: "tévésorozat", TV_SHORT: "rövid sorozat", MOVIE: "film", OVA: "OVA", ONA: "ONA", SPECIAL: "különkiadás", MUSIC: "zenei" }[m.format] || String(m.format).toLowerCase());
    if (m.startDate?.year) bits.push(String(m.startDate.year));
    if (m.averageScore) bits.push(`${(m.averageScore / 10).toFixed(1)} pontos`);
    if ((m.genres || []).length) bits.push((m.genres || []).join(", "));
    const state = { FINISHED: "befejezett", RELEASING: "jelenleg fut", NOT_YET_RELEASED: "még nem indult" }[m.status] || "";
    if (state) bits.push(state);
    let text = `${title}: ${bits.join(", ")}.`;
    const desc = (m.description || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
    if (desc) text += " " + (desc.length > 1100 ? desc.slice(0, 1100).replace(/\s+\S*$/, "") + "…" : desc);
    return { text, title, url: `https://anilist.co/anime/${m.id || ""}`, source: "AniList" };
  } catch { return undefined; } finally { clearTimeout(timer); }
}

/** DuckDuckGo azonnali válasz — rövid, de gyors, és sok mindenre elég. */
/** RSS → elemek. Csak a cím, a link, a dátum és a forrás kell. */
function decodeEntities(text) {
  return String(text || "")
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&nbsp;/g, " ")
    .replace(/<[^>]+>/g, "")
    .trim();
}

function rssItems(xml, limit = 5) {
  const out = [];
  const re = /<item[^>]*>([\s\S]*?)<\/item>/g;
  let m;
  while ((m = re.exec(xml)) && out.length < limit) {
    const block = m[1];
    const pick = (tag) => {
      const hit = block.match(new RegExp(`<${tag}[^>]*>([\\s\\S]*?)</${tag}>`));
      return hit ? decodeEntities(hit[1]) : "";
    };
    const title = pick("title");
    if (!title) continue;
    const rawDate = pick("pubDate");
    const parsed = rawDate ? new Date(rawDate) : null;
    const day = parsed && !Number.isNaN(parsed.getTime()) ? parsed.toISOString().slice(0, 10) : "";
    out.push({ title, link: pick("link"), source: pick("source"), date: day });
  }
  return out;
}

/** Friss hírek egy témában. Ez az, amit a Wikipédia nem tud: a mai nap. */
const NEWS_CACHE = new Map();

// Magyar toldalékok, amikkel egy címke szó a címben szerepelhet (chainsaw → chainsawról).
const HU_SUFFIX = new Set([
  "", "t", "ot", "et", "at", "ok", "ek", "ak", "i", "ja", "je", "a", "e",
  "rol", "rol", "tol", "hoz", "hez", "ban", "ben", "nak", "nek", "val", "vel",
  "ra", "re", "on", "en", "ig", "ert", "kent", "kori", "beli", "s", "os", "es",
]);

/** Egy szó a címben: a token egy szó elején áll, és a maradék magyar toldalék. */
function wordHit(title, token) {
  const words = fold(title).split(" ");
  for (const word of words) {
    if (word === token) return true;
    if (word.startsWith(token) && HU_SUFFIX.has(word.slice(token.length))) return true;
    // Fordítva: a kérdés szava hordoz toldalékot („monarchról” → „monarch”).
    if (token.startsWith(word) && word.length >= 4 && HU_SUFFIX.has(token.slice(word.length))) return true;
  }
  return false;
}

function termScore(title, tokens) {
  return tokens.reduce((n, t) => n + (wordHit(title, t) ? 1 : 0), 0);
}

// Kérdés-szavak, amik önmagukban nem jelentenek témát: ezekre nem illesztünk hírt.
// Hír-kérdés szavai: nem témát jelentenek, hanem szándékot.
const NEWS_WORDS = new Set([
  "hir", "hirek", "hiret", "hire", "legfrissebb", "friss", "ma", "mai", "tegnap", "heti",
  "milyen", "vannak", "van", "tortent", "anime", "manga", "sorozat", "jatek", "film",
]);

/** A hír-kérdés valódi témája (a szándék-szavak nélkül). Üres = általános hírkérés. */
export function newsSubject(question) {
  return contentTokens(String(question || "")).filter((t) => t.length >= 3 && !NEWS_WORDS.has(t));
}

const NEWS_STOP = new Set([
  "van", "vannak", "volt", "lesz", "uj", "legujabb", "friss", "hirek", "hir", "hiret",
  "mi", "mit", "milyen", "mikor", "hol", "ki", "kik", "hogy", "hogyan", "miert", "mennyi",
  "about", "news", "latest", "what", "when", "who", "how", "why", "the", "and", "for",
]);
const NEWS_TTL = 10 * 60_000;

// Magyar hírforrások. A Google News kiváló találatokat ad, de a worker kimenő IP-jét
// időnként korlátozza — ezért ezek a tartalékok, és napi briefhez ezek mennek.
const NEWS_FEEDS = [
  { url: "https://hu.ign.com/feed.xml", source: "IGN Hungary" },
  { url: "https://444.hu/feed", source: "444" },
  { url: "https://telex.hu/rss", source: "Telex" },
];

async function feedNews(term, limit, { requireMatch = true } = {}) {
  const tokens = fold(term).split(/\s+/).filter((t) => t.length >= 3);
  const batches = await Promise.all(NEWS_FEEDS.map(async (feed) => {
    try {
      const res = await fetch(feed.url, {
        headers: { "User-Agent": "CortexAI/2.6 (+https://cortanime.eu)" },
        signal: AbortSignal.timeout(5000),
      });
      if (!res.ok) return [];
      const xml = await res.text();
      return rssItems(xml, 30).map((it) => ({
        ...it,
        source: it.source || feed.source,
        score: termScore(it.title, tokens),
      }));
    } catch { return []; }
  }));
  let all = batches.flat().filter((it) => it.title);
  if (requireMatch && tokens.length) {
    all = all.filter((it) => it.score > 0);
    all.sort((a, b) => (b.score - a.score) || String(b.date).localeCompare(String(a.date)));
  } else {
    all.sort((a, b) => String(b.date).localeCompare(String(a.date)));
  }
  return all.slice(0, limit);
}

/** A legfrissebb játék/anime hírek szűrés nélkül — a napi briefhez. */
export async function topNews(limit = 3) {
  const cacheKey = `top|${limit}`;
  const cached = NEWS_CACHE.get(cacheKey);
  if (cached && Date.now() - cached.at < NEWS_TTL) return cached.hit;
  try {
    const rows = await feedNews("", limit, { requireMatch: false });
    NEWS_CACHE.set(cacheKey, { at: Date.now(), hit: rows });
    return rows;
  } catch {
    return [];
  }
}

export async function news(term, { limit = 4, feeds: feedCount = 2 } = {}) {
  // A teljes kérdés rossz keresőkifejezés: a „legfrissebb” és a „mi a” elviszi a találatokat.
  const qTokens = newsSubject(term);
  if (!qTokens.length) return null;  // általános hírkérés: azt a hívó dönti el (top hírek)
  const q = qTokens.join(" ");
  const cacheKey = `${q.toLowerCase()}|${limit}`;
  const cached = NEWS_CACHE.get(cacheKey);
  if (cached && Date.now() - cached.at < NEWS_TTL) return cached.hit;

  const feeds = [
    `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=hu&gl=HU&ceid=HU:hu`,
    `https://news.google.com/rss/search?q=${encodeURIComponent(q)}&hl=en-US&gl=US&ceid=US:en`,
  ].slice(0, Math.min(Math.max(feedCount, 1), 2));
  const googleTask = (async () => {
    for (const url of feeds) {
      try {
        const res = await fetch(url, {
          headers: { "User-Agent": "CortexAI/2.6 (+https://cortanime.eu)" },
          signal: AbortSignal.timeout(4500),
        });
        if (!res.ok) continue;
        const xml = await res.text();
        const found = rssItems(xml, limit);
        if (found.length >= 2) return found;
        if (found.length) return found;
      } catch { /* következő kiadás */ }
    }
    return [];
  })();
  const feedTask = feedNews(q, limit).catch(() => []);
  // Amelyik gyorsabb és van találata. A Google a pontosabb, a feedek a biztosabbak.
  const [googleItems, feedItems] = await Promise.all([googleTask, feedTask]);
  // A Google News a kérdésre lazán illeszkedő címeket is adhat (más sorozat, más téma).
  // Csak azt tartjuk meg, amiben a kérdés egyik értelmes szava szerepel a címben.
  const tokens = fold(q).split(/\s+/).filter((t) => t.length >= 3 && !NEWS_STOP.has(t));
  const phrase = fold(q);
  const need = Math.min(tokens.length, 2);
  const relevant = (rows) => (tokens.length
    ? rows.filter((it) => {
        if (tokens.length >= 2 && fold(it.title).includes(phrase)) return true;
        return termScore(it.title, tokens) >= need;
      })
    : rows);
  const googleHits = relevant(googleItems);
  const feedHits = relevant(feedItems);
  let items = googleHits.length >= 2 ? googleHits : (feedHits.length ? feedHits : googleHits);
  // A cache-be a kész válasz megy, hogy a második hívás azonnal jöjjön.

  if (!items.length) return null;
  const text = items
    .map((it) => `${it.date ? it.date + " · " : ""}${it.title}${it.source ? " (" + it.source + ")" : ""}`)
    .join("\n");
  const hit = {
    text: "Friss hírek:\n" + text,
    title: `Hírek: ${q}`,
    source: "Google News",
    url: items[0].link || "",
    sources: items.map((it) => it.link).filter(Boolean).slice(0, 3),
    items,
    kind: "news",
  };
  NEWS_CACHE.set(cacheKey, { at: Date.now(), hit });
  return hit;
}

async function ddg(term) {
  const d = await getJson(`https://api.duckduckgo.com/?q=${encodeURIComponent(term)}&format=json&no_html=1&skip_disambig=1`);
  const text = (d?.AbstractText || d?.Answer || "").trim();
  if (!text || text.length < 20) return null;
  return {
    text,
    title: d.Heading || term,
    url: d.AbstractURL || "",
    source: "DuckDuckGo",
  };
}

/**
 * Keresés több forrásból. Az első találat nyer, de a forrás nevét mindig megmondjuk,
 * mert a Phantom nem tippel: ha nem tudja, azt mondja, és megmutatja, honnan jött.
 */
export async function search(env, question, { anime } = {}) {
  const raw = (question || "").trim().replace(/[?.!]+$/, "");
  if (!raw || raw.length < 3) return null;
  // Tanácsot kér ("ajánlj valamit") — ez nem keresés, hanem ajánlás: az agy dolga.
  if (/(ajanl|javasolj|mit nezzek|mit nezzem|melyik a jobb|melyiket valasszam)/.test(fold(raw))) return null;

  const entity = extractEntity(raw);
  const wantAnime = anime === undefined ? looksAnime(raw) : anime;

  const t = entity;
  // Időérzékeny kérdés: előbb a mai hírek, aztán a lexikon. Ha nem az, marad a régi sorrend.
  const fresh = /(hir|hír|hirek|hírek|friss|legujabb|legújabb|\bma\b|\bmai\b|tegnap|ezen a heten|ezen a héten|ki nyert|meccs|bemutato|bemutató|megjelenik|mikor jon ki|mikor jön ki|ujdonsag|újdonság|bejelentette|trailer|elozetes|előzetes)/.test(fold(raw));
  const attempts = wantAnime
    ? [() => anilist(t), () => wikipedia(t, "hu"), () => wikipedia(t, "en"), () => ddg(t), () => anilist(raw)]
    : [() => wikipedia(t, "hu"), () => wikipedia(t, "en"), () => ddg(t), () => anilist(t), () => wikipedia(raw, "hu")];
  if (fresh) attempts.unshift(() => news(t, { limit: 4 }));

  for (const attempt of attempts) {
    let hit = null;
    try { hit = await attempt(); } catch { hit = null; }
    if (hit && hit.text && hit.text.length > 20) {
      return {
        text: hit.text,
        title: hit.title,
        source: hit.source,
        url: hit.url,
        sources: [hit.url].filter(Boolean),
      };
    }
  }
  return null;
}

/** A keresés eredményéből emberi válasz. A forrást mindig kimondjuk. */
export function compose(question, hit) {
  if (!hit) return null;
  let text = hit.text.trim();
  if (!/[.!?…]$/.test(text)) text += ".";
  const title = (hit.title || "").trim();
  const same = title && fold(title) === fold(question);
  const from = hit.source ? `\n\nForrás: ${hit.source}${title && !same ? " — " + title : ""}.` : "";
  return { text: text + from, sources: hit.sources || [], kind: "search" };
}

/** A tudástár ürítése — akkor kell, ha egyszer rossz válasz került bele. */
export async function resetKnowledge(env, question = "") {
  if (!question) {
    KNOW_CACHE = { at: 0, rows: null };
    if (env.CORTEX_R2) { try { await env.CORTEX_R2.delete(KNOWLEDGE_KEY); } catch { /* ignore */ } }
    return { cleared: "all" };
  }
  const qTok = contentTokens(question);
  const rows = await knowledge(env);
  const kept = rows.filter((r) => overlap(qTok, r.t || []) < 0.8);
  KNOW_CACHE = { at: Date.now(), rows: kept };
  await writeJson(env, KNOWLEDGE_KEY, kept);
  return { cleared: rows.length - kept.length, left: kept.length };
}

export const keys = { KNOWLEDGE_KEY, QUESTIONS_KEY };
