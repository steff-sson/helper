# Helper
Kleine Hilfsskripte und -programm, die den Alltag erleichtern und Backups einfacher ermöglichen (siehe [btrbk-home-clients](https://github.com/steff-sson/btrbk-home-clients))

## hooks
Pacman Hooks können vor, während oder nach der Installation von Paketen mit Pacman ausgeführt werden.
### pkglist-post-install
Dieser Hook schreibt eine aktuelle Liste installierter Pakte nach /home/pkglist.txt (siehe [archwiki](https://wiki.archlinux.org/title/Pacman#Hooks))
#### Installation
`sudo cp hooks/pkglist-post-install.hook /usr/share/libalpm/hooks/`

## Skripte
### dts-convert
Ein Skript, das in einem bestimmbaren Ordner rekursiv nach *.mkv Dateien sucht, die eine DTS-Tonspur enthalten und diese mit ffmpeg in eine AC3-Tonspur bei hoher Qualität und niedriger Kompression umwandelt. Inklusive Logging.
#### Installation
Das Skript wird über einen Systemd-Timer täglich aufgerufen.

**Klone das Repository**

`git clone https://github.com/steff-sson/helper.git`

**Mache notwendige Änderungen an dts-convert.sh**
(z.B. zu durchsuchenden Pfad und Log-Location)

`nano helper/dts-convert/dts-convert.sh`

**Kopiere den Systemd-Service und -Timer**

```sudo cp helper/dts-convert/dts-convert.service /etc/systemd/system/ && sudo cp helper/dts-convert/dts-convert.timer /etc/systemd/system/```

**Installiere den Systemd-Timer**

`sudo systemctl enable dts-convert.timer`
