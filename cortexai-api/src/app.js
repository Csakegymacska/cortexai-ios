// ── Cortex AI app distribution ───────────────────────────────────────────────
// The app itself stays private. What ships from here is the finished build and a
// page that tells people how to get it onto their phone: either through AltStore /
// SideStore with their own Apple ID (signing happens on their device), or by
// downloading the unsigned IPA and signing it on a signer of their choosing.
//
// R2 layout:
//   cortexai/app/CortexAI-<version>.ipa
//   cortexai/app/icon.png
//   cortexai/app/source.json   (optional override)

const APP = {
  name: "Cortex AI",
  bundleId: "eu.cortex.ai",
  version: "7.3",
  build: "27",
  versionDate: "2026-11-06T05:39:00Z",
  releaseDate: "2026-11-06",
  minOS: "26.5",
  sizeBytes: 3487747,
  developer: "OmegaTech x CortexAnime",
  ipaKey: "cortexai/app/CortexAI-7.3-b27-ios26-unsigned.ipa",
  iconKey: "cortexai/app/icon.png",
  signer: "https://applejr.net/#signer",
  site: "https://cortanime.eu",
  tint: "#0B0B0F",
};

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,HEAD,OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
};

const json = (body, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...CORS },
  });

function base(request) {
  const url = new URL(request.url);
  return `${url.protocol}//${url.host}/api/cortexai/app`;
}

const DESCRIPTION =
  "Cortex AI is the CortexAnime player for iPhone: the full Hungarian catalogue, " +
  "subtitles, downloads and a built-in assistant — Cortex Phantom — who answers about " +
  "series, episodes, genres and scores without sending your questions anywhere. " +
  "The assistant speaks Hungarian; the interface speaks English.";

// Everybody wants to know whether it grows. Nobody creates an account, so the only
// honest signal we have is the download itself: one counter in R2, no cookies, no IPs.
const STATS_KEY = "cortexai/app/stats.json";

async function bump(env, field) {
  if (!env.CORTEX_R2) return;
  let stats = {};
  try {
    const object = await env.CORTEX_R2.get(STATS_KEY);
    if (object) stats = await object.json();
  } catch { stats = {}; }
  stats[field] = (Number(stats[field]) || 0) + 1;
  stats.updated = new Date().toISOString();
  await env.CORTEX_R2.put(STATS_KEY, JSON.stringify(stats), {
    httpMetadata: { contentType: "application/json" },
  });
}

async function appStats(env) {
  let stats = {};
  if (env.CORTEX_R2) {
    try {
      const object = await env.CORTEX_R2.get(STATS_KEY);
      if (object) stats = await object.json();
    } catch { stats = {}; }
  }
  return json({
    ok: true,
    installs: Number(stats.installs) || 0,
    sourceViews: Number(stats.sourceViews) || 0,
    updated: stats.updated || null,
    version: APP.version,
  });
}

// GET /app/ipa — the build itself. Range is supported so a phone can resume.
async function appIpa(request, env, ctx) {
  if (!env.CORTEX_R2) return json({ ok: false, error: "storage_unavailable" }, 503);
  const countIt = bump(env, "installs");          // a letöltés a legközelebbi jel a telepítésre
  if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(countIt);
  // Range-fejléc → R2 tartomány-objektum (a nyers szöveg hibát okozna)
  const rangeHeader = request.headers.get("Range");
  let rangeOpt;
  if (rangeHeader) {
    const m = /^bytes=(\d*)-(\d*)$/.exec(rangeHeader.trim());
    if (m) {
      if (m[1] !== "") {
        const offset = Number(m[1]);
        rangeOpt = m[2] !== "" ? { offset, length: Number(m[2]) - offset + 1 } : { offset };
      } else if (m[2] !== "") {
        rangeOpt = { suffix: Number(m[2]) };
      }
    }
  }
  const object = await env.CORTEX_R2.get(APP.ipaKey, rangeOpt);
  if (!object) {
    return json(
      { ok: false, error: "build_not_uploaded", expected: APP.ipaKey, version: APP.version },
      404,
    );
  }
  const headers = {
    ...CORS,
    "Content-Type": "application/octet-stream",
    "Content-Disposition": `attachment; filename="CortexAI-${APP.version}.ipa"`,
    "Accept-Ranges": "bytes",
    "Cache-Control": "public, max-age=3600",
    "X-App-Version": `${APP.version} (${APP.build})`,
    "X-Min-OS": APP.minOS,
  };
  if (rangeHeader && object.range) {
    const start = object.range.offset || 0;
    const length = object.range.length ?? object.size - start;
    headers["Content-Range"] = `bytes ${start}-${start + length - 1}/${object.size}`;
    headers["Content-Length"] = String(length);
    return new Response(object.body, { status: 206, headers });
  }
  headers["Content-Length"] = String(object.size ?? APP.sizeBytes);
  return new Response(object.body, { status: 200, headers });
}

