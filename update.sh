#!/bin/bash
# ============================================================
#  SnowFoxOS — Update Script
#  Aktualisiert Configs, CLI und Pakete auf einem
#  bestehenden SnowFoxOS-System.
# ============================================================

set -euo pipefail

# ── Farben ───────────────────────────────────────────────────
BLD='\033[1m'
PRP='\033[0;35m'
GRN='\033[0;32m'
YLW='\033[0;33m'
RED='\033[0;31m'
RST='\033[0m'

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$HOME/.snowfox-backup/$(date +%Y%m%d_%H%M%S)"

step()  { echo -e "\n${PRP}${BLD}━━━  $1${RST}"; }
ok()    { echo -e "${GRN}✓${RST}  $1"; }
warn()  { echo -e "${YLW}⚠${RST}  $1"; }
abort() { echo -e "${RED}✗${RST}  $1"; exit 1; }

# ── Voraussetzungen ──────────────────────────────────────────
[[ "$EUID" -eq 0 ]] && abort "Nicht als root ausführen. Einfach: bash update.sh"
[[ -f "$REPO_DIR/snowfox" ]] || abort "Dieses Skript muss aus dem SnowFoxOS-Repo-Ordner gestartet werden."

echo -e "\n${PRP}${BLD}  SnowFoxOS — System Update${RST}"
echo    "  Backup wird unter $BACKUP_DIR gespeichert"
echo -e "  Drücke Enter zum Fortfahren oder Ctrl+C zum Abbrechen.\n"
read -r

# ── 1. Backup ────────────────────────────────────────────────
step "1/4 — Backup der aktuellen Configs"
mkdir -p "$BACKUP_DIR"
for dir in i3 polybar rofi dunst kitty snowfox-greeting.sh; do
    src="$HOME/.config/$dir"
    [[ -e "$src" ]] && cp -r "$src" "$BACKUP_DIR/" && ok "Gesichert: ~/.config/$dir"
done
[[ -f /usr/local/bin/snowfox ]] && cp /usr/local/bin/snowfox "$BACKUP_DIR/snowfox.bak" && ok "Gesichert: snowfox CLI"
ok "Backup abgeschlossen → $BACKUP_DIR"

# ── 2. Pakete ────────────────────────────────────────────────
step "2/4 — Pakete aktualisieren"
sudo apt-get update -qq
sudo apt-get upgrade -y
ok "Pakete aktualisiert"

# ── 3. CLI ───────────────────────────────────────────────────
step "3/4 — snowfox CLI aktualisieren"
sudo cp "$REPO_DIR/snowfox" /usr/local/bin/snowfox
sudo chmod +x /usr/local/bin/snowfox
ok "snowfox CLI aktualisiert"

# ── 4. Configs ───────────────────────────────────────────────
step "4/4 — Configs aktualisieren"
if [[ ! -d "$REPO_DIR/configs" ]]; then
    warn "Kein configs/-Ordner gefunden, überspringe."
else
    cp -r "$REPO_DIR/configs/"* "$HOME/.config/"
    ok "Configs kopiert nach ~/.config/"

    # i3 neu laden
    if command -v i3-msg &>/dev/null; then
        i3-msg reload &>/dev/null && ok "i3 neu geladen"
    fi

    # Polybar neu starten
    if pgrep -x polybar &>/dev/null; then
        pkill polybar
        sleep 0.5
        polybar snowfox &>/dev/null &
        ok "Polybar neu gestartet"
    fi

    # Dunst neu starten
    if pgrep -x dunst &>/dev/null; then
        pkill dunst
        sleep 0.3
        dunst &>/dev/null &
        ok "Dunst neu gestartet"
    fi
fi

# ── Fertig ───────────────────────────────────────────────────
echo -e "\n${PRP}${BLD}  Update abgeschlossen.${RST}"
echo -e "  Backup liegt unter: ${BLD}$BACKUP_DIR${RST}"
echo -e "  Bei Problemen: ${BLD}cp -r $BACKUP_DIR/* ~/.config/${RST}\n"
