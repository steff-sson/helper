#!/bin/bash

set -o pipefail
set -u

# DTS/TrueHD/Opus-to-AC3 Converter (Hybrid: ffmpeg Audio-Encode + mkvmerge Mux)

paths=(
  "/volume1/video/Filme"
  "/volume1/video/Serien"
)

log="/home/$USER/dts-convert.log"
dts_check=0
skip_count=0
current_file=""
tmp_mka=""
tmp_mkv=""

# Abhängigkeiten prüfen
command -v jq        >/dev/null 2>&1 || { echo "jq nicht installiert!";       exit 1; }
command -v ffmpeg    >/dev/null 2>&1 || { echo "ffmpeg nicht installiert!";   exit 1; }
command -v ffprobe   >/dev/null 2>&1 || { echo "ffprobe nicht installiert!";  exit 1; }
command -v mkvmerge  >/dev/null 2>&1 || { echo "mkvmerge nicht installiert! (pacman -S mkvtoolnix-cli)"; exit 1; }
command -v lsof      >/dev/null 2>&1 || { echo "lsof nicht installiert!";     exit 1; }
command -v setfattr  >/dev/null 2>&1 || { echo "attr nicht installiert! (pacman -S attr)"; exit 1; }
command -v getfattr  >/dev/null 2>&1 || { echo "attr nicht installiert! (pacman -S attr)"; exit 1; }

# Lockfile gegen Doppelstart
lockfile="/tmp/dts-convert.lock"
[ -f "$lockfile" ] && { echo "Skript läuft bereits – Abbruch."; exit 1; }
touch "$lockfile"

# Trap: Lockfile + Tempfiles aufräumen
trap '
  rm -f "$lockfile"
  [ -n "$tmp_mka" ] && rm -f "$tmp_mka"
  [ -n "$tmp_mkv" ] && rm -f "$tmp_mkv"
' EXIT INT TERM

ts() { date '+%Y-%m-%d %H:%M:%S'; }

# Language-Lookup-Tabelle (ISO 639-2 → Anzeigename)
declare -A lang_map=(
  [eng]="English"    [deu]="Deutsch"     [ger]="Deutsch"
  [fre]="Français"   [fra]="Français"    [spa]="Español"
  [ita]="Italiano"   [jpn]="Japanese"    [kor]="Korean"
  [chi]="Chinese"    [zho]="Chinese"     [por]="Português"
  [rus]="Russian"    [hin]="Hindi"       [ara]="Arabic"
  [dut]="Nederlands" [nld]="Nederlands"  [pol]="Polski"
  [tur]="Turkish"    [swe]="Svenska"     [nor]="Norsk"
  [dan]="Dansk"      [fin]="Suomi"       [cze]="Čeština"
  [ces]="Čeština"    [hun]="Magyar"      [tha]="Thai"
)

# Log rotieren (max. 2000 Zeilen)
if [ -f "$log" ]; then
  tail -n 2000 "$log" > "${log}.tmp" && mv "${log}.tmp" "$log" \
  || rm -f "${log}.tmp"
fi

# Pfade prüfen
for p in "${paths[@]}"; do
  [ -d "$p" ] || echo "$(ts): WARNUNG – Pfad nicht gefunden: $p" >> "$log"
done