// GET /app/icon.png — the icon AltStore shows.
async function appIcon(env) {
  if (!env.CORTEX_R2) return json({ ok: false, error: "storage_unavailable" }, 503);
  const object = await env.CORTEX_R2.get(APP.iconKey);
  if (!object) return json({ ok: false, error: "icon_missing" }, 404);
  return new Response(object.body, {
    headers: {
      ...CORS,
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=86400",
    },
  });
}

// GET /app/source.json — an AltStore / SideStore source. Add it once, and the app
// installs and updates from inside AltStore, signed with the user's own Apple ID.
function appSource(request, env, ctx) {
  if (env && env.CORTEX_R2) {
    const countIt = bump(env, "sourceViews");
    if (ctx && typeof ctx.waitUntil === "function") ctx.waitUntil(countIt);
  }
  const root = base(request);
  const icon = `${root}/icon.png`;
  const version = {
    version: APP.version,
    buildVersion: APP.build,
    date: APP.versionDate,
    downloadURL: `${root}/ipa`,
    size: APP.sizeBytes,
    minOSVersion: APP.minOS,
    localizedDescription:
      "Cortex AI 1.4: the Hungarian catalogue with subtitles and downloads, and the " +
      "Cortex Phantom assistant answering from our own brain — instantly, offline for " +
      "catalogue, maths, dates and identity.",
  };
  return json({
    name: "CortexAnime",
    identifier: "eu.cortanime.source",
    subtitle: "Cortex AI for iOS",
    description:
      "Official builds of Cortex AI (OmegaTech x CortexAnime). Unsigned — AltStore or " +
      "SideStore signs it with your own Apple ID while installing. The application " +
      "source is not public.",
    iconURL: icon,
    headerURL: icon,
    website: APP.site,
    tintColor: APP.tint,
    featuredApps: [APP.bundleId],
    apps: [
      {
        name: APP.name,
        bundleIdentifier: APP.bundleId,
        developerName: APP.developer,
        subtitle: "Hungarian anime catalogue with the Cortex Phantom assistant",
        localizedDescription: DESCRIPTION,
        iconURL: icon,
        tintColor: APP.tint,
        category: "entertainment",
        screenshots: [],
        versions: [version],
        version: APP.version,
        versionDate: APP.versionDate,
        versionDescription: version.localizedDescription,
        downloadURL: version.downloadURL,
        size: APP.sizeBytes,
        minOSVersion: APP.minOS,
        appPermissions: { entitlements: [], privacy: {} },
      },
    ],
    news: [],
  });
}

