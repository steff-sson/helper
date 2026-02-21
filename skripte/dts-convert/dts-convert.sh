#!/bin/bash

# DTS-to-AC3 Converter (Optimiert für Multi-Track + Google TV)
path=/volume1/video/
log=/home/$USER/dts-convert.log
# shopt -s globstar
dts_check=0
date=$(date '+%Y-%m-%d %H:%M:%S')

while IFS= read -r -d '' f; do
  # JSON-Analyse aller Audio-Tracks
  tracks=$(ffprobe -v error -print_format json -show_entries stream=index,codec_name,tags=title,language "$f" | jq -r '.streams[] | select(.codec_name=="dts") | .index')
  
  if [ "$tracks" != "null" ] && [ -n "$tracks" ]; then
    ((dts_check++))
    echo "$date: DTS-Tracks in $f ($tracks), starte Conversion..." >> $log
    
    # Dynamisches Mapping bauen
    map_cmd="-map 0:v -map 0:s? -map 0:d?"  # Video, Subs, Data
    audio_cmd=""
    dts_count=0
    
    while IFS= read -r dts_idx; do
      if [ -n "$dts_idx" ]; then
        orig_title=$(ffprobe -v error -select_streams a:$dts_idx -show_entries stream_tags=title -of csv=p=0 "$f" 2>/dev/null || echo "DTS")
        lang=$(ffprobe -v error -select_streams a:$dts_idx -show_entries stream_tags=language -of csv=p=0 "$f" 2>/dev/null || echo "und")
        map_cmd="$map_cmd -map 0:a:$dts_idx"
        audio_cmd="$audio_cmd -c:a:$dts_count ac3 -b:a 640k -metadata:s:a.$dts_count title=\"$orig_title (AC3 Reencode)\" -metadata:s:a.$dts_count language=$lang"
        ((dts_count++))
      fi
    done <<< "$tracks"
    
    # Non-DTS Audio copy
    map_cmd="$map_cmd -map 0:a -c:a copy"
    
    # FFmpeg Aufruf
    ffmpeg -i "$f" $map_cmd $audio_cmd \
      -avoid_negative_ts make_zero \
      "${f%.mkv}-ac3.mkv" -y -loglevel error
    
    # Atomic Replace + Size Check
    orig_size=$(stat -c%s "$f")
    new_size=$(stat -c%s "${f%.mkv}-ac3.mkv")
    mv "${f%.mkv}-ac3.mkv" "$f"
    delta=$((new_size - orig_size))
    echo "$date: $f fertig. Größe: ${delta}B ($((delta * 100 / orig_size))%). DTS: $dts_count Tracks." >> $log
  fi
done < <(find "$path" -name "*.mkv" -print0)

[ $dts_check -eq 0 ] && echo "$date: Kein DTS gefunden." >> $log
echo "$date: Scan abgeschlossen. $dts_check Dateien bearbeitet." >> $log