while IFS= read -r -d '' f; do
  current_file="$f"
  tmp_mka=""
  tmp_mkv=""

  # xattr-Cache prüfen: bereits geprüft und Mtime unverändert?
  stored_mtime=$(getfattr -n user.dts_check --only-values "$f" 2>/dev/null || echo "")
  current_mtime=$(stat -c%Y "$f")
  if [ "$stored_mtime" = "$current_mtime" ]; then
    skip_count=$((skip_count + 1))
    continue
  fi

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

  # ffprobe einmalig ausführen
  probe=$(ffprobe -v error -print_format json \
    -show_streams \
    -- "$f" 2>/dev/null) || {
    echo "$(ts): FEHLER – ffprobe fehlgeschlagen für $f" >> "$log"
    continue
  }

  # DTS/TrueHD/Opus-Tracks erkennen
  tracks=$(echo "$probe" | \
    jq -r '.streams[] | select(.codec_name=="dts" or .codec_name=="truehd" or .codec_name=="opus") | .index')
  tracks="${tracks:-}"

  if [ -n "$tracks" ]; then
    dts_check=$((dts_check + 1))
    echo "$(ts): Gefunden: $f" >> "$log"
    echo "$(ts): DTS/TrueHD/Opus-Tracks: $tracks" >> "$log"

    # Atmos-Hinweis bei TrueHD
    if echo "$probe" | \
      jq -e '.streams[] | select(.codec_name=="truehd")' >/dev/null 2>&1; then
      echo "$(ts): Hinweis: TrueHD – Atmos-Layer wird zu AC3 5.1 reduziert." >> "$log"
    fi

    # Disk-Space prüfen (2x Originalgröße als Reserve für beide Tempfiles)
    orig_size=$(stat -c%s -- "$f")
    dirpath=$(dirname -- "$f")
    avail=$(df -P "$dirpath" | awk 'NR==2{print $4}')
    needed=$(( (orig_size * 2) / 1024 ))
    if [ "$avail" -lt "$needed" ]; then
      echo "$(ts): FEHLER – Nicht genug Speicher (benötigt: ${needed}KB, verfügbar: ${avail}KB)" >> "$log"
      continue
    fi

    # Tempfile-Pfade
    tmp_mka="${f%.mkv}-audio.mka"
    tmp_mkv="${f%.mkv}-merged.mkv"

    # ── SCHRITT 1: ffmpeg – nur Audio-Encode ──────────────────────────────────
    ffmpeg_args=(-analyzeduration 200M -probesize 200M -i "$f")
    ffmpeg_args+=(-vn -sn)          # kein Video, keine Untertitel
    ffmpeg_args+=(-map 0:a)         # alle Audiospuren
    ffmpeg_args+=(-c:a copy)        # Standard: kopieren
    ffmpeg_args+=(-max_muxing_queue_size 2048 -max_error_rate 1.0)
    ffmpeg_args+=(-map_chapters -1)
    audio_index=0

    while IFS=$'\t' read -r codec orig_title lang; do
      # Titel-Fallback: orig_title → lang_map[$lang] → $lang → "Audio"
      _lang_key="${lang:-}"
      echo "$(ts): DEBUG lang='${lang}' key='${_lang_key}'" >> "$log"
      display_lang=""
      [ -n "$_lang_key" ] && display_lang="${lang_map[$_lang_key]:-}"
      if [ -z "$orig_title" ]; then
        orig_title="${display_lang:-${_lang_key:-Audio}}"
      fi
      lang="${lang:-und}"

      if [ "$codec" = "dts" ] || [ "$codec" = "truehd" ] || [ "$codec" = "opus" ]; then
        ffmpeg_args+=(-c:a:$audio_index ac3 -b:a:$audio_index 640k)
        ffmpeg_args+=(-metadata:s:a:$audio_index "title=${orig_title} (AC3 Reencode)")
        if [ "$lang" != "und" ]; then
          ffmpeg_args+=(-metadata:s:a:$audio_index "language=$lang")
        fi
        echo "$(ts): a:$audio_index ($codec) -> AC3 640k: '${orig_title} (AC3 Reencode)' [$lang]" >> "$log"
      else
        ffmpeg_args+=(-metadata:s:a:$audio_index "title=${orig_title}")
        if [ "$lang" != "und" ]; then
          ffmpeg_args+=(-metadata:s:a:$audio_index "language=$lang")
        fi
      fi

      audio_index=$((audio_index + 1))
    done < <(echo "$probe" | jq -r \
      '.streams[] | select(.codec_type=="audio") |
      [.codec_name, (.tags.title // ""), (.tags.language // "")] | @tsv')

    ffmpeg "${ffmpeg_args[@]}" "$tmp_mka" 2>&1 \
      | grep -iv "mjpeg" > /tmp/dts-ffmpeg.tmp
    ffmpeg_exit=${PIPESTATUS[0]}

    if [ "$ffmpeg_exit" -ne 0 ] || grep -qi "error\|corrupt\|invalid" /tmp/dts-ffmpeg.tmp; then
      echo "$(ts): WARNUNG – ffmpeg meldete Fehler/Warnungen für $f" >> "$log"
      cat /tmp/dts-ffmpeg.tmp >> "$log"
    fi
    rm -f /tmp/dts-ffmpeg.tmp

    if [ "$ffmpeg_exit" -ne 0 ] || [ ! -f "$tmp_mka" ]; then
      echo "$(ts): FEHLER – ffmpeg Audio-Encode fehlgeschlagen (Exit $ffmpeg_exit) für $f" >> "$log"
      rm -f "$tmp_mka"; tmp_mka=""
      continue
    fi

    # ── SCHRITT 2: mkvmerge – Video + Untertitel aus Original, Audio aus .mka ─
    mkvmerge -o "$tmp_mkv" \
      --no-audio "$f" \
      "$tmp_mka" 2>&1 > /tmp/dts-mkvmerge.tmp
    mkvmerge_exit=$?

    if [ "$mkvmerge_exit" -ne 0 ]; then
      echo "$(ts): FEHLER – mkvmerge fehlgeschlagen (Exit $mkvmerge_exit) für $f" >> "$log"
      cat /tmp/dts-mkvmerge.tmp >> "$log"
      rm -f /tmp/dts-mkvmerge.tmp "$tmp_mka" "$tmp_mkv"
      tmp_mka=""; tmp_mkv=""
      continue
    fi
    rm -f /tmp/dts-mkvmerge.tmp

    # Korruptionsschutz: Output suspekt klein?
    new_size=$(stat -c%s -- "$tmp_mkv")
    if [ "$new_size" -lt $((orig_size / 10)) ]; then
      echo "$(ts): WARNUNG – Output suspekt klein (${new_size}B vs. ${orig_size}B)" >> "$log"
      rm -f "$tmp_mka" "$tmp_mkv"
      tmp_mka=""; tmp_mkv=""
      continue
    fi

    # ── SCHRITT 3: Atomic Replace ─────────────────────────────────────────────
    rm -f "$tmp_mka"; tmp_mka=""
    mv -- "$tmp_mkv" "$f"
    tmp_mkv=""
    current_file=""  # Erfolgreich – Trap soll nicht löschen

    # xattr nach erfolgreichem Replace neu setzen
    new_mtime=$(stat -c%Y "$f")
    setfattr -n user.dts_check -v "$new_mtime" "$f"

    delta=$((orig_size - new_size))
    pct=$((delta * 100 / orig_size))
    echo "$(ts): Fertig. Ersparnis: ${delta}B (-${pct}%). Audio-Tracks: $audio_index." >> "$log"

  else
    # Keine problematischen Tracks – als geprüft markieren
    setfattr -n user.dts_check -v "$current_mtime" "$f"
  fi

done < <(find -L "${paths[@]}" -name "*.mkv" -print0 2>/dev/null)

current_file=""

[ $dts_check -eq 0 ] && echo "$(ts): Kein DTS/TrueHD/Opus gefunden." >> "$log"
echo "$(ts): Scan abgeschlossen. $dts_check Dateien konvertiert, $skip_count übersprungen (xattr-Cache)." >> "$log"