// GET /app/install — the page people land on.
function appInstall(request) {
  const root = base(request);
  const source = `${root}/source.json`;
  const ipa = `${root}/ipa`;
  const icon = `${root}/icon.png`;
  const sizeMb = (APP.sizeBytes / 1e6).toFixed(1);

  const html = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>${APP.name} ${APP.version} — install on iPhone</title>
<meta name="description" content="Install ${APP.name} on iOS. Signed with your own Apple ID by AltStore or SideStore, or download the IPA and sign it yourself.">
<style>
  :root{color-scheme:dark}
  *{box-sizing:border-box}
  body{margin:0;background:#07070a;color:#f2f2f5;font:16px/1.55 -apple-system,BlinkMacSystemFont,"Segoe UI",Inter,sans-serif}
  .wrap{max-width:760px;margin:0 auto;padding:40px 20px 72px}
  header{display:flex;gap:16px;align-items:center;margin-bottom:28px}
  header img{width:72px;height:72px;border-radius:18px;background:#111;box-shadow:0 8px 30px #000}
  h1{font-size:26px;margin:0 0 4px;letter-spacing:-.3px}
  .sub{color:#9a9aa6;font-size:14px;margin:0}
  .card{border:1px solid #1d1d24;background:linear-gradient(180deg,#111117,#0c0c11);border-radius:16px;padding:20px;margin:16px 0}
  .card h2{font-size:17px;margin:0 0 6px}
  .card p{color:#a9a9b4;margin:6px 0}
  ol{margin:10px 0 0;padding-left:20px;color:#c9c9d2}
  li{margin:6px 0}
  code,.mono{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px}
  .url{display:block;background:#000;border:1px solid #24242e;border-radius:10px;padding:12px;margin:10px 0;word-break:break-all;color:#eaeaf0}
  a.btn{display:inline-block;margin:12px 8px 0 0;padding:12px 18px;border-radius:11px;text-decoration:none;font-weight:600;font-size:15px}
  .primary{background:#fff;color:#000}
  .ghost{border:1px solid #2a2a35;color:#e8e8ee}
  .note{border-left:3px solid #3a3a48;padding-left:12px;color:#9a9aa6;font-size:14px;margin:14px 0}
  .meta{display:flex;flex-wrap:wrap;gap:8px;margin:18px 0 0}
  .pill{border:1px solid #24242e;border-radius:999px;padding:5px 11px;font-size:13px;color:#a9a9b4}
  footer{margin-top:34px;color:#6f6f7d;font-size:13px}
  h2.sec{font-size:13px;letter-spacing:.12em;text-transform:uppercase;color:#7c7c8a;margin:34px 0 8px}
</style></head>
<body><div class="wrap">
  <header>
    <img src="${icon}" alt="">
    <div>
      <h1>${APP.name} ${APP.version}</h1>
      <p class="sub">${APP.developer} · iPhone · iOS ${APP.minOS}+ · ${sizeMb} MB</p>
    </div>
  </header>

  <div class="meta">
    <span class="pill">Unsigned build</span>
    <span class="pill">No account required</span>
    <span class="pill">Released ${APP.releaseDate}</span>
    <span class="pill">Build ${APP.build}</span>
  </div>

  <div class="card">
    <h2>No install needed — try it in the browser</h2>
    <p>The same brain, the same Hungarian answers, no Apple ID and no signing.</p>
    <a class="btn primary" href="/api/cortexai/web">Open Cortex AI in the browser</a>
    <p class="note">It keeps your conversations on the device, and it works on any phone, tablet or desktop.</p>
  </div>

  <h2 class="sec">Install</h2>

  <div class="card">
    <h2>Way one — AltStore or SideStore (recommended)</h2>
    <p>Your phone signs the app itself with your own Apple ID. Nothing is uploaded anywhere.</p>
    <ol>
      <li>Install <strong>AltStore</strong> or <strong>SideStore</strong> from their own sites.</li>
      <li>In the app, open <em>Sources</em> and add this address:</li>
    </ol>
    <span class="url mono">${source}</span>
    <ol start="3">
      <li>Open the CortexAnime source, tap <em>${APP.name}</em>, then <em>Install</em>.</li>
      <li>Free Apple IDs sign for 7 days — AltStore refreshes it automatically while both are on the same Wi-Fi.</li>
    </ol>
  </div>

  <div class="card">
    <h2>Way two — download the IPA and sign it yourself</h2>
    <p>If you already use a signer, take the file and sign it there.</p>
    <a class="btn primary" href="${ipa}" download>Download CortexAI-${APP.version}.ipa</a>
    <a class="btn ghost" href="${APP.signer}" target="_blank" rel="noopener">Sign it at applejr.net</a>
    <p class="note">Upload the file to the signer, sign with your certificate, then install the signed result. Nothing of ours is involved in that step.</p>
  </div>

  <h2 class="sec">Android and Windows</h2>
  <div class="card">
    <p>The same Cortex AI, on three platforms — one account everywhere.</p>
    <a class="btn primary" href="/api/cortexai/app/apk" download>Download CortexAI-${APP.version}-android.apk</a>
    <a class="btn primary" href="/api/cortexai/app/win" download>Download CortexAI-${APP.version}-windows.exe</a>
    <p class="note">Android: open the APK on your phone and allow install from this source. Windows: run the exe — it opens the full Cortex AI app.</p>
  </div>

  <h2 class="sec">What is inside</h2>
  <div class="card">
    <p>${DESCRIPTION}</p>
    <p class="note">The application's source code is private and is not published, here or anywhere else. This page and the build are all that is distributed.</p>
  </div>

  <h2 class="sec">Requirements</h2>
  <div class="card">
    <p>iOS ${APP.minOS} or newer. A computer is not required for way one; way two needs a signer that supports iOS ${APP.minOS}.</p>
    <p>If the install fails, remove a previous copy of the app first — two builds with the same bundle identifier cannot coexist.</p>
  </div>

  <footer>${APP.developer} · <a href="${APP.site}" style="color:#8a8a98">cortanime.eu</a> · build served from our own storage</footer>
</div></body></html>`;

  return new Response(html, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "public, max-age=300",
      ...CORS,
    },
  });
}

// GET /app/apk, /app/win — a másik két platform buildje (R2-ből).
async function appBinary(env, key, filename) {
  if (!env.CORTEX_R2) return json({ ok: false, error: "storage_unavailable" }, 503);
  const object = await env.CORTEX_R2.get(key);
  if (!object) return json({ ok: false, error: "build_not_uploaded", expected: key }, 404);
  return new Response(object.body, {
    headers: {
      ...CORS,
      "Content-Type": "application/octet-stream",
      "Content-Disposition": `attachment; filename="${filename}"`,
      "Cache-Control": "public, max-age=3600",
    },
  });
}

export { APP, appIpa, appIcon, appSource, appInstall, appStats, appBinary };
