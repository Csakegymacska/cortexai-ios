/* ============================================================================
   CORTEX API PLATFORM  ·  CORTEXAPI_V1
   ----------------------------------------------------------------------------
   Mit ad:
     · API-kulcs generálás a weben (cortanime.eu/api-keys) — a kulcs EGYSZER látszik
     · OpenAI-kompatibilis végpont: POST /api/v1/chat/completions
     · Napi token-kvóta csomagonként: free 50M · pro 220M · max 2.2B
     · Használat-mérés: /api/keys/usage, /api/v1/usage
   Motor: DeepSeek (deepseek-flash = V4.1-Flash, 1M kontextus)
   ========================================================================== */

const CAP_TIERS = {
  free: { id: "free", label: "Free", tokensPerDay: 5_000_000, rpm: 20, keyLimit: 2, price: "ingyenes" },
  pro:  { id: "pro",  label: "Pro",  tokensPerDay: 50_000_000, rpm: 120, keyLimit: 10, price: "1 990 Ft/hó" },
  max:  { id: "max",  label: "Max",  tokensPerDay: 500_000_000, rpm: 600, keyLimit: 40, price: "4 990 Ft/hó" },
};
const CAP_REVOLUT = "https://revolut.me/tibikegh12";
const CAP_UPSTREAM = "https://api.deepseek.com";
const CAP_MODEL_DEFAULT = "deepseek-flash";

const CAP_SCHEMA = [
  `CREATE TABLE IF NOT EXISTS cortex_api_keys(
     id TEXT PRIMARY KEY,
     user_id INTEGER NOT NULL,
     name TEXT NOT NULL,
     prefix TEXT NOT NULL,
     hash TEXT NOT NULL,
     created_at INTEGER NOT NULL,
     last_used_at INTEGER,
     revoked_at INTEGER
   )`,
  `CREATE TABLE IF NOT EXISTS cortex_api_usage(
     key_id TEXT NOT NULL,
     day TEXT NOT NULL,
     calls INTEGER NOT NULL DEFAULT 0,
     prompt_tokens INTEGER NOT NULL DEFAULT 0,
     completion_tokens INTEGER NOT NULL DEFAULT 0,
     PRIMARY KEY (key_id, day)
   )`,
  `CREATE TABLE IF NOT EXISTS cortex_api_tiers(
     user_id INTEGER PRIMARY KEY,
     tier TEXT NOT NULL DEFAULT 'free',
     source TEXT,
     since INTEGER,
     until INTEGER
   )`,
  `CREATE TABLE IF NOT EXISTS cortex_sub_codes(
     code TEXT PRIMARY KEY,
     tier TEXT NOT NULL,
     days INTEGER NOT NULL DEFAULT 31,
     note TEXT,
     created_at INTEGER NOT NULL,
     redeemed_by INTEGER,
     redeemed_at INTEGER
   )`,
  `CREATE TABLE IF NOT EXISTS cortex_user_ai(
     user_id INTEGER PRIMARY KEY,
     ai_name TEXT,
     persona TEXT,
     style TEXT,
     updated_at INTEGER
   )`,
  `CREATE INDEX IF NOT EXISTS idx_cap_hash ON cortex_api_keys(hash)`,
];

let capReady = false;

// Egyszeri seed: Revolut-beváltókódok + a tulajdonos (TibikeYH120) Max előfizetése.
async function capSeed(db) {
  try {
    const done = await db.prepare("SELECT note FROM cortex_sub_codes WHERE note='seeded' LIMIT 1").first();
    if (done) return;
    const now = Math.floor(Date.now() / 1000);
    const codes = [
      ["TIBIKE-MAX-2026", "max", 3650, "tulajdonos"],
      ["CORTEXMAX1M", "max", 31, "revolut után kiosztható"],
      ["CORTEXPRO1M", "pro", 31, "revolut után kiosztható"],
    ];
    for (const [code, tier, days, note] of codes) {
      await db.prepare("INSERT OR IGNORE INTO cortex_sub_codes(code,tier,days,note,created_at) VALUES(?,?,?,?,?)")
        .bind(code, tier, days, note, now).run();
    }
    await db.prepare("INSERT OR IGNORE INTO cortex_sub_codes(code,tier,days,note,created_at) VALUES('seeded','free',1,'seeded',?)").bind(now).run();
    // Tulajdonos: Max, 10 évre
    await db.prepare(
      "INSERT INTO cortex_api_tiers(user_id,tier,source,since,until) " +
      "SELECT id,'max','owner',?,? FROM users WHERE username='TibikeYH120' LIMIT 1 " +
      "ON CONFLICT(user_id) DO UPDATE SET tier='max', source='owner', until=MAX(excluded.until, cortex_api_tiers.until)")
      .bind(now, now + 3153600000).run();
  } catch { /* a seed hibája nem akadályozza a szolgáltatást */ }
}
async function capDB(env) {
  if (!env || !env.DB) return null;
  if (!capReady) {
    for (const sql of CAP_SCHEMA) {
      try {
        await env.DB.prepare(sql).run();
      } catch {
      }
    }
    await capSeed(env.DB).catch(() => {});
    capReady = true;
  }
  return env.DB;
}

