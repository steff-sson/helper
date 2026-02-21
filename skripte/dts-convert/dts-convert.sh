#!/bin/bash
set -o pipefail
set -u

# DTS/TrueHD-to-AC3 Converter (Final - Multi-Track + Google TV + Renaming)
paths=(
  "/volume1/video/Filme"
  "/volume1/video/Serien"
)
log="/home/$USER/dts-convert.log"
dts_check=0

# Abhängigkeiten prüfen
command -v jq      >/dev/null 2>&1 || { echo "jq nicht installiert!";      exit 1; }
command -v ffmpeg  >/dev/null 2>&1 || { echo "ffmpeg nicht installiert!";  exit 1; }
command -v ffprobe >/dev/null 2>&1 || { echo "ffprobe nicht installiert!"; exit 1; }
command -v lsof    >/dev/null 2>&1 || { echo "lsof nicht installiert!";    exit 1; }

# Lockfile gegen Doppelstart
lockfile="/tmp/dts-convert.lock"
[ -f "$lockfile" ] && { echo "Skript läuft bereits – Abbruch."; exit 1; }
touch "$lockfile"
trap "rm -f \"$lockfile\"" EXIT

# Timestamp-Funktion
ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Log rotieren (max. 1000 Zeilen)
if [ -f "$log" ]; then
  tail -n 1000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log" \
    || rm -f "${log}.tmp"
fi

while IFS= read -r -d '' f; do

  # Race Condition: Datei gerade in Verwendung?
  if lsof -- "$f" >/dev/null 2>&1; then
    echo "$(ts): SKIP – $f wird gerade verwendet (Sonarr/Radarr?)" >> "$log"
    continue
  fi

  # Schreibrecht prüfen
  if [ ! -w "$f" ]; then
    echo "$(ts): FEHLER – Keine Schreibrechte auf $f" >> "$log"
    continue
  fi

  # ffprobe einmalig cachen
  probe=$(ffprobe -v error -print_format json \
    -show_entries stream=index,codec_name,codec_type,tags=title,language \
    -- "$f" 2>/dev/null) || {
    echo "$(ts): FEHLER – ffprobe fehlgeschlagen für $f" >> "$log"
    continue
  }

  # DTS/TrueHD-Tracks aus Cache
  tracks=$(echo "$probe" | \
    jq -r '.streams[] | select(.codec_name=="dts" or .codec_name=="truehd") | .index')
  tracks="${tracks:-}"

  if [ -n "$tracks" ]; then
    dts_check=$((dts_check + 1))
    echo "$(ts): Gefunden: $f" >> "$log"
    echo "$(ts): DTS/TrueHD-Tracks: $tracks" >> "$log"

    # Atmos-Hinweis bei TrueHD
    if echo "$probe" | \
      jq -e '.streams[] | select(.codec_name=="truehd")' >/dev/null 2>&1; then
      echo "$(ts):   Hinweis: TrueHD – Atmos-Layer wird zu AC3 5.1 reduziert." >> "$log"
    fi

    # Disk-Space prüfen
    orig_size=$(stat -c%s -- "$f")
    dirpath=$(dirname -- "$f")
    avail=$(df -P "$dirpath" | awk 'NR==2{print $4}')
    needed=$((orig_size / 1024))
    if [ "$avail" -lt "$needed" ]; then
      echo "$(ts): FEHLER – Nicht genug Speicher (benötigt: ${needed}KB, verfügbar: ${avail}KB)" >> "$log"
      continue
    fi

    # FFmpeg-Argumente als Array
    ffmpeg_args=(-i "$f")
    ffmpeg_args+=(-map 0:v -map 0:a -map "0:s?" -map "0:d?")
    ffmpeg_args+=(-c:v copy -c:s copy -c:a copy -c:d copy)
    ffmpeg_args+=(-fix_sub_duration -max_muxing_queue_size 1024)
    audio_index=0

    # Audio-Streams: alles in einem jq-Aufruf
    while IFS=$'\t' read -r codec orig_title lang; do
      orig_title="${orig_title:-Audio}"
      lang="${lang:-und}"

      if [ "$codec" = "dts" ] || [ "$codec" = "truehd" ]; then
        ffmpeg_args+=(-c:a:$audio_index ac3 -b:a:$audio_index 640k)
        ffmpeg_args+=(-metadata:s:a:$audio_index "title=${orig_title} (AC3 Reencode)")
        ffmpeg_args+=(-metadata:s:a:$audio_index "language=$lang")
        echo "$(ts):   a:$audio_index ($codec) -> AC3: '${orig_title} (AC3 Reencode)' [$lang]" >> "$log"
      fi

      audio_index=$((audio_index + 1))
    done < <(echo "$probe" | jq -r \
      '.streams[] | select(.codec_type=="audio") |
      [.codec_name, (.tags.title // ""), (.tags.language // "")] | @tsv')

    # FFmpeg ausführen – </dev/null verhindert stdin-Konflikt mit while-Loop
    ffmpeg_exit=0
    ffmpeg "${ffmpeg_args[@]}" \
      -avoid_negative_ts make_zero \
      "${f%.mkv}-ac3.mkv" -y \
      -loglevel error \
      </dev/null 2>&1 | grep -iv "mjpeg" >> "$log" || ffmpeg_exit=$?

    # Output prüfen
    if [ $ffmpeg_exit -ne 0 ] || [ ! -f "${f%.mkv}-ac3.mkv" ]; then
      echo "$(ts): FEHLER – FFmpeg Exit $ffmpeg_exit für $f" >> "$log"
      rm -f -- "${f%.mkv}-ac3.mkv"
      continue
    fi

    # Korruptionsschutz: Output suspekt klein?
    new_size=$(stat -c%s -- "${f%.mkv}-ac3.mkv")
    if [ "$new_size" -lt $((orig_size / 10)) ]; then
      echo "$(ts): WARNUNG – Output suspekt klein (${new_size}B vs. ${orig_size}B)" >> "$log"
      rm -f -- "${f%.mkv}-ac3.mkv"
      continue
    fi

    # Atomic Replace
    mv -- "${f%.mkv}-ac3.mkv" "$f"
    delta=$((orig_size - new_size))
    pct=$((delta * 100 / orig_size))
    echo "$(ts): Fertig. Ersparnis: ${delta}B (-${pct}%). Audio-Tracks: $audio_index." >> "$log"
  fi

done < <(find -L "${paths[@]}" -name "*.mkv" -print0 2>/dev/null)

[ $dts_check -eq 0 ] && echo "$(ts): Kein DTS/TrueHD gefunden." >> "$log"
echo "$(ts): Scan abgeschlossen. $dts_check Dateien bearbeitet." >> "$log"
