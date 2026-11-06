// daily.js — napi adatfolyam a Cortexnek: „napra kész keresés nélkül is".
//
// A napi cron (04:00 UTC) lehúzza a friss híreket (a phantom-search feedjeiről)
// és az AniList mai/mai+holnapi adásrendjét, és eltárolja az R2-ben. A chat
// hír-eszköze ezt ELŐBB elolvassa (instant, hálózat nélkül), és csak akkor
// keres élőben, ha a brief nem elég. A /kb/daily végpont bárkinek adja.

import { topNews } from "./phantom-search.js";
import { readJson, writeJson } from "./phantom-search.js";

const DAILY_KEY = "cortexai/phantom/daily.v1.json";

const ANILIST_QUERY = `
query ($start: Int, $end: Int) {
  Page(page: 1, perPage: 30) {
    airingSchedules(airingAt_greater: $start, airingAt_lesser: $end, sort: TIME) {
      airingAt
      episode
      media { title { romaji english } format episodes }
    }
  }
}`;

async function airingToday() {
  const now = Math.floor(Date.now() / 1000);
  try {
    const r = await fetch("https://graphql.anilist.co", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": "CortexDailyFeed/1.0 (+cortanime.eu)",
        "Accept": "application/json",
      },
      body: JSON.stringify({
        query: ANILIST_QUERY,
        variables: { start: now - 6 * 3600, end: now + 30 * 3600 },
      }),
    });
    if (!r.ok) { airingToday.lastError = `http ${r.status}`; return []; }
    const d = await r.json();
    if (d?.errors?.length) { airingToday.lastError = String(d.errors[0].message || "").slice(0, 80); }
    const rows = d?.data?.Page?.airingSchedules || [];
    return rows.map((s) => ({
      title: s.media?.title?.english || s.media?.title?.romaji || "",
      episode: s.episode,
      when: new Date(s.airingAt * 1000).toISOString(),
    })).filter((x) => x.title);
  } catch {
    return [];
  }
}

/** A mai brief betöltése az R2-ből (üres objektum, ha még nincs). */
export async function dailyBrief(env) {
  return readJson(env, DAILY_KEY, null);
}

/** A saját platform friss epizódjai (CortexAnime epfeed) — mindig elérhető. */
async function freshEpisodes(origin) {
  try {
    const r = await fetch(`${origin || "https://cortanime.eu"}/api/app/epfeed`, {
      headers: { "User-Agent": "CortexDailyFeed/1.0" },
    });
    if (!r.ok) return [];
    const d = await r.json();
    return (d.items || []).slice(0, 8).map((x) => ({
      title: x.title || "", ep: x.ep, aid: x.aid,
      when: new Date(x.ts || Date.now()).toISOString(),
    }));
  } catch { return []; }
}

/** A napi frissítés: hírek + saját friss epizódok + (ha lehet) anime-adásrend → R2. */
export async function dailyFeedJob(env) {
  const headlines = await topNews(8).catch(() => []);
  const airing = await airingToday();
  const fresh = await freshEpisodes(env.ORIGIN);
  const brief = {
    date: new Date().toISOString().slice(0, 10),
    generated: new Date().toISOString(),
    airingError: airingToday.lastError || null,
    headlines: headlines.map((h) => ({
      title: h.title || "",
      source: h.source || "",
      link: h.link || "",
      date: h.date || "",
    })),
    airing,
    freshEpisodes: fresh,
    counts: { headlines: headlines.length, airing: airing.length, fresh: fresh.length },
  };
  if (env.CORTEX_R2) {
    await writeJson(env, DAILY_KEY, brief);
    try {
      await writeJson(env, `cortexai/phantom/daily/${brief.date}.json`, brief);
    } catch { /* a napi másolat opcionális */ }
  }
  return brief;
}

/** Keresés a briefben — a kereső-rendszer „mai" rétege. */
export async function dailySearch(env, foldQuery) {
  const brief = await dailyBrief(env).catch(() => null);
  if (!brief) return [];
  const q = String(foldQuery || "");
  const hits = [];
  for (const h of brief.headlines || []) {
    const t = `${h.title} ${h.source}`.toLowerCase();
    if (q && t.includes(q)) hits.push({ kind: "news", ...h });
  }
  for (const a of [...(brief.airing || []), ...(brief.freshEpisodes || [])]) {
    const t = `${a.title} ${a.episode ?? a.ep ?? ""}`.toLowerCase();
    if (q && t.includes(q)) hits.push({ kind: a.ep !== undefined ? "fresh-episode" : "airing", ...a });
  }
  return hits.slice(0, 6);
}