function capDay(ts = Date.now()) {
  return new Date(ts).toISOString().slice(0, 10);
}

function capJson(obj, status = 200, extra = {}) {
  const h = new Headers({
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers": "authorization,content-type",
    "Access-Control-Allow-Methods": "GET,POST,DELETE,OPTIONS",
    "Cache-Control": "no-store",
    ...extra,
  });
  return new Response(JSON.stringify(obj), { status, headers: h });
}

function capErr(status, type, message, code) {
  return capJson({ error: { message, type, code: code || null } }, status);
}

/* ── kulcsok ─────────────────────────────────────────────────────────────── */

const CAP_ALPHABET = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";

function capRandom(n) {
  const b = new Uint8Array(n);
  crypto.getRandomValues(b);
  let s = "";
  for (let i = 0; i < n; i++) s += CAP_ALPHABET[b[i] % CAP_ALPHABET.length];
  return s;
}

async function capHash(token) {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return [...new Uint8Array(d)].map((x) => x.toString(16).padStart(2, "0")).join("");
}

async function capNewKey(userId, name) {
  const secret = capRandom(40);            // 40 karakter, ~238 bit
  const token = "cx_" + secret;
  const prefix = "cx_" + secret.slice(0, 6);
  const id = "key_" + capRandom(14);
  return { id, token, prefix, hash: await capHash(token), name: name || "default" };
}

async function capTierFor(env, userId) {
  const db = await capDB(env);
  if (!db || !userId) return CAP_TIERS.free;
  let row = null;
  try {
    row = await db.prepare("SELECT tier, until FROM cortex_api_tiers WHERE user_id=?").bind(userId).first();
  } catch {
  }
  if (!row) return CAP_TIERS.free;
  if (row.until && Number(row.until) * 1000 < Date.now()) return CAP_TIERS.free;
  return CAP_TIERS[row.tier] || CAP_TIERS.free;
}

async function capAuthKey(req, env) {
  const h = req.headers.get("Authorization") || req.headers.get("authorization") || "";
  const m = /^Bearer\s+(cx_[A-Za-z0-9]+)$/.exec(h.trim());
  if (!m) return { error: capErr(401, "invalid_request_error", "Hiányzó vagy hibás API-kulcs. Fejléc: Authorization: Bearer cx_…", "missing_key") };
  const db = await capDB(env);
  if (!db) return { error: capErr(503, "server_error", "Az adatbázis nem érhető el.", "no_db") };
  const hash = await capHash(m[1]);
  let key = null;
  try {
    key = await db.prepare("SELECT * FROM cortex_api_keys WHERE hash=? LIMIT 1").bind(hash).first();
  } catch {
  }
  if (!key) return { error: capErr(401, "invalid_request_error", "Érvénytelen API-kulcs.", "invalid_key") };
  if (key.revoked_at) return { error: capErr(401, "invalid_request_error", "Ez a kulcs visszavonva.", "revoked_key") };
  return { key };
}

async function capUsageToday(env, keyId) {
  const db = await capDB(env);
  try {
    const row = await db.prepare("SELECT calls, prompt_tokens, completion_tokens FROM cortex_api_usage WHERE key_id=? AND day=?")
      .bind(keyId, capDay()).first();
    return row || { calls: 0, prompt_tokens: 0, completion_tokens: 0 };
  } catch {
    return { calls: 0, prompt_tokens: 0, completion_tokens: 0 };
  }
}

/** Egész nap összes tokenje a felhasználó összes kulcsára (a kvóta a fiókhoz tartozik). */
async function capUsageUserToday(env, userId) {
  const db = await capDB(env);
  try {
    const row = await db.prepare(
      `SELECT COALESCE(SUM(u.prompt_tokens + u.completion_tokens),0) AS tokens, COALESCE(SUM(u.calls),0) AS calls
         FROM cortex_api_usage u JOIN cortex_api_keys k ON k.id = u.key_id
        WHERE k.user_id=? AND u.day=?`).bind(userId, capDay()).first();
    return { tokens: (row && row.tokens) || 0, calls: (row && row.calls) || 0 };
  } catch {
    return { tokens: 0, calls: 0 };
  }
}

