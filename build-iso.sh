#!/bin/bash
# ============================================================
#  SnowFoxOS — ISO Builder v3.1
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "Bitte mit sudo ausführen: sudo bash build-iso.sh"
    exit 1
fi

apt-get update -qq
apt-get install -y \
    live-build debootstrap xorriso mtools \
    grub-pc-bin grub-efi-amd64-bin rsync git

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$REPO_DIR/iso_build_temp"
ISO_LABEL="SNOWFOX21"
ISO_NAME="SnowFoxOS-v2.1-amd64.iso"

echo ""
echo "  Projektordner : $REPO_DIR"
echo "  Build-Ordner  : $BUILD_DIR"
echo ""

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR" || exit 1

# ── 1. lb config ─────────────────────────────────────────────
lb config \
    --binary-images iso-hybrid \
    --debian-installer false \
    --distribution bookworm \
    --archive-areas "main contrib non-free non-free-firmware" \
    --iso-application "SnowFoxOS" \
    --iso-publisher "Xr7-Code" \
    --iso-volume "$ISO_LABEL" \
    --bootloaders "grub-efi" \
    --uefi-secure-boot disable \
    --memtest none \
    --bootappend-live "boot=live components locales=de_DE.UTF-8 keyboard-layouts=de quiet splash"

[[ $? -ne 0 ]] && echo "FEHLER: lb config fehlgeschlagen." && exit 1

# ── 2. Pakete ─────────────────────────────────────────────────
mkdir -p config/package-lists

cat > config/package-lists/live.list.chroot << 'PKGEOF'
live-boot
live-config
live-config-systemd
sudo
git
curl
wget
rsync
bash-completion
pciutils
usbutils
parted
xserver-xorg
xinit
i3-wm
i3status
feh
picom
kitty
rofi
dunst
polybar
fonts-jetbrains-mono
fonts-font-awesome
fonts-noto
fonts-noto-color-emoji
network-manager
network-manager-gnome
xsettingsd
lxappearance
arc-theme
papirus-icon-theme
gparted
ntfs-3g
mc
htop
neofetch
xdg-utils
dbus-x11
PKGEOF

# ── 3. GRUB ───────────────────────────────────────────────────
# Die grub.cfg wird zunächst mit Platzhaltern erstellt.
# Ein binary-Hook ersetzt die Platzhalter nach dem Build
# mit den echten Kernel-Dateinamen.
mkdir -p config/includes.binary/boot/grub

cat > config/includes.binary/boot/grub/grub.cfg << 'GRUBEOF'
set default=0
set timeout=10

insmod part_gpt
insmod part_msdos
insmod fat
insmod iso9660
insmod all_video
insmod font

if loadfont (cd0)/boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
fi

set root=(cd0)

menuentry "SnowFoxOS Live starten" {
    set root=(cd0)
    linux  /live/VMLINUZ_PLACEHOLDER boot=live components locales=de_DE.UTF-8 keyboard-layouts=de quiet splash
    initrd /live/INITRD_PLACEHOLDER
}

menuentry "SnowFoxOS Live (Failsafe)" {
    set root=(cd0)
    linux  /live/VMLINUZ_PLACEHOLDER boot=live components locales=de_DE.UTF-8 keyboard-layouts=de nomodeset noapic
    initrd /live/INITRD_PLACEHOLDER
}

menuentry "Neu starten" { reboot }
menuentry "Ausschalten" { halt }
GRUBEOF

# ── 3b. Binary-Hook: echte Kernel-Namen in grub.cfg eintragen ──
mkdir -p config/hooks/normal

cat > config/hooks/normal/9998-snowfox-grub-fix.hook.binary << 'HOOKEOF'
#!/bin/bash
# Läuft im iso_build_temp/ Verzeichnis.
# binary-Hooks laufen mit iso_build_temp/ als Arbeitsverzeichnis,
# das binary/-Verzeichnis liegt also direkt darunter.

# Mögliche Pfade durchsuchen
LIVE_DIR=""
for candidate in "binary/live" "live"; do
    if [[ -d "$candidate" ]]; then
        LIVE_DIR="$candidate"
        break
    fi
