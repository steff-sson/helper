# Helper
Kleine Hilfsskripte und -programme, die den Alltag (eines Media-Servers) erleichtern und Backups einfacher ermöglichen (siehe [btrbk-home-clients](https://github.com/steff-sson/btrbk-home-clients))

## hooks
Pacman Hooks können vor, während oder nach der Installation von Paketen mit Pacman ausgeführt werden.
### pkglist-post-install
Dieser Hook schreibt eine aktuelle Liste installierter Pakte nach /home/pkglist.txt (siehe [archwiki](https://wiki.archlinux.org/title/Pacman#Hooks))
#### Installation
`sudo cp hooks/pkglist-post-install.hook /usr/share/libalpm/hooks/`

## configs
### btrfsmaintenance
Konfigurationsdatei für [https://github.com/kdave/btrfsmaintenance](btrfsmaintenance). Hier werden **balance**, **scrub** und **trim** automatisch durchgeführt und in `/etc/default/btrfsmaintenance` konfiguriert.

**Klone das Repository**

`git clone https://github.com/steff-sson/helper.git && cd helper`

**Mache notwendige Änderungen an btrfsmaintenance**
(z.B. zu durchsuchenden Pfad und Log-Location)

`nano configs/btrfsmaintenance`

**Installiere das AUR-Paket btrfsmaintenance**

`yay btrfsmaintenance`

**Kopiere die Konfigurationsdatei**

`sudo cp configs/btrfsmaintenance /etc/default/`

**Aktiviere die Systemd-Timer**

`sudo systemctl enable btrfs-balance.timer && sudo systemctl enable btrfs-scrub.timer && sudo systemctl enable btrfs-trim.timer &&`

## skripte
### dts-convert
Ein Skript, das in einem bestimmbaren Ordner rekursiv nach *.mkv Dateien sucht, die eine DTS-Tonspur enthalten und diese mit ffmpeg in eine AC3-Tonspur bei hoher Qualität und niedriger Kompression umwandelt. Inklusive Logging.
#### Installation
Das Skript wird über einen Systemd-Timer täglich aufgerufen.

**Klone das Repository**

`git clone https://github.com/steff-sson/helper.git && cd helper`

**Mache notwendige Änderungen an dts-convert.sh**
(z.B. zu durchsuchenden Pfad und Log-Location)

`nano skripte/dts-convert/dts-convert.sh`

**Mache notwendige Änderungen an dts-convert.service**
(z.B. Pfad zu dts-convert.sh)

`nano skripte/dts-convert/dts-convert.service`

**Kopiere den Systemd-Service und -Timer**

```
sudo cp skripte/dts-convert/dts-convert.service /etc/systemd/system/ && sudo cp skripte/dts-convert/dts-convert.timer /etc/systemd/system/
```

**Installiere den Systemd-Timer**

`sudo systemctl enable dts-convert.timer`
