#!/bin/bash
# /opt/logwatch/log-analyse.sh
# Tägliche Log-Analyse: Docker-Container + journalctl
# Version 5 – mit Noise-Filtern, Farben, systemd-Timer-ready

DATE=$(date +%Y-%m-%d)
OUTPUT_DIR="/home/$USER/logwatch"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/${DATE}.txt"
DOCKER_SINCE=$(date -d "yesterday" --iso-8601=seconds)
SINCE="yesterday"

# ── Container-Gruppen ──────────────────────────────────────────────
CRITICAL="homeassistant vaultwarden authelia nextcloud wireguard crowdsec mariadb swag"
MEDIA="jellyfin sonarr radarr bazarr prowlarr nzbget recyclarr mediathekarr"
PAPERLESS="paperless paperless-db paperless-broker docker-tika-1 docker-gotenberg-1"
AI_VOICE="whisper openwakeword piper musicassistant"
INFRA="mosquitto zigbee2mqtt duplicati diun dockhand"
APPS="mealie karakeep-web karakeep-chrome karakeep-meilisearch \
      calibre-web heimdall nodered raneto yourls yourls_db \
      bentopdf languagetool esphome torproxy"

ALL_CONTAINERS="$CRITICAL $MEDIA $PAPERLESS $AI_VOICE $INFRA $APPS"

# ── Noise-Filter ───────────────────────────────────────────────────
GLOBAL_NOISE="kex_exchange|preauth|blob data|Connection reset|\
Health check|recaptcha site key|Logging to.*mariadb-error"

PAPERLESS_NOISE="$GLOBAL_NOISE|\
filename format|double curly|No passphrase|sensitive fields|\
WARNINGS:|passphrase|plaintext|\
Access denied for user 'root'.*using password: NO|\
init-db-wait|init-start|init-folders|\
<bf>|<search>|Module.*loaded|RedisBloom|gc: ON"

MEDIA_NOISE="$GLOBAL_NOISE|\
Item not found|not found in database|Language not found|\
No results|Skipping|already exists|is not monitored|\
Using.*again after"

AI_NOISE="$GLOBAL_NOISE|\
Loaded model|inference|sample rate|chunk|silence|wake word|\
will be retried"

INFRA_NOISE="$GLOBAL_NOISE|\
reconnect|keepalive|retain|subscribe|heartbeat|\
certificate|renewal|TLS handshake|\
MQTT failed to connect|ECONNREFUSED|\
Jobs completed"

APPS_NOISE="$GLOBAL_NOISE|\
404|favicon|robots.txt|static|OPTIONS|HEAD request|\
rate limit|timeout waiting|\
dark_error|light_error|\
dbus|system_bus_socket|\
xdg-desktop|bash completions|\
log_error ="

# ── Farben (nur im Terminal, nicht in Datei) ───────────────────────
if [ -t 1 ]; then
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  NC='\033[0m'
else
  RED='' GREEN='' YELLOW='' NC=''
fi

# ── Output-Dateien initialisieren ──────────────────────────────────
> "$OUTPUT_FILE"

TOTAL_ERRORS=0
SUMMARY=""
SKIPPED=""

# ── Hilfsfunktion: Container prüfen ───────────────────────────────
check_container() {
  local CONTAINER=$1
  local NOISE_FILTER=$2
  local LABEL=$3

  if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
    SKIPPED="$SKIPPED $CONTAINER"
    return
  fi

  RESULT=$(docker logs \
    --since "$DOCKER_SINCE" \
    --timestamps \
    "$CONTAINER" 2>&1 | \
    grep -iE "error|fatal|critical|exception|failed|crash|panic|refused|denied|killed|oom" | \
    grep -vE "$NOISE_FILTER" | \
    sort | uniq -c | sort -nr | head -5)

  COUNT=$(echo "$RESULT" | grep -c '\S' 2>/dev/null || echo 0)

  if [ -n "$RESULT" ] && [ "$COUNT" -gt "0" ]; then
    echo -e "${RED}⚠️  [$LABEL] $CONTAINER ($COUNT Fehler-Typen):${NC}"
    echo "$RESULT" | sed 's/^/    /'
    # In Datei schreiben (ohne Farben)
    echo "[$LABEL] $CONTAINER:" >> "$OUTPUT_FILE"
    echo "$RESULT" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    TOTAL_ERRORS=$((TOTAL_ERRORS + COUNT))
    SUMMARY="$SUMMARY\n⚠️  [$LABEL] $CONTAINER: $COUNT Fehler-Typen"
  else
    echo -e "${GREEN}✅  [$LABEL] $CONTAINER${NC}"
  fi
}