async function capAddUsage(env, keyId, promptTokens, completionTokens) {
  const db = await capDB(env);
  try {
    await db.prepare(
      `INSERT INTO cortex_api_usage(key_id,day,calls,prompt_tokens,completion_tokens) VALUES(?,?,1,?,?)
       ON CONFLICT(key_id,day) DO UPDATE SET calls=calls+1,
         prompt_tokens=prompt_tokens+excluded.prompt_tokens,
         completion_tokens=completion_tokens+excluded.completion_tokens`)
      .bind(keyId, capDay(), promptTokens | 0, completionTokens | 0).run();
  } catch {
  }
}

/* ── OpenAI-kompatibilis végpont ─────────────────────────────────────────── */

async function capChat(req, env, ctx) {
  if (req.method === "OPTIONS") return capJson({}, 204);
  if (req.method !== "POST") return capErr(405, "invalid_request_error", "Csak POST.", "method");

  const auth = await capAuthKey(req, env);
  if (auth.error) return auth.error;
  const key = auth.key;

  let body = null;
  try {
    body = await req.json();
  } catch {
    return capErr(400, "invalid_request_error", "A kérés törzse nem érvényes JSON.", "bad_json");
  }
  if (!Array.isArray(body.messages) || !body.messages.length) {
    return capErr(400, "invalid_request_error", "A `messages` tömb hiányzik vagy üres.", "bad_messages");
  }
  if (body.stream) body.stream_options = { ...(body.stream_options || {}), include_usage: true };

  // 1) kvóta-ellenőrzés
  const tier = await capTierFor(env, key.user_id);
  const used = await capUsageUserToday(env, key.user_id);
  if (used.tokens >= tier.tokensPerDay) {
    return capErr(429, "insufficient_quota",
      `Elfogyott a napi keret (${tier.label}: ${tier.tokensPerDay.toLocaleString("en-US")} token/nap). ` +
      `A keret UTC éjfélkor áll vissza.`, "daily_quota");
  }

  // 2) upstream hívás
  const upstreamBody = { ...body, model: body.model || CAP_MODEL_DEFAULT };
  if (!upstreamBody.model || upstreamBody.model === "phantom") upstreamBody.model = CAP_MODEL_DEFAULT;
  delete upstreamBody.tier;

  let upstream;
  try {
    upstream = await fetch(CAP_UPSTREAM + "/chat/completions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + (env.DEEPSEEK_API_KEY || ""),
        "Content-Type": "application/json",
        Accept: body.stream ? "text/event-stream" : "application/json",
      },
      body: JSON.stringify(upstreamBody),
    });
  } catch (e) {
    return capErr(502, "upstream_error", "A motor nem elérhető: " + String(e && e.message || e), "upstream_unreachable");
  }

  // 3) upstream hiba: változatlanul továbbadjuk, de magyar magyarázattal
  if (!upstream.ok) {
    const text = await upstream.text();
    let payload = null;
    try {
      payload = JSON.parse(text);
    } catch {
    }
    if (upstream.status === 402) {
      return capErr(503, "server_error",
        "A Cortex motor egyenlege elfogyott — a szolgáltatás átmenetileg szünetel. Szólj az üzemeltetőnek.",
        "upstream_balance");
    }
    return new Response(text, {
      status: upstream.status,
      headers: { "Content-Type": "application/json; charset=utf-8", "Access-Control-Allow-Origin": "*" },
    });
  }

  // 4a) nem streamelő válasz: mérjük a usage-t
  if (!body.stream) {
    const text = await upstream.text();
    let payload = null;
    try {
      payload = JSON.parse(text);
    } catch {
    }
    const u = (payload && payload.usage) || {};
    if (ctx && ctx.waitUntil) {
      ctx.waitUntil(capAddUsage(env, key.id, u.prompt_tokens || 0, u.completion_tokens || 0));
      ctx.waitUntil(env.DB.prepare("UPDATE cortex_api_keys SET last_used_at=? WHERE id=?").bind(Math.floor(Date.now() / 1000), key.id).run().catch(() => {}));
    }
    const headers = {
      "Content-Type": "application/json; charset=utf-8",
      "Access-Control-Allow-Origin": "*",
      "X-Cortex-Tier": tier.id,
      "X-Cortex-Quota-Limit": String(tier.tokensPerDay),
      "X-Cortex-Quota-Used": String(used.tokens + (u.prompt_tokens || 0) + (u.completion_tokens || 0)),
    };
    return new Response(text, { status: 200, headers });
  }

  // 4b) streamelő: a választ változatlanul átengedjük, a usage-t a végén olvassuk ki
  const [toClient, toMeter] = upstream.body.tee();
  if (ctx && ctx.waitUntil) {
    ctx.waitUntil((async () => {
      let buf = "";
      try {
        const reader = toMeter.getReader();
        const dec = new TextDecoder();
        let seen = 0;
        for (;;) {
          const { done, value } = await reader.read();
          if (done) break;
          const chunk = dec.decode(value, { stream: true });
          seen += chunk.length;
          if (seen > 240000) continue;                 // ne nőjön a memória, a usage a végén jön
          buf += chunk;
          if (buf.length > 16000) buf = buf.slice(-16000);
        }
      } catch {
      }
      const m = /"usage"\s*:\s*\{[^}]*\}/g;
      let last = null, x;
      while ((x = m.exec(buf))) last = x[0];
      if (last) {
        try {
          const u = JSON.parse("{" + last + "}").usage || {};
          await capAddUsage(env, key.id, u.prompt_tokens || 0, u.completion_tokens || 0);
        } catch {
        }
      }
    })());
  }
  return new Response(toClient, {
    status: 200,
    headers: {
      "Content-Type": "text/event-stream; charset=utf-8",
      "Cache-Control": "no-cache",
      "Access-Control-Allow-Origin": "*",
      "X-Cortex-Tier": tier.id,
    },
  });
}

