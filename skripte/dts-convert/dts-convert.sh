#!/bin/bash

# DTS/TrueHD-to-AC3 Converter (Final - Multi-Track + Google TV + Renaming)
path=/volume1/video/
log=/home/$USER/dts-convert.log
dts_check=0
date=$(date '+%Y-%m-%d %H:%M:%S')

while IFS= read -r -d '' f; do

  # Alle DTS/TrueHD-Tracks finden (Index relativ zu allen Streams)
  tracks=$(ffprobe -v error -print_format json \
    -show_entries stream=index,codec_name,tags=title,language "$f" \
    | jq -r '.streams[] | select(.codec_name=="dts" or .codec_name=="truehd") | .index')

  if [ -n "$tracks" ] && [ "$tracks" != "null" ]; then
    ((dts_check++))
    echo "$date: Gefunden: $f" >> $log
    echo "$date: DTS/TrueHD-Tracks (Stream-Index): $tracks" >> $log

    # Basis: alles copy
    codec_cmd="-c:v copy -c:s copy -c:a copy -c:d copy"
    meta_cmd=""
    
    # Audio-Index-Zähler (relativ nur zu Audio-Streams)
    audio_index=0

    # Alle Audio-Streams durchlaufen
    while IFS= read -r stream; do
      stream_index=$(echo "$stream" | jq -r '.index')
      codec=$(echo "$stream" | jq -r '.codec_name')
      orig_title=$(echo "$stream" | jq -r '.tags.title // "Audio"')
      lang=$(echo "$stream" | jq -r '.tags.language // "und"')

      if [ "$codec" = "dts" ] || [ "$codec" = "truehd" ]; then
        # Re-encode + Rename
        codec_cmd="$codec_cmd -c:a:$audio_index ac3 -b:a:$audio_index 640k"
        meta_cmd="$meta_cmd -metadata:s:a:$audio_index title=\"${orig_title} (AC3 Reencode)\" -metadata:s:a:$audio_index language=$lang"
        echo "$date:   Track a:$audio_index ($codec) -> AC3: '${orig_title} (AC3 Reencode)' [$lang]" >> $log
      fi

      ((audio_index++))
    done < <(ffprobe -v error -print_format json \
      -show_entries stream=index,codec_name,tags=title,language "$f" \
      | jq -c '.streams[] | select(.codec_type=="audio" or (.codec_name | test("dts|truehd|ac3|eac3|aac|opus")))')

    # FFmpeg ausführen
    eval ffmpeg -i \"$f\" \
      -map 0:v -map '"0:a"' -map '"0:s?"' -map '"0:d?"' \
      $codec_cmd \
      $meta_cmd \
      -avoid_negative_ts make_zero \
      \"${f%.mkv}-ac3.mkv\" -y \
      -loglevel error 2>&1 | grep -iv "mjpeg" >> $log

    # Prüfen ob Output existiert
    if [ ! -f "${f%.mkv}-ac3.mkv" ]; then
      echo "$date: FEHLER – FFmpeg fehlgeschlagen für $f" >> $log
      continue
    fi

    # Size Check + Atomic Replace
    orig_size=$(stat -c%s "$f")
    new_size=$(stat -c%s "${f%.mkv}-ac3.mkv")
    mv "${f%.mkv}-ac3.mkv" "$f"
    delta=$((orig_size - new_size))
    pct=$((delta * 100 / orig_size))
    echo "$date: Fertig. Ersparnis: ${delta}B (-${pct}%). Tracks: $audio_index." >> $log

  fi

done < <(find "$path" -name "*.mkv" -print0)

[ $dts_check -eq 0 ] && echo "$date: Kein DTS/TrueHD gefunden." >> $log
echo "$date: Scan abgeschlossen. $dts_check Dateien bearbeitet." >> $log
