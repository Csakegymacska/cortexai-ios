# Cortex Phantom Core — saját kiszolgáló (llama.cpp, OpenAI-kompatibilis)

Egy CPU-s VPS-en is fut (Hetzner CPX21+), a modell 4 bites, ~1 GB.

## Indítás

```bash
# 1. modell helye (a Kaggle-ből csomagolt GGUF)
mkdir -p models
# scp cortex-phantom-core-Q4_K_M.gguf models/

# 2. indítás
docker compose up -d

# 3. ellenőrzés
curl http://localhost:8080/v1/models -H "Authorization: Bearer phantom"
```

## Bekötés a Cortexhez

A `secrets/.env`-be (utána `python3 tools/deploy_cortexai.py`):

```
SELFHOST_BASE_URL=http://<VPS-IP>:8080/v1
SELFHOST_API_KEY=phantom
SELFHOST_MODEL=cortex-phantom-core
```

A worker `selfhost` motorja ettől kezdve a lánc elején próbálja — ha nem érhető
el, automatikusan a következő motorra (DeepSeek, Gemini…) vált.