async function capModels() {
  return capJson({
    object: "list",
    data: [
      {
        id: "deepseek-flash",
        object: "model",
        created: 1762300800,
        owned_by: "cortex",
        name: "Cortex Phantom (deepseek-flash)",
        context_window: 1048576,
        max_output_tokens: 393216,
        input_modalities: ["text", "image"],
      },
    ],
  });
}

async function capUsageEndpoint(req, env) {
  const auth = await capAuthKey(req, env);
  if (auth.error) return auth.error;
  const tier = await capTierFor(env, auth.key.user_id);
  const used = await capUsageUserToday(env, auth.key.user_id);
  return capJson({
    object: "usage",
    tier: tier.id,
    limit: tier.tokensPerDay,
    used: used.tokens,
    remaining: Math.max(0, tier.tokensPerDay - used.tokens),
    calls_today: used.calls,
    resets_at: new Date(Date.UTC(new Date().getUTCFullYear(), new Date().getUTCMonth(), new Date().getUTCDate() + 1)).toISOString(),
  });
}

/* ── kulcskezelés a weben (session-nel) ──────────────────────────────────── */

async function capKeysApi(req, requestUrl, env) {
  const user = await getSessionUser(req, env);
  if (!user) return capErr(401, "auth_required", "Be kell jelentkezned.", "no_session");
  const db = await capDB(env);
  if (!db) return capErr(503, "server_error", "Nincs adatbázis.", "no_db");
  const tier = await capTierFor(env, user.id);
  const path = requestUrl.pathname;

  if (path === "/api/keys/list" || path === "/api/keys") {
    let rows = [];
    try {
      rows = (await db.prepare("SELECT id,name,prefix,created_at,last_used_at,revoked_at FROM cortex_api_keys WHERE user_id=? ORDER BY created_at DESC").bind(user.id).all()).results || [];
    } catch {
    }
    const usage = await capUsageUserToday(env, user.id);
    return capJson({
      ok: true,
      tier: tier.id,
      tier_label: tier.label,
      limit: tier.tokensPerDay,
      used: usage.tokens,
      remaining: Math.max(0, tier.tokensPerDay - usage.tokens),
      key_limit: tier.keyLimit,
      keys: rows,
    });
  }

  if (path === "/api/keys/create" && req.method === "POST") {
    let live = 0;
    try {
      const r = await db.prepare("SELECT COUNT(*) AS n FROM cortex_api_keys WHERE user_id=? AND revoked_at IS NULL").bind(user.id).first();
      live = (r && r.n) || 0;
    } catch {
    }
    if (live >= tier.keyLimit) {
      return capErr(429, "quota", `A ${tier.label} csomagban legfeljebb ${tier.keyLimit} élő kulcs lehet.`, "key_limit");
    }
    let name = "default";
    try {
      const b = await req.json();
      name = String(b.name || "default").slice(0, 40);
    } catch {
    }
    const k = await capNewKey(user.id, name);
    await db.prepare("INSERT INTO cortex_api_keys(id,user_id,name,prefix,hash,created_at) VALUES(?,?,?,?,?,?)")
      .bind(k.id, user.id, k.name, k.prefix, k.hash, Math.floor(Date.now() / 1000)).run();
    // A teljes kulcs CSAK itt, egyszer látszik.
    return capJson({ ok: true, id: k.id, name: k.name, key: k.token, prefix: k.prefix, warning: "Ez az egyetlen alkalom, hogy a kulcs látszik. Másold ki most." });
  }

  if (path === "/api/keys/revoke" && req.method === "POST") {
    let id = "";
    try {
      id = String((await req.json()).id || "");
    } catch {
    }
    if (!id) return capErr(400, "invalid_request_error", "Hiányzó id.", "no_id");
    await db.prepare("UPDATE cortex_api_keys SET revoked_at=? WHERE id=? AND user_id=?")
      .bind(Math.floor(Date.now() / 1000), id, user.id).run();
    return capJson({ ok: true });
  }

  return capErr(404, "not_found", "Ismeretlen végpont.", "not_found");
}

