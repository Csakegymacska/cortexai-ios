#!/usr/bin/env python3
"""Deploy the Cortex AI worker straight through the Cloudflare API (no wrangler/Node 22 needed).

  python3 tools/deploy_cortexai.py            # upload + secrets + route + verify
  python3 tools/deploy_cortexai.py --dry      # print what would happen
"""
import json, sys, urllib.request, urllib.error, uuid, os

ROOT = "/home/user"
WORKER = "cortexai-api"
ZONE_NAME = "cortanime.eu"
ROUTES = ["cortanime.eu/api/cortexai/*", "cortanime.eu/grid*", "cortanime.eu/ai", "cortanime.eu/ai/*"]
SRC = f"{ROOT}/{WORKER}/src/index.js"

env = {}
for line in open(f"{ROOT}/secrets/.env"):
    line = line.strip()
    if "=" in line and not line.startswith("#"):
        k, v = line.split("=", 1)
        env[k.strip()] = v.strip().strip('"').strip("'")

ACC = env["CF_ACCOUNT_ID"]
ZONE = env["CF_ZONE_CORTEXAI"] if env.get("CF_ZONE_CORTEXAI") else None
H = {"X-Auth-Email": env["CLOUDFLARE_EMAIL"], "X-Auth-Key": env["CLOUDFLARE_API_KEY"]}


def api(method, path, body=None, ctype="application/json", raw=None):
    url = f"https://api.cloudflare.com/client/v4{path}"
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method)
    req.add_header("Content-Type", ctype)
    for k, v in H.items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        return {"success": False, "status": e.code, "errors": json.loads(e.read() or b"{}")}


def zone_id():
    r = api("GET", f"/zones?name={ZONE_NAME}")
    return r["result"][0]["id"]


def deploy():
    src = open(SRC, "rb").read()
    # Inject the volunteer page so /grid works without a second bucket or worker.
    grid_path = "/home/user/cortexai-grid/grid.html"
    if os.path.exists(grid_path):
        grid = open(grid_path, encoding="utf-8").read()
        src = src.replace(b"__GRID_HTML__", json.dumps(grid).encode()[1:-1])
    meta = {
        "main_module": "index.js",
        "compatibility_date": "2026-01-01",
        "bindings": [
            {"type": "secret_text", "name": "GLM_API_KEY", "text": env["GLM_API_KEY"]},
            {"type": "secret_text", "name": "GEMINI_API_KEY", "text": env["GEMINI_API_KEY"]},
            {"type": "secret_text", "name": "DIAG_TOKEN", "text": env["CLOUDFLARE_API_KEY"][-12:]},
            # The training loop authenticates with its own token, not the CF one.
            {"type": "secret_text", "name": "CORE_TOKEN", "text": env["CORE_TOKEN"]},
            {"type": "r2_bucket", "name": "CORTEX_R2", "bucket_name": "cortex-app"},
            # Workers AI — a FLUX.1-schnell képmotor (Cortex Void Canvas).
            {"type": "ai", "name": "AI"},
        ] + [
            # Optional engines: wired only when the secret exists (self-host, Groq, Cerebras,
            # OpenRouter, Together). Add the key to secrets/.env and redeploy to switch one on.
            {"type": "secret_text", "name": name, "text": env[name]}
            for name in ("XKIRO_API_KEY", "XKIRO_BASE_URL", "XKIRO_MODEL", "XKIRO_MODEL_2",
                         "XKIRO_MODEL_3", "XKIRO_MODEL_4", "XKIRO_MODEL_5", "XKIRO_IMAGE_MODEL",
                         "SELFHOST_BASE_URL", "SELFHOST_API_KEY", "SELFHOST_MODEL",
                         "GROQ_API_KEY", "CEREBRAS_API_KEY", "OPENROUTER_API_KEY",
                         "TOGETHER_API_KEY", "GLM_MODEL", "GEMINI_MODEL",
                         # Hugging Face (DeepSeek V4.1 Flash) és a helyi Poe-8B-HERETIC végpont.
                         "HF_TOKEN", "HF_MODEL", "HERETIC_BASE_URL", "HERETIC_API_KEY", "HERETIC_MODEL",
                         # DeepSeek közvetlen API — a Phantom első motorja (deepseek-flash = V4.1-Flash)
                         "DEEPSEEK_API_KEY", "DEEPSEEK_MODEL",
                         "SANDBOX_URL", "SANDBOX_TOKEN")
            if env.get(name)
        ] + [
        ],
        # Dynamic Workers: a modell által írt kód saját izolált Workerben fut, szerver nélkül.
        "worker_loaders": [{"binding": "LOADER"}],
        "probe_worker_loader_binding": [{"type": "worker_loader", "name": "LOADER2"}],
        "observability": {"enabled": True},
        "triggers": {"crons": ["0 4 * * *"]},
    }
    boundary = "----cortex" + uuid.uuid4().hex
    parts = []
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"metadata\"\r\nContent-Type: application/json\r\n\r\n".encode() + json.dumps(meta).encode() + b"\r\n")
    parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"index.js\"; filename=\"index.js\"\r\nContent-Type: application/javascript+module\r\n\r\n".encode() + src + b"\r\n")
    # Every other module in src/ (brains, helpers) ships in the same upload; the worker
    # imports them by relative path, so they must be present as named parts.
    src_dir = os.path.dirname(SRC)
    for name in sorted(os.listdir(src_dir)):
        if not name.endswith(".js") or name == "index.js":
            continue
        data = open(os.path.join(src_dir, name), "rb").read()
        # A sandbox telepítője a repóbeli fájlokból épül be, hogy ne legyen két példány.
        if name == "sandboxinstall.js":
            py_src = open(f"{ROOT}/phantom-sandbox/sandbox_service.py", encoding="utf-8").read()
            sh_src = open(f"{ROOT}/phantom-sandbox/deploy/setup.sh", encoding="utf-8").read()
            data = data.replace(b"\"__SANDBOX_PY__\"", json.dumps(py_src).encode())
            data = data.replace(b"\"__SANDBOX_SETUP__\"", json.dumps(sh_src).encode())
        parts.append(f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; filename=\"{name}\"\r\nContent-Type: application/javascript+module\r\n\r\n".encode() + data + b"\r\n")
        print("module:", name, len(data), "B")
    parts.append(f"--{boundary}--\r\n".encode())
    body = b"".join(parts)
    r = api("PUT", f"/accounts/{ACC}/workers/scripts/{WORKER}", raw=body,
            ctype=f"multipart/form-data; boundary={boundary}")
    print("upload:", r.get("success"), r.get("errors") or "")
    if not r.get("success"):
        return False

    sub = api("POST", f"/accounts/{ACC}/workers/scripts/{WORKER}/subdomain", {"enabled": True})
    print("workers.dev:", sub.get("success"))

    zid = zone_id()
    existing = {row["pattern"] for row in api("GET", f"/zones/{zid}/workers/routes").get("result", [])}
    for route in ROUTES:
        if route in existing:
            print("route exists:", route)
            continue
        rt = api("POST", f"/zones/{zid}/workers/routes", {"pattern": route, "script": WORKER})
        print("route add:", route, rt.get("success"), rt.get("errors") or "")
    return True


if __name__ == "__main__":
    if "--dry" in sys.argv:
        print("would upload", SRC, len(open(SRC, "rb").read()), "bytes; routes", ROUTES)
        sys.exit(0)
    ok = deploy()
    sys.exit(0 if ok else 1)
