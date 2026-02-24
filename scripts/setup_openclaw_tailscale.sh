#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-codex}"   # codex | openai-key

echo "==[1/6] Packages installieren =="
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg jq git

echo "==[2/6] Tailscale installieren (falls fehlt) =="
if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

echo "==[3/6] Tailscale aktivieren (falls noch nicht eingeloggt) =="
# Wenn nicht eingeloggt, zeigt tailscale dir einen Login-Link im Terminal.
if ! tailscale status >/dev/null 2>&1; then
  sudo tailscale up --accept-dns=true
fi

echo "==[4/6] OpenClaw installieren (ohne Wizard) =="
# Offizieller Installer (skip onboarding)
curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard

echo "==[5/6] OpenClaw onboarding (Gateway + Tailscale Serve) =="
if [[ "$MODE" == "codex" ]]; then
  # Codex (ChatGPT OAuth) – kann 1x Browser/OAuth benötigen
  openclaw onboard \
    --flow quickstart \
    --auth-choice openai-codex \
    --gateway-bind loopback \
    --tailscale serve \
    --install-daemon
elif [[ "$MODE" == "openai-key" ]]; then
  : "${OPENAI_API_KEY:?Bitte OPENAI_API_KEY als Environment Variable setzen}"
  openclaw onboard \
    --non-interactive \
    --flow quickstart \
    --openai-api-key "$OPENAI_API_KEY" \
    --gateway-bind loopback \
    --tailscale serve \
    --install-daemon
else
  echo "Usage: $0 {codex|openai-key}"
  exit 2
fi

# Explizit setzen (robust gegen Wizard-Varianten)
openclaw config set gateway.bind '"loopback"' || true
openclaw config set gateway.tailscale.mode '"serve"' || true
openclaw config set gateway.auth.allowTailscale true || true

echo "==[6/6] Gateway prüfen & URL ausgeben =="
openclaw gateway status || true
openclaw health --json || true

DNSNAME="$(tailscale status --json | jq -r '.Self.DNSName // empty' | sed 's/\.$//')"
if [[ -n "$DNSNAME" ]]; then
  echo ""
  echo "✅ iPhone Zugriff (Tailscale an): https://$DNSNAME/"
  echo "   (Wenn Pairing kommt: am Host 'openclaw devices approve --latest')"
else
  echo ""
  echo "⚠️ Konnte MagicDNS Namen nicht lesen. Prüfe: tailscale status"
fi
