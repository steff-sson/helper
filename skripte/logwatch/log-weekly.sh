#!/bin/bash
# /opt/logwatch/log-weekly.sh

OUTPUT_DIR="/home/$USER/logwatch"
WEEKLY_FILE="$OUTPUT_DIR/weekly-$(date +%Y-%W).txt"
WEEK_START=$(date -d "last monday" +%Y-%m-%d)
TODAY=$(date +%Y-%m-%d)

echo "=== Wöchentlicher Log-Report ===" > "$WEEKLY_FILE"
echo "Zeitraum: $WEEK_START bis $TODAY" >> "$WEEKLY_FILE"
echo "Erstellt: $(date)" >> "$WEEKLY_FILE"
echo "" >> "$WEEKLY_FILE"

# ── Alle Tages-Reports der letzten 7 Tage sammeln ─────────────────
TOTAL_WEEK=0
declare -A ERROR_COUNT  # Container → Gesamtfehler der Woche

echo "── Tages-Übersicht ───────────────────────────────────────────" >> "$WEEKLY_FILE"

for i in {6..0}; do
  DAY=$(date -d "$i days ago" +%Y-%m-%d)
  DAY_FILE="$OUTPUT_DIR/${DAY}.txt"

  if [ -f "$DAY_FILE" ]; then
    # Fehleranzahl aus Tages-Report extrahieren
    COUNT=$(grep "Fehler-Typen gesamt:" "$DAY_FILE" | awk '{print $NF}')
    COUNT=${COUNT:-0}
    TOTAL_WEEK=$((TOTAL_WEEK + COUNT))

    if [ "$COUNT" -gt "0" ]; then
      echo "  ⚠️  $DAY: $COUNT Fehler-Typen" >> "$WEEKLY_FILE"
    else
      echo "  ✅  $DAY: sauber" >> "$WEEKLY_FILE"
    fi
  else
    echo "  ⏭️  $DAY: kein Report" >> "$WEEKLY_FILE"
  fi
done

echo "" >> "$WEEKLY_FILE"
echo "── Wiederkehrende Probleme (≥2x diese Woche) ────────────────" >> "$WEEKLY_FILE"

# Container/Services die mehrfach aufgetaucht sind
grep "^\[" "$OUTPUT_DIR"/$(date -d "6 days ago" +%Y-%m-%d).txt \
         "$OUTPUT_DIR"/$(date -d "5 days ago" +%Y-%m-%d).txt \
         "$OUTPUT_DIR"/$(date -d "4 days ago" +%Y-%m-%d).txt \
         "$OUTPUT_DIR"/$(date -d "3 days ago" +%Y-%m-%d).txt \
         "$OUTPUT_DIR"/$(date -d "2 days ago" +%Y-%m-%d).txt \
         "$OUTPUT_DIR"/$(date -d "1 days ago" +%Y-%m-%d).txt \
         "$OUTPUT_DIR"/$(date +%Y-%m-%d).txt \
         2>/dev/null | \
  sed 's|.*:\[||;s|\].*||' | \
  sort | uniq -c | sort -nr | \
  awk '$1 >= 2 {print "  ⚠️  "$2": "$1"x diese Woche"}' >> "$WEEKLY_FILE"

echo "" >> "$WEEKLY_FILE"
echo "── Neue Fehler (nur heute) ───────────────────────────────────" >> "$WEEKLY_FILE"

# Was heute neu ist (gestern nicht da)
if [ -f "$OUTPUT_DIR/$(date +%Y-%m-%d).txt" ] && \
   [ -f "$OUTPUT_DIR/$(date -d yesterday +%Y-%m-%d).txt" ]; then
  diff \
    <(grep "^\[" "$OUTPUT_DIR/$(date -d yesterday +%Y-%m-%d).txt" 2>/dev/null | sort) \
    <(grep "^\[" "$OUTPUT_DIR/$(date +%Y-%m-%d).txt" 2>/dev/null | sort) | \
    grep "^>" | sed 's/^> /  🆕 /' >> "$WEEKLY_FILE"
fi

echo "" >> "$WEEKLY_FILE"
echo "Fehler-Typen gesamt diese Woche: $TOTAL_WEEK" >> "$WEEKLY_FILE"
echo "══════════════════════════════════════════════════════════════" >> "$WEEKLY_FILE"

cat "$WEEKLY_FILE"
echo "Gespeichert: $WEEKLY_FILE"