# ── Header ─────────────────────────────────────────────────────────
HEADER="=== Log-Analyse $DATE (seit $DOCKER_SINCE) ==="
echo -e "${YELLOW}$HEADER${NC}"
echo "$HEADER" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# ── Checks nach Gruppe ─────────────────────────────────────────────
echo "── KRITISCH ──────────────────────────────────────────────────"
echo "── KRITISCH ──────────────────────────────────────────────────" >> "$OUTPUT_FILE"
for C in $CRITICAL; do check_container "$C" "$GLOBAL_NOISE" "KRITISCH"; done

echo ""
echo "── MEDIA ─────────────────────────────────────────────────────"
echo "" >> "$OUTPUT_FILE"
echo "── MEDIA ─────────────────────────────────────────────────────" >> "$OUTPUT_FILE"
for C in $MEDIA; do check_container "$C" "$MEDIA_NOISE" "MEDIA"; done

echo ""
echo "── PAPERLESS ─────────────────────────────────────────────────"
echo "" >> "$OUTPUT_FILE"
echo "── PAPERLESS ─────────────────────────────────────────────────" >> "$OUTPUT_FILE"
for C in $PAPERLESS; do check_container "$C" "$PAPERLESS_NOISE" "PAPERLESS"; done

echo ""
echo "── AI / VOICE ────────────────────────────────────────────────"
echo "" >> "$OUTPUT_FILE"
echo "── AI / VOICE ────────────────────────────────────────────────" >> "$OUTPUT_FILE"
for C in $AI_VOICE; do check_container "$C" "$AI_NOISE" "AI"; done

echo ""
echo "── INFRASTRUKTUR ─────────────────────────────────────────────"
echo "" >> "$OUTPUT_FILE"
echo "── INFRASTRUKTUR ─────────────────────────────────────────────" >> "$OUTPUT_FILE"
for C in $INFRA; do check_container "$C" "$INFRA_NOISE" "INFRA"; done

echo ""
echo "── APPS ──────────────────────────────────────────────────────"
echo "" >> "$OUTPUT_FILE"
echo "── APPS ──────────────────────────────────────────────────────" >> "$OUTPUT_FILE"
for C in $APPS; do check_container "$C" "$APPS_NOISE" "APPS"; done

# ── journalctl (System) ────────────────────────────────────────────
echo ""
echo "── SYSTEM (journalctl) ───────────────────────────────────────"
echo "" >> "$OUTPUT_FILE"
echo "── SYSTEM (journalctl) ───────────────────────────────────────" >> "$OUTPUT_FILE"

JOURNAL_RESULT=$(journalctl --since "$SINCE" \
  -p err..emerg \
  -o short-precise \
  --no-hostname | \
  grep -vE "kex_exchange|preauth|Connection reset by peer|invalid user" | \
  sort | uniq -c | sort -nr | head -10)

JOURNAL_COUNT=$(echo "$JOURNAL_RESULT" | grep -c '\S' 2>/dev/null || echo 0)

if [ -n "$JOURNAL_RESULT" ] && [ "$JOURNAL_COUNT" -gt "0" ]; then
  echo -e "${RED}⚠️  [SYSTEM] journalctl ($JOURNAL_COUNT Fehler-Typen):${NC}"
  echo "$JOURNAL_RESULT" | sed 's/^/    /'
  echo "[SYSTEM] journalctl:" >> "$OUTPUT_FILE"
  echo "$JOURNAL_RESULT" >> "$OUTPUT_FILE"
  echo "" >> "$OUTPUT_FILE"
  TOTAL_ERRORS=$((TOTAL_ERRORS + JOURNAL_COUNT))
  SUMMARY="$SUMMARY\n⚠️  [SYSTEM] journalctl: $JOURNAL_COUNT Fehler-Typen"
else
  echo -e "${GREEN}✅  [SYSTEM] journalctl – sauber${NC}"
  echo "[SYSTEM] journalctl: sauber" >> "$OUTPUT_FILE"
fi

# ── Zusammenfassung ────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════════════"
echo -e "${YELLOW}=== ZUSAMMENFASSUNG $DATE ===${NC}"

{
  echo ""
  echo "══════════════════════════════════════════════════════════════"
  echo "=== ZUSAMMENFASSUNG $DATE ==="
  echo "Container geprüft: $(echo $ALL_CONTAINERS | wc -w)"
  if [ -n "$SKIPPED" ]; then
    echo "Nicht aktiv: $SKIPPED"
  fi
  echo "Fehler-Typen gesamt: $TOTAL_ERRORS"
  if [ -n "$SUMMARY" ]; then
    echo -e "$SUMMARY"
  else
    echo "✅ Alles sauber!"
  fi
  echo "══════════════════════════════════════════════════════════════"
} | tee -a "$OUTPUT_FILE"

echo ""
echo "Gespeichert: $OUTPUT_FILE ($(wc -l < "$OUTPUT_FILE") Zeilen)"