done

GRUB_CFG=""
for candidate in "binary/boot/grub/grub.cfg" "boot/grub/grub.cfg"; do
    if [[ -f "$candidate" ]]; then
        GRUB_CFG="$candidate"
        break
    fi
done

if [[ -z "$LIVE_DIR" ]]; then
    echo "FEHLER: live/-Verzeichnis nicht gefunden. Aktuelles Verzeichnis:"
    pwd
    ls -la
    exit 1
fi

if [[ -z "$GRUB_CFG" ]]; then
    echo "FEHLER: grub.cfg nicht gefunden. Aktuelles Verzeichnis:"
    pwd
    find . -name "grub.cfg" 2>/dev/null
    exit 1
fi

VMLINUZ=$(ls "$LIVE_DIR"/vmlinuz-* 2>/dev/null | sort -V | tail -1 | xargs basename)
INITRD=$(ls  "$LIVE_DIR"/initrd.img-* 2>/dev/null | sort -V | tail -1 | xargs basename)

if [[ -z "$VMLINUZ" || -z "$INITRD" ]]; then
    echo "FEHLER: Kernel oder Initrd nicht gefunden in $LIVE_DIR"
    ls "$LIVE_DIR"
    exit 1
fi

echo "Kernel gefunden : $VMLINUZ"
echo "Initrd gefunden : $INITRD"

sed -i "s|VMLINUZ_PLACEHOLDER|$VMLINUZ|g" "$GRUB_CFG"
sed -i "s|INITRD_PLACEHOLDER|$INITRD|g"   "$GRUB_CFG"

echo "grub.cfg aktualisiert:"
grep -E "linux |initrd " "$GRUB_CFG"
HOOKEOF
chmod +x config/hooks/normal/9998-snowfox-grub-fix.hook.binary

# ── 4. Verzeichnisstruktur im Live-System ─────────────────────
# includes.chroot wird 1:1 ins Live-System kopiert.
# Der Live-User heißt "user" (live-config Standard).
# Deshalb legen wir die Configs direkt nach /home/user/
# UND nach /etc/skel/ (für den Fall dass live-config skel ausrollt).

CHROOT="config/includes.chroot"

# Installer
mkdir -p "$CHROOT/opt/snowfox-installer"
rsync -av \
    --exclude='iso_build_temp' \
    --exclude='.git' \
    "$REPO_DIR/" \
    "$CHROOT/opt/snowfox-installer/"

# Configs — direkt nach /home/user/.config/ UND /etc/skel/.config/
mkdir -p "$CHROOT/home/user/.config"
mkdir -p "$CHROOT/etc/skel/.config"

if [[ -d "$REPO_DIR/configs" ]]; then
    cp -r "$REPO_DIR/configs/." "$CHROOT/home/user/.config/"
    cp -r "$REPO_DIR/configs/." "$CHROOT/etc/skel/.config/"
    echo "  Configs kopiert: $(ls "$REPO_DIR/configs/" | wc -l) Einträge"
fi

if [[ -d "$REPO_DIR/.config" ]]; then
    cp -r "$REPO_DIR/.config/." "$CHROOT/home/user/.config/"
    cp -r "$REPO_DIR/.config/." "$CHROOT/etc/skel/.config/"
fi

# Wallpapers — direkt nach /home/user/Pictures/wallpapers/
mkdir -p "$CHROOT/home/user/Pictures/wallpapers"
mkdir -p "$CHROOT/etc/skel/Pictures/wallpapers"

if [[ -d "$REPO_DIR/wallpapers" ]]; then
    cp -r "$REPO_DIR/wallpapers/." "$CHROOT/home/user/Pictures/wallpapers/"
    cp -r "$REPO_DIR/wallpapers/." "$CHROOT/etc/skel/Pictures/wallpapers/"
    echo "  Wallpapers kopiert: $(ls "$REPO_DIR/wallpapers/" | wc -l) Dateien"
fi

