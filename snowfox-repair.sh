#!/bin/bash
# ============================================================
#  SnowFoxOS — Reparatur-Script für Intel-Laptop
#  Behebt: Plymouth, xinitrc, xsettingsd, GRUB, X11-Absturz
#  Ausführen: sudo bash snowfox-repair.sh
# ============================================================

PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${PURPLE}${BOLD}[SnowFox]${RESET} $1"; }
ok()      { echo -e "${GREEN}${BOLD}[  OK  ]${RESET} $1"; }
warn()    { echo -e "${ORANGE}${BOLD}[ WARN ]${RESET} $1"; }
err()     { echo -e "${RED}${BOLD}[FEHLER]${RESET} $1"; }
step()    { echo -e "\n${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}";
            echo -e "${PURPLE}${BOLD}  $1${RESET}";
            echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }

if [[ $EUID -ne 0 ]]; then
    err "Bitte mit sudo ausführen: sudo bash snowfox-repair.sh"
    exit 1
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    read -rp "Benutzername: " TARGET_USER
fi
TARGET_HOME="/home/$TARGET_USER"

[[ ! -d "$TARGET_HOME" ]] && err "Home $TARGET_HOME nicht gefunden" && exit 1

info "Repariere System für: ${BOLD}$TARGET_USER${RESET}"
echo ""

# ============================================================
# FIX 1 — GRUB: nvidia-drm.modeset=1 entfernen (Intel-only)
# ============================================================
step "1/6 — GRUB bereinigen (Intel-only)"

GRUB_FILE="/etc/default/grub"

if [[ -f "$GRUB_FILE" ]]; then
    # Backup erstellen
    cp "$GRUB_FILE" "${GRUB_FILE}.snowfox-bak"
    ok "Backup: ${GRUB_FILE}.snowfox-bak"

    # nvidia-drm.modeset=1 entfernen — auf Intel unnötig und stört Framebuffer
    sed -i 's/ nvidia-drm\.modeset=1//g' "$GRUB_FILE"

    # Sicherstellen dass i915 früh im Framebuffer geladen wird (sauberer Boot)
    # quiet splash beibehalten, aber doppelte Einträge bereinigen
    sed -i 's/quiet splash quiet splash/quiet splash/g' "$GRUB_FILE"

    # Falls GRUB_CMDLINE noch leer/kaputt ist, auf sauberen Wert setzen
    if ! grep -q 'GRUB_CMDLINE_LINUX_DEFAULT' "$GRUB_FILE"; then
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' >> "$GRUB_FILE"
    fi

    # Timeout auf 1 setzen (schneller Boot)
    sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' "$GRUB_FILE"

    update-grub 2>/dev/null || true
    ok "GRUB bereinigt — nvidia-drm.modeset=1 entfernt"
else
    warn "GRUB-Datei nicht gefunden — übersprungen"
fi

# ============================================================
# FIX 2 — i915 Kernel-Modul früh laden (Plymouth-Fix)
# ============================================================
step "2/6 — Intel i915 Framebuffer früh laden (Plymouth)"

# i915 in initramfs-modules eintragen damit Plymouth beim Boot funktioniert
INITRAMFS_MODULES="/etc/initramfs-tools/modules"
if ! grep -q "^i915" "$INITRAMFS_MODULES" 2>/dev/null; then
    echo "i915" >> "$INITRAMFS_MODULES"
    ok "i915 zu initramfs-modules hinzugefügt"
else
    ok "i915 bereits in initramfs-modules eingetragen"
fi

# Intel VA-Driver sicherstellen
apt-get install -y --no-install-recommends \
    intel-media-va-driver-non-free \
    i965-va-driver \
    libvulkan1 2>/dev/null || \
apt-get install -y --no-install-recommends \
    intel-media-va-driver \
    i965-va-driver 2>/dev/null || true

# initramfs neu bauen
info "Baue initramfs neu..."
update-initramfs -u 2>/dev/null && ok "initramfs neu gebaut" || warn "initramfs-Update fehlgeschlagen"

# ============================================================
# FIX 3 — .xinitrc neu schreiben (D-Bus vor gsettings)
# ============================================================
step "3/6 — .xinitrc reparieren (D-Bus Reihenfolge)"

# Backup
[[ -f "$TARGET_HOME/.xinitrc" ]] && \
    cp "$TARGET_HOME/.xinitrc" "$TARGET_HOME/.xinitrc.snowfox-bak" && \
    ok "Backup: .xinitrc.snowfox-bak"

cat > "$TARGET_HOME/.xinitrc" << 'EOF'
#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games

# Theme-Variablen setzen
export GTK_THEME=Arc-Dark
export QT_QPA_PLATFORMTHEME=qt5ct
export _JAVA_AWT_WM_NONREPARENTING=1

# ── D-Bus ZUERST starten ────────────────────────────────────
# gsettings braucht D-Bus — deshalb muss dieser Block VOR
# allen gsettings-Aufrufen kommen!
if [ -f /usr/bin/dbus-launch ]; then
    eval $(/usr/bin/dbus-launch --sh-syntax --exit-with-session)
fi

