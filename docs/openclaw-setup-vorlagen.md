# OpenClaw richtig einrichten – kopierbare Befehlsvorlagen

Diese Vorlage ist auf dein Ziel ausgelegt:
1. OpenClaw stabil starten.
2. Brave Search API Key sauber speichern.
3. Steuerung über **WhatsApp**.
4. Steuerung über **Telegram**.
5. **GoClaw erst ganz am Ende** verbinden.

> Ersetze alle Platzhalter wie `<DEIN_WERT>`.

---

## 1) Basis: OpenClaw + Gateway prüfen

```bash
# Version und Status prüfen
openclaw --version
openclaw models status --agent main

# Falls ein User-Service verwendet wird (wie in deinem Screenshot)
systemctl --user status openclaw-gateway.service --no-pager
```

Wenn `openclaw models status` fehlende Auth zeigt, zuerst API Keys setzen (Schritt 2).

---

## 2) Brave Search API Key + weitere Keys korrekt speichern

### 2.1 Zentrale Env-Datei anlegen

```bash
mkdir -p ~/.openclaw
cat > ~/.openclaw/.env <<'ENVEOF'
# LLM / Provider
OPENAI_API_KEY=<DEIN_OPENAI_API_KEY>

# Brave Search (je nach Integration wird einer der beiden Namen genutzt)
BRAVE_API_KEY=<DEIN_BRAVE_API_KEY>
BRAVE_SEARCH_API_KEY=<DEIN_BRAVE_API_KEY>

# Optional: spätere Integrationen
WHATSAPP_VERIFY_TOKEN=<DEIN_WHATSAPP_VERIFY_TOKEN>
WHATSAPP_ACCESS_TOKEN=<DEIN_WHATSAPP_ACCESS_TOKEN>
WHATSAPP_PHONE_NUMBER_ID=<DEINE_PHONE_NUMBER_ID>

TELEGRAM_BOT_TOKEN=<DEIN_TELEGRAM_BOT_TOKEN>
TELEGRAM_ALLOWED_CHAT_IDS=<CHAT_ID_1>,<CHAT_ID_2>

GOCLAW_API_URL=<https://goclaw.example.com/api>
GOCLAW_API_KEY=<DEIN_GOCLAW_API_KEY>
ENVEOF

chmod 600 ~/.openclaw/.env
```

### 2.2 Env-Datei mit openclaw-gateway.service verbinden

```bash
mkdir -p ~/.config/systemd/user/openclaw-gateway.service.d
cat > ~/.config/systemd/user/openclaw-gateway.service.d/env.conf <<'EOF2'
[Service]
EnvironmentFile=%h/.openclaw/.env
EOF2

systemctl --user daemon-reload
systemctl --user restart openclaw-gateway.service
systemctl --user status openclaw-gateway.service --no-pager
```

### 2.3 Schnelltest für Key-Ladung

```bash
# Prüfen ob die Variablen aus der Datei lesbar sind
set -a
source ~/.openclaw/.env
set +a

[ -n "$BRAVE_API_KEY" ] && echo "BRAVE_API_KEY OK" || echo "BRAVE_API_KEY FEHLT"
[ -n "$OPENAI_API_KEY" ] && echo "OPENAI_API_KEY OK" || echo "OPENAI_API_KEY FEHLT"
```

---

## 3) OpenClaw lokal erreichbar machen (Beispiel)

> Wenn dein Gateway lokal auf Port `8080` läuft, testen:

```bash
curl -i http://127.0.0.1:8080/health
```

Wenn du einen Reverse Proxy nutzt, verwende später für WhatsApp/Telegram eine öffentliche HTTPS-URL wie:
`https://<deine-domain>`.

---

## 4) WhatsApp zuerst (Steuerung über WhatsApp)

Diese Befehle sind Vorlagen für Meta WhatsApp Cloud API + Webhook-Flow.

### 4.1 Callback/Verify in Meta konfigurieren

Webhook-URL in Meta Developer Console setzen:

```text
https://<deine-domain>/webhooks/whatsapp
```

Verify Token muss mit `WHATSAPP_VERIFY_TOKEN` übereinstimmen.

### 4.2 Verifikation lokal simulieren

```bash
curl -G "https://<deine-domain>/webhooks/whatsapp" \
  --data-urlencode "hub.mode=subscribe" \
  --data-urlencode "hub.verify_token=<DEIN_WHATSAPP_VERIFY_TOKEN>" \
  --data-urlencode "hub.challenge=123456"
```

### 4.3 Eingehende Nachricht simulieren

```bash
curl -X POST "https://<deine-domain>/webhooks/whatsapp" \
  -H "Content-Type: application/json" \
  -d '{
    "object":"whatsapp_business_account",
    "entry":[{
      "changes":[{
        "value":{
          "messages":[{
            "from":"49123456789",
            "text":{"body":"/status"},
            "type":"text"
          }]
        }
      }]
    }]
  }'
```

### 4.4 Logs prüfen

```bash
journalctl --user -u openclaw-gateway.service -n 200 --no-pager
```

---

## 5) Danach Telegram verbinden

### 5.1 Bot-Webhook auf OpenClaw setzen

```bash
set -a
source ~/.openclaw/.env
set +a

export OPENCLAW_PUBLIC_URL="https://<deine-domain>"

curl -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/setWebhook" \
  -H "Content-Type: application/json" \
  -d "{\"url\":\"${OPENCLAW_PUBLIC_URL}/webhooks/telegram\"}"
```

### 5.2 Telegram-Verbindung prüfen

```bash
curl "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo"
```

### 5.3 Testnachricht an Bot

1. In Telegram `/start` an den Bot senden.
2. Danach z. B. `/status` senden.
3. Falls keine Antwort kommt: Logs prüfen.

```bash
journalctl --user -u openclaw-gateway.service -n 200 --no-pager
```

---

## 6) Ganz zum Schluss: OpenClaw mit GoClaw verbinden

> Erst jetzt, wenn WhatsApp + Telegram sauber laufen.

### 6.1 GoClaw API testen

```bash
set -a
source ~/.openclaw/.env
set +a

curl -i "${GOCLAW_API_URL}/health" \
  -H "Authorization: Bearer ${GOCLAW_API_KEY}"
```

### 6.2 OpenClaw -> GoClaw Testaufruf (Template)

```bash
curl -X POST "http://127.0.0.1:8080/integrations/goclaw/test" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer ${GOCLAW_API_KEY}" \
  -d '{"message":"ping"}'
```

### 6.3 Verbindung bei Fehlern debuggen

```bash
journalctl --user -u openclaw-gateway.service -f
```

---

## 7) Reihenfolge-Checkliste (kurz)

```bash
# 1) Keys gesetzt?
awk -F= '/^(OPENAI_API_KEY|BRAVE_API_KEY|TELEGRAM_BOT_TOKEN|GOCLAW_API_URL)=/{print $1"=***"}' ~/.openclaw/.env

# 2) Service neu laden
systemctl --user daemon-reload && systemctl --user restart openclaw-gateway.service

# 3) Service gesund?
systemctl --user is-active openclaw-gateway.service

# 4) OpenClaw Modellstatus?
openclaw models status --agent main
```

---

## 8) Sicherheit (sehr wichtig)

- `.env` niemals in Git committen.
- Dateirechte auf `600` belassen.
- Webhooks nur über HTTPS veröffentlichen.
- Telegram auf erlaubte Chat-IDs begrenzen.
- Tokens regelmäßig rotieren.

