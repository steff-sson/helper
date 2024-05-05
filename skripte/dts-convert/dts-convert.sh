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
# Date Variable für numeric date code
date=$(date '+%Y-%m-%d %H:%M:%S')
# temporary variable based on folder for loop
folder="$path**/*.mkv"

for f in $folder
do
 if ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" | grep dts;
 then
   ((dts_check=dts_check+1))
   echo "$date: $f gefunden und gespeichert, starte AC3 Re-Encode..." >> $log
   ffmpeg -i "$f" -map 0 -map -0:s -c:v copy -c:a ac3 -b:a 640k "${f%.mkv}-ac3.mkv"
   echo "$date: AC3 Re-Encode abgeschlossen. Entferne Original-MKV und ersetze sie durch neue MKV." >> $log
   # rm "$f"
   mv "${f%.mkv}-ac3.mkv" "$f"
   echo "$date: Fertig!" >> $log
 fi
 if ffprobe -v error -select_streams a:1 -show_entries stream=codec_name -of csv=p=0 "$f" | grep dts;
 then
   ((dts_check=dts_check+1))
   echo "$date: $f gefunden und gespeichert, starte AC3 Re-Encode..." >> $log
   ffmpeg -i "$f" -map 0 -map -0:s -c:v copy -c:a ac3 -b:a 640k "${f%.mkv}-ac3.mkv"
   echo "$date: AC3 Re-Encode abgeschlossen. Entferne Original-MKV und ersetze sie durch neue MKV." >> $log
   # rm "$f"
   mv "${f%.mkv}-ac3.mkv" "$f"
   echo "$date: Fertig!" >> $log
 fi
 if ffprobe -v error -select_streams a:0 -show_entries stream=codec_name -of csv=p=0 "$f" | grep eac3;
 then
   ((dts_check=dts_check+1))
   echo "$date: $f gefunden und gespeichert, starte AC3 Re-Encode..." >> $log
   ffmpeg -i "$f" -map 0 -map -0:s -c:v copy -c:a ac3 -b:a 640k "${f%.mkv}-ac3.mkv"
   echo "$date: AC3 Re-Encode abgeschlossen. Entferne Original-MKV und ersetze sie durch neue MKV." >> $log
   # rm "$f"
   mv "${f%.mkv}-ac3.mkv" "$f"
   echo "$date: Fertig!" >> $log
 fi
 if ffprobe -v error -select_streams a:1 -show_entries stream=codec_name -of csv=p=0 "$f" | grep eac3;
 then
   ((dts_check=dts_check+1))
   echo "$date: $f gefunden und gespeichert, starte AC3 Re-Encode..." >> $log
   ffmpeg -i "$f" -map 0 -map -0:s -c:v copy -c:a ac3 -b:a 640k "${f%.mkv}-ac3.mkv"
   echo "$date: AC3 Re-Encode abgeschlossen. Entferne Original-MKV und ersetze sie durch neue MKV." >> $log
   # rm "$f"
   mv "${f%.mkv}-ac3.mkv" "$f"
   echo "$date: Fertig!" >> $log
 fi
done

if [[ $dts_check -eq 0 ]]
then
  echo "$date: Ich habe keine MKV-Datei(en) mit einer DTS-Tonspur in $path gefunden." >> $log
fi