# snowfox CLI
mkdir -p "$CHROOT/usr/local/bin"
[[ -f "$REPO_DIR/snowfox.sh" ]] && \
    cp "$REPO_DIR/snowfox.sh" "$CHROOT/usr/local/bin/snowfox"
[[ -f "$REPO_DIR/snowfox-greeting.sh" ]] && \
    cp "$REPO_DIR/snowfox-greeting.sh" "$CHROOT/usr/local/bin/snowfox-greeting"

find "$CHROOT/opt/snowfox-installer/" -name "*.sh" -exec chmod +x {} \;
find "$CHROOT/usr/local/bin/" -type f -exec chmod +x {} \;

# ── 5. Polybar launch.sh ──────────────────────────────────────
# Falls noch keine launch.sh in den Configs ist, erstellen wir eine
mkdir -p "$CHROOT/home/user/.config/polybar"
mkdir -p "$CHROOT/etc/skel/.config/polybar"

if [[ ! -f "$CHROOT/home/user/.config/polybar/launch.sh" ]]; then
cat > "$CHROOT/home/user/.config/polybar/launch.sh" << 'LAUNCHEOF'
#!/bin/bash
sleep 1
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done
PRIMARY=$(xrandr --query | grep " connected primary" | cut -d" " -f1)
[[ -z "$PRIMARY" ]] && PRIMARY=$(xrandr --query | grep " connected" | head -1 | cut -d" " -f1)
MONITOR=$PRIMARY polybar snowfox 2>/tmp/polybar.log &
LAUNCHEOF
chmod +x "$CHROOT/home/user/.config/polybar/launch.sh"
cp "$CHROOT/home/user/.config/polybar/launch.sh" \
   "$CHROOT/etc/skel/.config/polybar/launch.sh"
fi

# ── 6. .bash_profile & .xinitrc ──────────────────────────────
cat > "$CHROOT/home/user/.bash_profile" << 'EOF'
export PATH=$PATH:/usr/local/bin

[[ -x /usr/local/bin/snowfox-greeting ]] && /usr/local/bin/snowfox-greeting

echo ""
echo "  ┌─────────────────────────────────────────────┐"
echo "  │           Willkommen bei SnowFoxOS          │"
echo "  │                                             │"
echo "  │  Desktop starten  →  startx                 │"
echo "  │  OS installieren  →  sudo bash              │"
echo "  │   /opt/snowfox-installer/install.sh         │"
echo "  └─────────────────────────────────────────────┘"
echo ""

# Automatisch startx auf TTY1
if [[ -z "$DISPLAY" ]] && [[ "$(tty)" = "/dev/tty1" ]]; then
    echo "  Drücke Enter um den Desktop zu starten..."
    read -r
    exec startx
fi
EOF
cp "$CHROOT/home/user/.bash_profile" "$CHROOT/etc/skel/.bash_profile"

cat > "$CHROOT/home/user/.xinitrc" << 'EOF'
#!/bin/sh
export GTK_THEME=Arc-Dark
export QT_QPA_PLATFORMTHEME=qt5ct
export _JAVA_AWT_WM_NONREPARENTING=1

# NetworkManager starten falls nicht aktiv
sudo systemctl start NetworkManager 2>/dev/null &

