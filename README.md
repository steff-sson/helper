# Helper
Kleine Hilfsskripte und -programme, die den Alltag (eines Media-Servers) erleichtern und Backups einfacher ermöglichen (siehe [btrbk-home-clients](https://github.com/steff-sson/btrbk-home-clients))

## hooks
Pacman Hooks können vor, während oder nach der Installation von Paketen mit Pacman ausgeführt werden.
### pkglists
Dieses Hook schreibt eine aktuelle Liste installierter Pakte nach /home/pkglist.txt sowie home/pkglist-AUR.txt.

siehe [archwiki](https://wiki.archlinux.org/title/Pacman#Hooks))
#### Installation

**Klone das Repository**

`git clone https://github.com/steff-sson/helper.git && cd helper`

**Kopiere den Hook für Pacman**

`sudo mkdir /etc/pacman.d/hooks && sudo cp hooks/* /etc/pacman.d/hooks/`

**Lege die eine symbolische Verknüpfung in dein User-Home**

`ln -s /home/pkglist.txt /home/$USER/pkglist.txt`

## configs
### btrfsmaintenance
Konfigurationsdatei für [https://github.com/kdave/btrfsmaintenance](btrfsmaintenance). Hier werden **balance**, **scrub** und **trim** automatisch durchgeführt und in `/etc/default/btrfsmaintenance` konfiguriert.

**Klone das Repository**

`git clone https://github.com/steff-sson/helper.git && cd helper`

**Installiere das AUR-Paket btrfsmaintenance**

`yay btrfsmaintenance`

**Kopiere die Konfigurationsdatei**

`sudo cp configs/btrfsmaintenance /etc/default/`

**Mache notwendige Änderungen an btrfsmaintenance**
(z.B. zu durchsuchenden Pfad und Log-Location)

`sudo nano /etc/default/btrfsmaintenance`

**Aktiviere die Systemd-Timer**

```
sudo systemctl enable btrfs-balance.timer && sudo systemctl enable btrfs-scrub.timer && sudo systemctl enable btrfs-trim.timer
```

Hier die aktualisierte README:

***

## Skripte
### dts-convert
Ein Skript, das in einem konfigurierbaren Ordner rekursiv nach `*.mkv`-Dateien sucht, die eine **DTS- oder Dolby TrueHD-Tonspur** enthalten, und diese per `ffmpeg` verlustarm in **AC3 (640k)** umwandelt. Alle anderen Tonspuren (AC3, EAC3, AAC, Opus) bleiben unverändert. Konvertierte Spuren werden automatisch umbenannt: `Originaltitel (AC3 Reencode)`. Inklusive Logging mit Größenvergleich (Ersparnis in Byte und Prozent).

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

**Installiere notwendige Abhängigkeiten (Arch)**

```
sudo pacman -Sy && sudo pacman -S ffmpeg jq
```

**Kopiere den Systemd-Service und -Timer**

```
sudo cp skripte/dts-convert/dts-convert.service /etc/systemd/system/ && sudo cp skripte/dts-convert/dts-convert.timer /etc/systemd/system/
```

**Installiere den Systemd-Timer**

`sudo systemctl enable dts-convert.timer`

Hier der fertige README-Abschnitt zum Einfügen – im gleichen Stil wie deine bestehenden Abschnitte:

***

### log-daily / log-weekly

`log-daily.sh` analysiert täglich die Logs aller konfigurierten Docker-Container sowie das systemd-`journalctl` auf Fehler (`error`, `fatal`, `critical`, `exception`, `failed`, `crash`, `panic`, `refused`, `denied`, `killed`, `oom`). Container sind in Gruppen organisiert (KRITISCH, MEDIA, PAPERLESS, AI/VOICE, INFRASTRUKTUR, APPS) – jede Gruppe nutzt einen eigenen **Noise-Filter**, der bekannte, irrelevante Meldungen ausblendet. Das Ergebnis wird als `YYYY-MM-DD.txt` nach `/home/stef/logwatch/` geschrieben.

`log-weekly.sh` fasst die Tages-Reports der letzten 7 Tage zusammen: Tages-Übersicht (sauber / Fehler-Typen), **wiederkehrende Probleme** (Container, die ≥2× in der Woche aufgetaucht sind) sowie **neue Fehler** (nur heute, per `diff` gegen gestern). Output: `weekly-YYYY-WW.txt`.

Beide Skripte sind per Systemd-Timer automatisierbar.

#### Installation

**Klone das Repository**

`git clone https://github.com/steff-sson/helper.git && cd helper`

**Mache notwendige Änderungen an `log-daily.sh`**
(Container-Gruppen, Noise-Filter, Output-Pfad)

`nano skripte/logwatch/log-daily.sh`

**Mache notwendige Änderungen an `log-weekly.sh`**
(Output-Pfad)

`nano skripte/logwatch/log-weekly.sh`

**Mache notwendige Änderungen an den Systemd-Units**
(Pfad zu den Skripten)

```
nano skripte/logwatch/log-daily.service
nano skripte/logwatch/log-weekly.service
```

**Kopiere die Systemd-Services und -Timer**

```
sudo cp skripte/logwatch/*.service /etc/systemd/system/
sudo cp skripte/logwatch/*.timer /etc/systemd/system/
```

**Installiere die Systemd-Timer**

```
sudo systemctl enable --now log-daily.timer
sudo systemctl enable --now log-weekly.timer
```
```