/* ── CORTEX SUBS · Revolut-előfizetés + egyedi AI-profil (CORTEXSUBS_V1) ───── */

async function capSubApi(req, requestUrl, env) {
  const user = await getSessionUser(req, env);
  if (!user) return capErr(401, "auth_required", "Be kell jelentkezned.", "no_session");
  const db = await capDB(env);
  if (!db) return capErr(503, "server_error", "Nincs adatbázis.", "no_db");
  const p = requestUrl.pathname;
  const tier = await capTierFor(env, user.id);

  // ── előfizetési státusz + csomagok + Revolut link ──
  if (p === "/api/sub/status" && req.method === "GET") {
    let until = null;
    try {
      const row = await db.prepare("SELECT until FROM cortex_api_tiers WHERE user_id=?").bind(user.id).first();
      until = row && row.until ? Number(row.until) : null;
    } catch {}
    return capJson({
      ok: true, tier: tier.id, label: tier.label, price: tier.price || "",
      tokensPerDay: tier.tokensPerDay, keyLimit: tier.keyLimit, rpm: tier.rpm,
      until: until ? new Date(until * 1000).toISOString() : null,
      plans: Object.fromEntries(Object.entries(CAP_TIERS).map(([k, v]) =>
        [k, { label: v.label, tokensPerDay: v.tokensPerDay, keyLimit: v.keyLimit, price: v.price || "" }])),
      revolut: CAP_REVOLUT,
    });
  }

  // ── kód beváltása (Revolut után a kapott kód) ──
  if (p === "/api/sub/redeem" && req.method === "POST") {
    let body = {}; try { body = await req.json(); } catch {}
    const code = String(body.code || "").trim().toUpperCase();
    if (!code) return capErr(400, "invalid_request_error", "Hiányzó kód.", "no_code");
    let row = null;
    try { row = await db.prepare("SELECT * FROM cortex_sub_codes WHERE code=?").bind(code).first(); } catch {}
    if (!row) return capErr(404, "not_found", "Ismeretlen kód.", "bad_code");
    if (row.redeemed_by) return capErr(409, "conflict", "Ez a kód már fel lett használva.", "used_code");
    const now = Math.floor(Date.now() / 1000);
    const until = now + (Number(row.days) || 31) * 86400;
    await db.prepare(
      "INSERT INTO cortex_api_tiers(user_id,tier,source,since,until) VALUES(?,?,?,?,?) " +
      "ON CONFLICT(user_id) DO UPDATE SET tier=excluded.tier, source=excluded.source, " +
      "since=excluded.since, until=MAX(excluded.until, cortex_api_tiers.until)")
      .bind(user.id, row.tier, "revolut-code:" + code, now, until).run();
    await db.prepare("UPDATE cortex_sub_codes SET redeemed_by=?, redeemed_at=? WHERE code=?")
      .bind(user.id, now, code).run();
    return capJson({ ok: true, tier: row.tier, until: new Date(until * 1000).toISOString(),
      message: "Előfizetés aktiválva: " + (CAP_TIERS[row.tier] || {}).label });
  }

  // ── kézi odaítélés (csak a tulajdonos) ──
  if (p === "/api/sub/grant" && req.method === "POST") {
    if (user.username !== "TibikeYH120" && (user.role || "") !== "admin") {
      return capErr(403, "forbidden", "Nincs jogosultságod.", "forbidden");
    }
    let body = {}; try { body = await req.json(); } catch {}
    const uname = String(body.username || "").trim();
    const wantTier = String(body.tier || "max").toLowerCase();
    const days = Number(body.days) || 365;
    if (!uname || !CAP_TIERS[wantTier]) return capErr(400, "invalid_request_error", "Kell: username + tier (free|pro|max).", "bad_body");
    const target = await db.prepare("SELECT id FROM users WHERE username=?").bind(uname).first();
    if (!target) return capErr(404, "not_found", "Nincs ilyen felhasználó.", "no_user");
    const now = Math.floor(Date.now() / 1000);
    await db.prepare(
      "INSERT INTO cortex_api_tiers(user_id,tier,source,since,until) VALUES(?,?,?,?," +
      "?) ON CONFLICT(user_id) DO UPDATE SET tier=excluded.tier, source=excluded.source, " +
      "until=MAX(excluded.until, cortex_api_tiers.until)")
      .bind(target.id, wantTier, "grant:" + user.username, now, now + days * 86400).run();
    return capJson({ ok: true, username: uname, tier: wantTier, days });
  }

  // ── egyedi AI-profil: mindenki a saját AI-ját szabhatja testre ──
  if (p === "/api/me/ai") {
    if (req.method === "GET") {
      let row = null;
      try { row = await db.prepare("SELECT ai_name, persona, style, updated_at FROM cortex_user_ai WHERE user_id=?").bind(user.id).first(); } catch {}
      return capJson({ ok: true,
        ai_name: (row && row.ai_name) || "Cortex",
        persona: (row && row.persona) || "",
        style: (row && row.style) || "kiegyensúlyozott",
        updated_at: row ? row.updated_at : null });
    }
    if (req.method === "PUT" || req.method === "POST") {
      let body = {}; try { body = await req.json(); } catch {}
      const aiName = String(body.ai_name || "Cortex").slice(0, 40);
      const persona = String(body.persona || "").slice(0, 2000);
      const style = String(body.style || "kiegyensúlyozott").slice(0, 40);
      const now = Math.floor(Date.now() / 1000);
      await db.prepare(
        "INSERT INTO cortex_user_ai(user_id, ai_name, persona, style, updated_at) VALUES(?,?,?,?,?) " +
        "ON CONFLICT(user_id) DO UPDATE SET ai_name=excluded.ai_name, persona=excluded.persona, " +
        "style=excluded.style, updated_at=excluded.updated_at")
        .bind(user.id, aiName, persona, style, now).run();
      return capJson({ ok: true, ai_name: aiName, persona, style, updated_at: now });
    }
  }

  return capErr(404, "not_found", "Ismeretlen végpont.", "not_found");
}