# Wallpaper — alle gängigen Formate suchen
WP=""
for ext in jpg jpeg png webp JPG JPEG PNG WEBP; do
    FOUND=$(ls ~/Pictures/wallpapers/*.$ext 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
        WP="$FOUND"
        break
    fi
done

if [[ -n "$WP" ]]; then
    feh --bg-fill "$WP" &
else
    xsetroot -solid "#0f0f0f" &
fi

xsettingsd &
picom --daemon &
dunst &

# Polybar — mit kurzem Delay damit i3 zuerst startet
(sleep 2 && bash ~/.config/polybar/launch.sh) &

exec i3
EOF
cp "$CHROOT/home/user/.xinitrc" "$CHROOT/etc/skel/.xinitrc"
chmod +x "$CHROOT/home/user/.xinitrc" "$CHROOT/etc/skel/.xinitrc"

# Autologin — live-config direkt konfigurieren
# live-config liest /etc/live/config.conf und setzt Autologin
mkdir -p "$CHROOT/etc/live"
cat > "$CHROOT/etc/live/config.conf" << 'EOF'
LIVE_USERNAME="user"
LIVE_USER_FULLNAME="SnowFox Live"
LIVE_USER_DEFAULT_GROUPS="audio,cdrom,dip,floppy,netdev,plugdev,sudo,video"
LIVE_AUTOLOGIN="true"
EOF

# TTY1 Autologin per systemd sicherstellen (Fallback)
mkdir -p "$CHROOT/etc/systemd/system/getty@tty1.service.d"
cat > "$CHROOT/etc/systemd/system/getty@tty1.service.d/autologin.conf" << 'EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin user --noclear %I $TERM
Type=idle
EOF

# ── 7. sudo ohne Passwort für Live-User ──────────────────────
mkdir -p "$CHROOT/etc/sudoers.d"
cat > "$CHROOT/etc/sudoers.d/live-user" << 'EOF'
user ALL=(ALL) NOPASSWD: ALL
EOF
chmod 440 "$CHROOT/etc/sudoers.d/live-user"

# ── 8. Hook: Berechtigungen nach dem Chroot-Build setzen ─────
# live-build baut das System in einem chroot — danach müssen
# die /home/user Dateien dem richtigen User gehören.
# Das erledigt ein chroot-hook der am Ende des Builds läuft.
mkdir -p config/hooks/normal

cat > config/hooks/normal/9999-snowfox-permissions.hook.chroot << 'HOOKEOF'
#!/bin/bash
# Berechtigungen für Live-User setzen
# Der Standard-Live-User von live-config ist "user" (uid 1000)
if id "user" &>/dev/null; then
    chown -R user:user /home/user/
fi

# NetworkManager aktivieren
systemctl enable NetworkManager 2>/dev/null || true

# Nerd Fonts für Polybar (Fuchs-Emoji Fix)
mkdir -p /usr/local/share/fonts/nerd-fonts
if command -v curl &>/dev/null; then
    NERD_VER="v3.2.1"
    curl -L "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VER}/JetBrainsMono.zip" \
        -o /tmp/JetBrainsMono.zip 2>/dev/null && \
    unzip -o /tmp/JetBrainsMono.zip "*.ttf" \
        -d /usr/local/share/fonts/nerd-fonts/ 2>/dev/null && \
    fc-cache -fv /usr/local/share/fonts/nerd-fonts/ 2>/dev/null && \
    rm -f /tmp/JetBrainsMono.zip
fi
HOOKEOF
chmod +x config/hooks/normal/9999-snowfox-permissions.hook.chroot

# ── 9. Build ─────────────────────────────────────────────────
echo ""
echo "  Starte lb build — dauert 15-45 Minuten..."
echo "  Log: $REPO_DIR/build.log"
echo ""

lb build 2>&1 | tee "$REPO_DIR/build.log"

# ── 10. ISO speichern ────────────────────────────────────────
ISO_FINAL="$REPO_DIR/$ISO_NAME"

for candidate in \
    "$BUILD_DIR/live-image-amd64.hybrid.iso" \
    "$BUILD_DIR/live-image-amd64.iso"; do
    if [[ -f "$candidate" ]]; then
        mv "$candidate" "$ISO_FINAL"
        break
    fi
done

if [[ ! -f "$ISO_FINAL" ]]; then
    echo "FEHLER: Build fehlgeschlagen. Siehe $REPO_DIR/build.log"
    exit 1
fi

echo ""
echo "  ════════════════════════════════════════════"
echo "  ERFOLG: $ISO_NAME"
echo "  Größe : $(du -sh "$ISO_FINAL" | cut -f1)"
echo "  ════════════════════════════════════════════"
echo ""
echo "  Flashen:"
echo "  sudo dd if=$ISO_FINAL of=/dev/sdX bs=4M status=progress && sync"
echo ""