#!/usr/bin/env bash
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"
MODE="quickstart"
OPENAI_API_KEY_VALUE="${OPENAI_API_KEY:-}"

log() {
  echo "[INFO] $*"
}

warn() {
  echo "[WARN] $*" >&2
}

err() {
  echo "[ERROR] $*" >&2
}

usage() {
  cat <<USAGE
Usage: $SCRIPT_NAME [OPTIONS]

Installiert OpenClaw als privates Gateway über Tailscale (Ubuntu 22/24 + systemd).

Optionen:
  -m, --mode MODE        Onboarding-Modus: quickstart (Modus A) oder api-key (Modus B)
  -k, --api-key KEY      OpenAI API Key für Modus B (alternativ ENV OPENAI_API_KEY)
  -h, --help             Zeigt diese Hilfe

Beispiele:
  $SCRIPT_NAME --mode quickstart
  OPENAI_API_KEY=sk-... $SCRIPT_NAME --mode api-key
  $SCRIPT_NAME --mode api-key --api-key sk-...
USAGE
}

on_error() {
  local exit_code=$?
  err "Fehler in Zeile ${BASH_LINENO[0]} (Exit-Code: ${exit_code})."
  exit "$exit_code"
}
trap on_error ERR

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "Benötigter Befehl fehlt: $cmd"
    exit 1
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -m|--mode)
        MODE="${2:-}"
        shift 2
        ;;
      -k|--api-key)
        OPENAI_API_KEY_VALUE="${2:-}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "Unbekannte Option: $1"
        usage
        exit 1
        ;;
    esac
  done

  case "$MODE" in
    quickstart|api-key) ;;
    *)
      err "Ungültiger Modus: $MODE (erlaubt: quickstart|api-key)"
      exit 1
      ;;
  esac

  if [[ "$MODE" == "api-key" && -z "$OPENAI_API_KEY_VALUE" ]]; then
    err "Modus api-key benötigt --api-key oder OPENAI_API_KEY."
    exit 1
  fi
}

install_dependencies() {
  log "Installiere Abhängigkeiten (curl, jq, git, ca-certificates)..."
  sudo apt-get update -y
  sudo apt-get install -y curl jq git ca-certificates
}

install_tailscale_if_missing() {
  if command -v tailscale >/dev/null 2>&1; then
    log "Tailscale ist bereits installiert."
    return
  fi

  log "Installiere Tailscale..."
  curl -fsSL https://tailscale.com/install.sh | sh
}

ensure_tailscale_active() {
  log "Prüfe Tailscale-Status..."
  if tailscale status --json >/tmp/tailscale-status.json 2>/dev/null; then
    if jq -e '.BackendState == "Running"' /tmp/tailscale-status.json >/dev/null 2>&1; then
      log "Tailscale ist aktiv."
      rm -f /tmp/tailscale-status.json
      return
    fi
  fi

  warn "Tailscale ist nicht aktiv. Starte: sudo tailscale up --accept-dns=true"
  sudo tailscale up --accept-dns=true

  tailscale status --json >/tmp/tailscale-status.json
  jq -e '.BackendState == "Running"' /tmp/tailscale-status.json >/dev/null
  rm -f /tmp/tailscale-status.json
  log "Tailscale läuft jetzt."
}

install_openclaw() {
  if command -v openclaw >/dev/null 2>&1; then
    log "OpenClaw ist bereits installiert."
    return
  fi

  log "Installiere OpenClaw (--no-onboard)..."
  curl -fsSL https://openclaw.ai/install.sh | bash -s -- --no-onboard
}

run_onboarding() {
  if [[ "$MODE" == "quickstart" ]]; then
    log "Starte OpenClaw Onboarding (Modus A: quickstart)..."
    openclaw onboard \
      --auth-choice openai-codex \
      --flow quickstart \
      --gateway-bind loopback \
      --tailscale serve \
      --install-daemon
  else
    log "Starte OpenClaw Onboarding (Modus B: API-Key non-interactive)..."
    openclaw onboard \
      --non-interactive \
      --openai-api-key "$OPENAI_API_KEY_VALUE" \
      --flow quickstart \
      --gateway-bind loopback \
      --tailscale serve \
      --install-daemon
  fi
}

set_openclaw_config() {
  log "Setze OpenClaw Gateway-Konfiguration (privat via Tailscale Serve)..."
  openclaw config set gateway.bind "loopback"
  openclaw config set gateway.tailscale.mode "serve"
  openclaw config set gateway.auth.allowTailscale "true"
}

print_summary() {
  local dns_name=""
  dns_name="$(tailscale status --json | jq -r '.Self.DNSName // empty')"

  echo
  echo "=============================================="
  echo "✅ OpenClaw Gateway wurde eingerichtet (privat)."
  echo "🔒 Keine Internet-Ports geöffnet. Kein Tailscale Funnel aktiviert."
  echo ""
  if [[ -n "$dns_name" ]]; then
    echo "MagicDNS: $dns_name"
  else
    warn "MagicDNS konnte nicht ermittelt werden."
  fi
  echo ""
  echo "iPhone Schritte:"
  echo "1) Installiere & öffne Tailscale auf dem iPhone und melde dich im selben Tailnet an."
  echo "2) Prüfe, dass das iPhone im Tailnet online ist."
  echo "3) Öffne OpenClaw App/Client auf dem iPhone und starte Pairing mit dem Gateway."
  echo "4) Falls Pairing hängt/aussteht, auf dem Gateway ausführen:"
  echo "   openclaw devices approve --latest"
  echo "=============================================="
}

main() {
  parse_args "$@"
  require_cmd sudo
  install_dependencies
  require_cmd curl
  require_cmd jq
  require_cmd git

  install_tailscale_if_missing
  ensure_tailscale_active

  install_openclaw
  require_cmd openclaw

  run_onboarding
  set_openclaw_config
  print_summary
}

main "$@"