/** A /api/v1/* router. */
async function cortexApiHandle(req, requestUrl, env, ctx) {
  const p = requestUrl.pathname;
  if (p === "/api/v1/chat/completions") return capChat(req, env, ctx);
  if (p === "/api/v1/models") return capModels();
  if (p === "/api/v1/usage") return capUsageEndpoint(req, env);
  return capErr(404, "not_found", "Ismeretlen végpont. Használd: /api/v1/chat/completions", "not_found");
}

/* ── a webes kulcskezelő oldal ───────────────────────────────────────────── */

function capKeysPage() {
  return `<!DOCTYPE html><html lang="hu"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>API kulcsok — CortexAnime</title>
<style>
:root{--ink:#050506;--surf:#0e0e11;--line:rgba(255,255,255,.08);--tx:#f5f5f7;--mut:#9a9aa8;--faint:#66667a;--vio:#8b5cf6;--mag:#e879f9;--ok:#34d399}
*{box-sizing:border-box;margin:0;padding:0}
body{background:var(--ink);color:var(--tx);font:15px/1.55 Inter,system-ui,-apple-system,sans-serif;min-height:100vh;
background-image:radial-gradient(60% 40% at 10% -5%,rgba(139,92,246,.22),transparent 70%),radial-gradient(50% 35% at 100% 10%,rgba(232,121,249,.12),transparent 70%);
background-attachment:fixed}
.wrap{max-width:820px;margin:0 auto;padding:40px 20px 70px}
.brand{display:flex;align-items:center;gap:10px;margin-bottom:26px;font-size:13px;letter-spacing:.4px}
.dot{width:22px;height:22px;border-radius:50%;border:5px solid transparent;background:linear-gradient(135deg,#22d3ee,#8b5cf6,#e879f9) border-box;-webkit-mask:linear-gradient(#000 0 0) padding-box,linear-gradient(#000 0 0);-webkit-mask-composite:xor;mask-composite:exclude}
h1{font-size:clamp(24px,4vw,34px);letter-spacing:-.8px;margin-bottom:8px;font-weight:800}
p.lead{color:var(--mut);margin-bottom:24px;max-width:600px}
.card{background:rgba(14,14,17,.9);border:1px solid var(--line);border-radius:18px;padding:20px;margin-bottom:14px}
.card h2{font-size:14px;margin-bottom:12px}
.pill{display:inline-flex;align-items:center;gap:6px;font-size:11px;font-weight:800;letter-spacing:.06em;padding:4px 9px;border-radius:7px;border:1px solid rgba(139,92,246,.4);background:rgba(139,92,246,.15);color:#c4b5fd}
.bar{height:7px;border-radius:99px;background:#1a1a22;overflow:hidden;margin:12px 0 8px}
.bar i{display:block;height:100%;background:linear-gradient(90deg,#22d3ee,#8b5cf6,#e879f9);transition:width .3s}
.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace}
.keyrow{display:flex;align-items:center;gap:10px;padding:11px 12px;border:1px solid var(--line);border-radius:12px;margin-bottom:8px;background:var(--surf)}
.keyrow .name{font-weight:600;font-size:13px}
.keyrow .meta{font-size:11px;color:var(--faint)}
.keyrow .grow{flex:1;min-width:0}
button{border:0;border-radius:10px;padding:9px 15px;font:600 13px Inter,system-ui,sans-serif;cursor:pointer}
.primary{background:linear-gradient(90deg,#8b5cf6,#e879f9);color:#fff}
.ghost{background:#191922;color:#c7c7d1;border:1px solid var(--line)}
.danger{background:rgba(251,113,133,.14);color:#fda4af;border:1px solid rgba(251,113,133,.3)}
.reveal{margin-top:12px;padding:14px;border-radius:12px;border:1px dashed rgba(52,211,153,.5);background:rgba(52,211,153,.07)}
.reveal code{display:block;word-break:break-all;font-size:12.5px;color:#a7f3d0;margin:8px 0}
code{font-family:ui-monospace,Menlo,monospace;background:#15151c;padding:2px 6px;border-radius:5px;font-size:12.5px;color:#c4b5fd}
pre{background:#0b0b11;border:1px solid var(--line);border-radius:12px;padding:14px;overflow:auto;font-size:12px;color:#c7c7d1;line-height:1.5}
.hint{font-size:12px;color:var(--faint);margin-top:10px;line-height:1.6}
.tierbox{display:flex;gap:10px;flex-wrap:wrap;margin-top:10px}
.tier{flex:1;min-width:150px;border:1px solid var(--line);border-radius:12px;padding:12px;background:var(--surf)}
.tier b{display:block;font-size:12px;letter-spacing:.05em;color:#c4b5fd}
.tier span{font-size:19px;font-weight:800;font-variant-numeric:tabular-nums}
.tier small{display:block;font-size:11px;color:var(--faint);margin-top:2px}
</style></head><body><div class="wrap">
<div class="brand"><div class="dot"></div><b>CORTEX ANIME</b><span style="color:#66667a">· API</span></div>
<h1>API kulcsok</h1>
<p class="lead">OpenAI-kompatibilis végpont a Cortex Phantom motorral. A kulcs a fiókodhoz tartozik, a napi keret a csomagodtól függ.</p>

<div class="card">
  <h2>Csomagod</h2>
  <div style="display:flex;align-items:center;gap:10px"><span class="pill" id="tier">—</span><span style="font-size:12px;color:#66667a" id="tiernote"></span></div>
  <div class="bar"><i id="bar" style="width:0%"></i></div>
  <div style="font-size:12.5px;color:#9a9aa8" id="usage">Betöltés…</div>
  <div class="tierbox" id="tiers"></div>
  <p class="hint">A keret UTC éjfélkor áll vissza. A mérés a válaszok valódi tokenhasználatán alapul.</p>
</div>

<div class="card">
  <h2>Kulcsaid</h2>
  <div id="keys">Betöltés…</div>
  <div style="display:flex;gap:8px;margin-top:12px;flex-wrap:wrap">
    <input id="kname" placeholder="Kulcs neve (pl. sajat-app)" style="flex:1;min-width:180px;background:#0b0b11;border:1px solid var(--line);border-radius:10px;padding:9px 12px;color:#f5f5f7;font-size:13px">
    <button class="primary" onclick="createKey()">Új kulcs</button>
  </div>
  <div id="reveal"></div>
</div>

<div class="card">
  <h2>Használat</h2>
  <pre id="example">curl https://cortanime.eu/api/v1/chat/completions \\
  -H "Authorization: Bearer cx_..." \\
  -H "Content-Type: application/json" \\
  -d '{"model":"deepseek-flash","messages":[{"role":"user","content":"Szia!"}]}'</pre>
  <p class="hint">Az OpenAI SDK-val is megy: <code>base_url="https://cortanime.eu/api/v1"</code></p>
</div>
<script>
const $=(id)=>document.getElementById(id);
const fmt=(n)=>Number(n||0).toLocaleString('hu-HU');
async function load(){
  const r=await fetch('/api/keys',{credentials:'include'});
  if(r.status===401){location.href='/login?next=/api-keys';return;}
  const d=await r.json();
  $('tier').textContent=d.tier_label.toUpperCase();
  $('tiernote').textContent='napi '+fmt(d.limit)+' token';
  const pct=Math.min(100,(d.used/d.limit)*100);
  $('bar').style.width=pct.toFixed(2)+'%';
  $('usage').textContent=fmt(d.used)+' / '+fmt(d.limit)+' token ma · maradék '+fmt(d.remaining)+' · '+fmt(d.used?d.calls_today:0)+' hívás';
  const tiers={free:{t:'50 millió',p:'Free'},pro:{t:'220 millió',p:'Pro'},max:{t:'2,2 milliárd',p:'Max'}};
  $('tiers').innerHTML=Object.entries(tiers).map(([k,v])=>
    '<div class="tier" style="'+(k===d.tier?'border-color:rgba(139,92,246,.6);background:rgba(139,92,246,.08)':'')+'">'+
    '<b>'+v.p.toUpperCase()+'</b><span>'+v.t+'</span><small>token / nap'+(k===d.tier?' · ez a tiéd':'')+'</small></div>').join('');
  $('keys').innerHTML=d.keys.length?d.keys.map(k=>
    '<div class="keyrow"><div class="grow"><div class="name">'+esc(k.name)+'</div>'+
    '<div class="meta mono">'+esc(k.prefix)+'••••••••  · létrehozva '+new Date(k.created_at*1000).toLocaleDateString('hu-HU')+
    (k.last_used_at?' · utoljára '+new Date(k.last_used_at*1000).toLocaleDateString('hu-HU'):' · még nem használt')+
    (k.revoked_at?' · VISSZAVONVA':'')+'</div></div>'+
    (k.revoked_at?'':'<button class="danger" onclick="revoke(\\''+k.id+'\\')">Visszavonás</button>')+'</div>').join('')
    :'<div style="font-size:13px;color:#66667a">Még nincs kulcsod.</div>';
}
function esc(s){return String(s).replace(/[&<>"]/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c]));}
async function createKey(){
  const r=await fetch('/api/keys/create',{method:'POST',credentials:'include',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({name:$('kname').value||'default'})});
  const d=await r.json();
  if(!r.ok){$('reveal').innerHTML='<div class="reveal" style="border-color:rgba(251,113,133,.5);background:rgba(251,113,133,.08)"><b>Hiba:</b> '+esc(d.error?.message||'ismeretlen')+'</div>';return;}
  $('kname').value='';
  $('reveal').innerHTML='<div class="reveal"><b>Kész — másold ki most!</b><code id="newkey">'+esc(d.key)+'</code>'+
    '<button class="ghost" onclick="navigator.clipboard.writeText(document.getElementById(\\'newkey\\').textContent);this.textContent=\\'Kimásolva\\'">Másolás</button>'+
    '<div class="hint">'+esc(d.warning)+'</div></div>';
  load();
}
async function revoke(id){
  if(!confirm('Biztosan visszavonod? A kulcs azonnal érvénytelenné válik.'))return;
  await fetch('/api/keys/revoke',{method:'POST',credentials:'include',headers:{'Content-Type':'application/json'},body:JSON.stringify({id})});
  load();
}
load();
</script></div></body></html>`;
}

async function capKeysPageHandle(req, requestUrl, env) {
  if (requestUrl.pathname === "/api-keys" || requestUrl.pathname === "/api-keys/") {
    return new Response(capKeysPage(), { status: 200, headers: { "Content-Type": "text/html; charset=utf-8" } });
  }
  return null;
}
