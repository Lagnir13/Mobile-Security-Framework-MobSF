# OpenClaw Setup – Kopierbare Befehlsvorlagen

> Diese Vorlagen sind bewusst **anpassbar** gehalten. Ersetze alle Platzhalter wie `<DEIN_WERT>`.

## 1) Voraussetzungen (einmalig)

```bash
# Projektordner anlegen
mkdir -p ~/openclaw && cd ~/openclaw

# Beispiel: Docker + Compose prüfen
docker --version
docker compose version
```

---

## 2) Brave Search API Key sicher speichern

### Option A: Als Umgebungsvariable in deiner Shell

```bash
# Nur für aktuelle Session
export BRAVE_SEARCH_API_KEY="<DEIN_BRAVE_API_KEY>"

# Test (zeigt nur, ob gesetzt)
[ -n "$BRAVE_SEARCH_API_KEY" ] && echo "BRAVE Key ist gesetzt" || echo "BRAVE Key fehlt"
```

### Option B: Persistente Speicherung in `.env` (empfohlen)

```bash
cd ~/openclaw
cat > .env <<'ENVEOF'
BRAVE_SEARCH_API_KEY=<DEIN_BRAVE_API_KEY>
ENVEOF

# Rechte härten
chmod 600 .env
```

> `.env` nie in Git einchecken.

---

## 3) OpenClaw Basis-Konfiguration

```bash
cd ~/openclaw
cat > docker-compose.yml <<'YAMLEOF'
services:
  openclaw:
    image: ghcr.io/<org>/openclaw:latest
    container_name: openclaw
    env_file:
      - .env
    environment:
      - OPENCLAW_HOST=0.0.0.0
      - OPENCLAW_PORT=8080
      - BRAVE_SEARCH_API_KEY=${BRAVE_SEARCH_API_KEY}
    ports:
      - "8080:8080"
    restart: unless-stopped
YAMLEOF

# Start
docker compose up -d

# Logs prüfen
docker compose logs -f --tail=200 openclaw
```

---

## 4) WhatsApp-Anbindung (Webhook-Template)

> OpenClaw muss einen eingehenden Webhook akzeptieren, z. B. `/webhooks/whatsapp`.

### `.env` ergänzen

```bash
cd ~/openclaw
cat >> .env <<'ENVEOF'
WHATSAPP_PROVIDER=meta
WHATSAPP_VERIFY_TOKEN=<WHATSAPP_VERIFY_TOKEN>
WHATSAPP_ACCESS_TOKEN=<WHATSAPP_ACCESS_TOKEN>
WHATSAPP_PHONE_NUMBER_ID=<WHATSAPP_PHONE_NUMBER_ID>
OPENCLAW_WHATSAPP_WEBHOOK_PATH=/webhooks/whatsapp
ENVEOF
```

### Beispiel: Erreichbarkeit testen

```bash
curl -i "http://localhost:8080/health"
```

### Beispiel: Test-Webhook lokal simulieren

```bash
curl -X POST "http://localhost:8080/webhooks/whatsapp" \
  -H "Content-Type: application/json" \
  -d '{"from":"49123456789","text":"status"}'
```

---

## 5) Telegram-Anbindung (Bot)

### Telegram Bot Token setzen

```bash
cd ~/openclaw
cat >> .env <<'ENVEOF'
TELEGRAM_BOT_TOKEN=<DEIN_TELEGRAM_BOT_TOKEN>
TELEGRAM_ALLOWED_CHAT_IDS=<CHAT_ID_1>,<CHAT_ID_2>
OPENCLAW_TELEGRAM_ENABLED=true
ENVEOF
```

### Bot-Webhook setzen (wenn OpenClaw Webhook-Modus nutzt)

```bash
# Beispiel-URL (öffentlich erreichbar, HTTPS)
export OPENCLAW_PUBLIC_URL="https://<deine-domain>"
export TELEGRAM_BOT_TOKEN="<DEIN_TELEGRAM_BOT_TOKEN>"

curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"${OPENCLAW_PUBLIC_URL}/webhooks/telegram\"}"
```

### Telegram-Verbindung prüfen

```bash
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

---

## 6) OpenClaw neu laden

```bash
cd ~/openclaw
docker compose down
docker compose up -d
docker compose logs -f --tail=200 openclaw
```

---

## 7) GoClaw-Verbindung (als letzter Schritt)

> Erst verbinden, wenn OpenClaw + WhatsApp + Telegram stabil laufen.

### `.env` um GoClaw ergänzen

```bash
cd ~/openclaw
cat >> .env <<'ENVEOF'
GOCLAW_ENABLED=true
GOCLAW_API_URL=https://<goclaw-host>/api
GOCLAW_API_KEY=<DEIN_GOCLAW_API_KEY>
GOCLAW_TIMEOUT_SECONDS=30
ENVEOF
```

### Verbindungstest gegen GoClaw

```bash
curl -i "https://<goclaw-host>/api/health" \
  -H "Authorization: Bearer <DEIN_GOCLAW_API_KEY>"
```

### Testaufruf von OpenClaw zu GoClaw (Beispiel)

```bash
curl -X POST "http://localhost:8080/integrations/goclaw/test" \
  -H "Content-Type: application/json" \
  -d '{"ping":true}'
```

---

## 8) Schnelle Checkliste

```bash
# 1) Läuft OpenClaw?
curl -s http://localhost:8080/health

# 2) Ist Brave Key vorhanden?
docker compose exec openclaw /bin/sh -lc 'test -n "$BRAVE_SEARCH_API_KEY" && echo OK || echo MISSING'

# 3) Webhooks aktiv?
docker compose logs --tail=200 openclaw | grep -Ei "webhook|telegram|whatsapp|goclaw"
```

---

## 9) Sicherheit (wichtig)

- API Keys nie in Chat, Screenshots oder Git-Commits teilen.
- `.env` nur lokal speichern und Rechte auf `600` setzen.
- Für öffentliche Webhooks immer HTTPS + Reverse Proxy + IP-Filter/Signaturprüfung verwenden.
- Telegram auf erlaubte Chat-IDs begrenzen.

