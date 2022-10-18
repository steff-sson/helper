#!/bin/bash
# DTS conversion script

# define folder to search for *.mkv files (will be search recursively!)
path=/volume1/video/

# define location of logfile
log=/home/$USER/dts-convert.log

## needed variables for loop and recursive scan
# globstar
shopt -s globstar
# temp variable for DTS-check
dts_check=0
# temporary variable based on folder for loop
folder="$path**/*.mkv"

for f in $folder
do
 if ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" | grep dts; then
   ((dts_check=dts_check+1))
   echo $(date -u) "$f gefunden und gespeichert, starte AC3 Re-Encode..." >> $log
   # ffmpeg -i "$f" -map 0 -c copy -c:a ac3 -b:a 640k -metadata:s:a:0 title="AC3 (reencode)" "${f%.mkv}-ac3.mkv"
   # echo $(date -u) "AC3 Re-Encode abgeschlossen. Entferne Original-MKV und ersetze sie durch neue MKV." >> $log
   # rm "$f"
   # mv "${f%.mkv}-ac3.mkv" "$f"
   # echo $(date -u) "Fertig!" >> $log
fi
done

if [[ $dts_check -eq 0 ]]
then
  echo $(date -u) "Ich habe keine MKV-Datei(en) mit einer DTS-Tonspur in $path gefunden." >> $log
fi