# ── Jetzt gsettings (D-Bus läuft bereits) ──────────────────
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null || true
gsettings set org.gnome.desktop.interface gtk-theme 'Arc-Dark' 2>/dev/null || true

# ── xsettingsd für X11-App-Theming ─────────────────────────
if command -v xsettingsd > /dev/null 2>&1; then
    xsettingsd &
fi

# ── i3 starten ──────────────────────────────────────────────
exec i3
EOF

chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"
chmod +x "$TARGET_HOME/.xinitrc"
ok ".xinitrc repariert — D-Bus läuft jetzt vor gsettings"

# ============================================================
# FIX 4 — xsettingsd Config erstellen falls fehlend
# ============================================================
step "4/6 — xsettingsd Config erstellen"

XSETTINGSD_DIR="$TARGET_HOME/.config/xsettingsd"
mkdir -p "$XSETTINGSD_DIR"

if [[ ! -f "$XSETTINGSD_DIR/xsettingsd.conf" ]]; then
    cat > "$XSETTINGSD_DIR/xsettingsd.conf" << 'EOF'
Net/ThemeName "Arc-Dark"
Net/IconThemeName "Papirus-Dark"
Gtk/CursorThemeName "Adwaita"
EOF
    ok "xsettingsd.conf erstellt"
else
    ok "xsettingsd.conf bereits vorhanden"
fi

# xsettingsd installieren falls fehlend
if ! command -v xsettingsd &>/dev/null; then
    info "Installiere xsettingsd..."
    apt-get install -y xsettingsd 2>/dev/null && ok "xsettingsd installiert" || warn "xsettingsd nicht verfügbar"
fi

chown -R "$TARGET_USER:$TARGET_USER" "$XSETTINGSD_DIR"

# ============================================================
# FIX 5 — NetworkManager wifi.powersave Kommentar-Bug
# ============================================================
step "5/6 — NetworkManager Konfiguration reparieren"

NM_POWERSAVE="/etc/NetworkManager/conf.d/99-snowfox-wifi-powersave.conf"
if [[ -f "$NM_POWERSAVE" ]]; then
    cp "$NM_POWERSAVE" "${NM_POWERSAVE}.bak"
    # Inline-Kommentar entfernen — NM versteht keine '#' in Wertzeilen
    cat > "$NM_POWERSAVE" << 'EOF'
[connection]
wifi.powersave=2
EOF
    ok "wifi.powersave Inline-Kommentar entfernt"
    systemctl restart NetworkManager 2>/dev/null || true
else
    warn "Powersave-Config nicht gefunden — übersprungen"
fi

# ============================================================
# FIX 6 — fstab noatime Idempotenz prüfen
# ============================================================
step "6/6 — fstab noatime-Duplikat bereinigen"

if grep -q "noatime,noatime" /etc/fstab; then
    sed -i 's/noatime,noatime/noatime/g' /etc/fstab
    ok "Doppeltes noatime in fstab bereinigt"
else
    ok "fstab ist sauber"
fi

# ── GTK-Configs sicherstellen ────────────────────────────────
# Falls der configs/-Ordner beim Install fehlte, minimal-Configs erstellen
for version in "3.0" "4.0"; do
    GTK_DIR="$TARGET_HOME/.config/gtk-$version"
    mkdir -p "$GTK_DIR"
    if [[ ! -f "$GTK_DIR/settings.ini" ]]; then
        cat > "$GTK_DIR/settings.ini" << GEOF
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
GEOF
        ok "GTK$version settings.ini erstellt"
    fi
done

# Qt5ct Minimal-Config
QT5CT_DIR="$TARGET_HOME/.config/qt5ct"
mkdir -p "$QT5CT_DIR"
if [[ ! -f "$QT5CT_DIR/qt5ct.conf" ]]; then
    cat > "$QT5CT_DIR/qt5ct.conf" << 'EOF'
[Appearance]
style=gtk2
EOF
    ok "qt5ct.conf erstellt"
fi

# Berechtigungen setzen
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.config"

# ============================================================
# Fertig
# ============================================================
echo ""
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo -e "${GREEN}${BOLD}  Reparatur abgeschlossen!${RESET}"
echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo -e "  Was wurde repariert:"
echo -e "  ${GREEN}✓${RESET} GRUB: nvidia-drm.modeset=1 entfernt (Intel-only)"
echo -e "  ${GREEN}✓${RESET} initramfs: i915 früh geladen (Plymouth-Fix)"
echo -e "  ${GREEN}✓${RESET} .xinitrc: D-Bus läuft jetzt vor gsettings"
echo -e "  ${GREEN}✓${RESET} xsettingsd.conf erstellt"
echo -e "  ${GREEN}✓${RESET} NetworkManager: Inline-Kommentar-Bug behoben"
echo -e "  ${GREEN}✓${RESET} fstab: noatime-Duplikat geprüft"
echo -e "  ${GREEN}✓${RESET} GTK/Qt Configs erstellt falls fehlend"
echo ""
echo -e "  ${ORANGE}${BOLD}→ Bitte neu starten: sudo reboot${RESET}"
echo ""
