#!/bin/bash
# ============================================================
#  SnowFoxOS v2.1 — Installer
#  Basis: Debian 12 (Bookworm) minimal
#  Desktop: i3 + Polybar + Rofi + Dunst + i3lock
#  Ausführen: sudo bash install.sh
# ============================================================

# Kein globales set -e — Fehler werden manuell behandelt

PURPLE='\033[0;35m'
ORANGE='\033[0;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
GRAY='\033[0;37m'
BOLD='\033[1m'
RESET='\033[0m'

info()    { echo -e "${PURPLE}${BOLD}[SnowFox]${RESET} $1"; }
success() { echo -e "${GREEN}${BOLD}[  OK  ]${RESET} $1"; }
warn()    { echo -e "${ORANGE}${BOLD}[ WARN ]${RESET} $1"; }
error()   { echo -e "${RED}${BOLD}[FEHLER]${RESET} $1"; exit 1; }
step()    { echo -e "\n${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}";
            echo -e "${PURPLE}${BOLD}  $1${RESET}";
            echo -e "${PURPLE}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"; }
ask_install() {
    echo ""
    read -rp "$(echo -e ${PURPLE}${BOLD}"[SnowFox] $1 installieren? [j/n]: "${RESET})" choice
    [[ "$choice" =~ ^[jJ]$ ]]
}

# APT-Lock abwarten (verhindert Kollision mit unattended-upgrades)
wait_apt() {
    local i=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock > /dev/null 2>&1; do
        [[ $i -eq 0 ]] && info "Warte auf apt-Lock..."
        sleep 2; i=$((i+1))
        [[ $i -gt 60 ]] && error "apt-Lock nach 120s nicht frei"
    done
}

if [[ $EUID -ne 0 ]]; then
    error "Bitte mit sudo ausführen: sudo bash install.sh"
fi

# Validierung der Basis-Distribution
if [[ ! -f /etc/debian_version ]] || ! grep -q "^12\." /etc/debian_version; then
    warn "Dieses Script ist für Debian 12 (Bookworm) optimiert. Die Ausführung auf anderen Versionen kann zu Fehlern führen."
fi

TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
if [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]]; then
    read -rp "Benutzername: " TARGET_USER
fi
TARGET_HOME="/home/$TARGET_USER"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

[[ ! -d "$TARGET_HOME" ]] && error "Home $TARGET_HOME nicht gefunden"

info "Installiere für: ${BOLD}$TARGET_USER${RESET}"
sleep 1

# ============================================================
# SCHRITT 1 — System & Repositories
# ============================================================
step "1/10 — System aktualisieren"

DKMS_HOOKS=(
    /etc/kernel/postinst.d/dkms
    /etc/kernel/prerm.d/dkms
    /usr/lib/kernel/install.d/50-dkms.install
)
for hook in "${DKMS_HOOKS[@]}"; do
    [[ -f "$hook" ]] && mv "$hook" "${hook}.snowfox-bak"
done
info "DKMS-Hooks für Installer-Lauf deaktiviert"

cat > /etc/apt/sources.list << 'EOF'
deb http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ bookworm-updates main contrib non-free non-free-firmware
EOF

wait_apt
dpkg --add-architecture i386
apt-get update -qq
dpkg --configure -a 2>/dev/null || true
apt-get -f install -y 2>/dev/null || true
wait_apt
apt-get upgrade -y
apt-get install -y \
    curl wget git unzip \
    build-essential \
    ca-certificates \
    aria2 \
    fzf \
    lz4 \
    gnupg \
    pciutils usbutils \
    htop btop neofetch irqbalance \
    bash-completion \
    xdg-utils \
    xdg-user-dirs \
    rfkill \
    imagemagick \
    bc \
    xorg \
    xinit \
    x11-utils \
    x11-xserver-utils \
    xclip \
    xdotool \
    dbus-x11

sudo -u "$TARGET_USER" xdg-user-dirs-update
success "System aktualisiert"

# ── XanMod Kernel ────────────────────────────────────────────
info "Prüfe CPU-Kompatibilität für x64v3..."
if ! grep -q "avx2" /proc/cpuinfo; then
    warn "CPU unterstützt kein AVX2. x64v3 Kernel wird nicht funktionieren."
    error "Installation abgebrochen, um System-Brick zu verhindern."
fi

# DKMS-Tools zuerst — werden für NVIDIA-Modulbau benötigt
info "Installiere DKMS-Tools..."
apt-get install -y --no-install-recommends dkms libdw-dev clang lld llvm
success "DKMS-Tools installiert"

info "Installiere XanMod LTS Kernel..."
# Broken packages bereinigen bevor XanMod installiert wird
dpkg --configure -a 2>/dev/null || true
apt-get -f install -y 2>/dev/null || true

mkdir -p /etc/apt/keyrings
wget -qO - https://dl.xanmod.org/archive.key \
    | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg

# bookworm hardcodiert — lsb_release auf minimalem Debian liefert "n/a"
echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org bookworm main" \
    > /etc/apt/sources.list.d/xanmod-release.list

wait_apt
apt-get update -qq
wait_apt

# linux-xanmod-x64v3 zieht Image + Headers automatisch mit
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-lts-x64v3
XANMOD_EXIT=$?

if [[ $XANMOD_EXIT -eq 0 ]]; then
    success "XanMod Kernel installiert (aktiv nach Reboot)"
    CURRENT_KERNEL=$(uname -r)
    # GRUB für Plymouth (Boot-Logo) vorbereiten
    if [[ -f /etc/default/grub ]]; then
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 quiet splash nvidia-drm.modeset=1"/' /etc/default/grub
        sed -i 's/quiet splash quiet splash/quiet splash/g' /etc/default/grub
        sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
    fi
    info "Alte Kernel wurden zur Sicherheit behalten. Bereinigung nach erstem erfolgreichen Boot empfohlen."
    update-grub 2>/dev/null || true
    success "Boot-Konfiguration aktualisiert"
else
    warn "XanMod fehlgeschlagen (Exit $XANMOD_EXIT) — Installation wird fortgesetzt"
fi

# Fritz USB AC 860 Treiber
info "Prüfe Fritz USB AC 860 Treiber..."
apt-get install -y firmware-misc-nonfree 2>/dev/null || true
if lsusb 2>/dev/null | grep -qi "fritz\|0x0bda\|2357"; then
    modprobe mt76x2u 2>/dev/null && \
        success "Fritz USB AC 860 Treiber geladen" || \
        warn "Fritz USB Treiber nicht gefunden — nach Reboot prüfen"
fi

# ============================================================
# SCHRITT 2 — Hardware-Erkennung & Treiber
# ============================================================
step "2/10 — Hardware-Analyse & Treiber"

IS_LAPTOP=false
[[ "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true

CPU_INFO=$(grep -m1 "vendor_id" /proc/cpuinfo)
if echo "$CPU_INFO" | grep -qi "AuthenticAMD"; then
    apt-get install -y amd64-microcode
    success "AMD CPU Microcode installiert"
else
    apt-get install -y intel-microcode
    success "Intel CPU Microcode installiert"
fi

GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
HAS_NVIDIA=false
HAS_AMD=false
echo "$GPU_INFO" | grep -qi "nvidia" && HAS_NVIDIA=true
echo "$GPU_INFO" | grep -qi "amd"    && HAS_AMD=true

if $HAS_NVIDIA; then
    info "NVIDIA GPU erkannt — Installiere Treiber via CUDA-Repo..."

    apt-get install -y clang-19 lld-19 2>/dev/null || \
        apt-get install -y clang lld || true

    update-alternatives --install /usr/bin/clang   clang   /usr/bin/clang-19  100 2>/dev/null || true
    update-alternatives --install /usr/bin/clang++ clang++ /usr/bin/clang++-19 100 2>/dev/null || true
    update-alternatives --install /usr/bin/lld     lld     /usr/bin/lld-19    100 2>/dev/null || true
    update-alternatives --install /usr/bin/ld.lld  ld.lld  /usr/bin/lld-19    100 2>/dev/null || true
    update-alternatives --set clang  /usr/bin/clang-19  2>/dev/null || true
    update-alternatives --set lld    /usr/bin/lld-19    2>/dev/null || true
    update-alternatives --set ld.lld /usr/bin/lld-19    2>/dev/null || true

    curl -fsSL https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/3bf863cc.pub \
        | gpg --dearmor | tee /usr/share/keyrings/nvidia-cuda-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/nvidia-cuda-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian12/x86_64/ /" \
        | tee /etc/apt/sources.list.d/nvidia-cuda.list

    cat > /etc/apt/preferences.d/nvidia-cuda << 'EOF'
Package: cuda-drivers* nvidia-* libcuda* libnvidia-*
Pin: origin "developer.download.nvidia.com"
Pin-Priority: 900

Package: *
Pin: release o=Debian
Pin-Priority: 500
EOF

    wait_apt
    apt-get update -qq
    apt-get purge -y nvidia-driver nvidia-kernel-dkms 2>/dev/null || true
    wait_apt
    apt-get install -y \
        cuda-drivers-580 \
        libvulkan1 libvulkan1:i386 \
        nvidia-vulkan-icd nvidia-vulkan-icd:i386

    if $HAS_AMD; then
        if apt-cache show envycontrol > /dev/null 2>&1; then
            apt-get install -y envycontrol && success "envycontrol installiert"
        else
            python3 -m venv /opt/envycontrol-venv 2>/dev/null || true
            /opt/envycontrol-venv/bin/pip install envycontrol 2>/dev/null || true
            ln -sf /opt/envycontrol-venv/bin/envycontrol /usr/local/bin/envycontrol 2>/dev/null || true
            success "envycontrol installiert (venv)"
        fi
    fi

    XANMOD_KERNEL=$(ls /lib/modules 2>/dev/null | grep xanmod | sort -V | tail -1)
    NVIDIA_VER=$(ls /var/lib/dkms/nvidia/ 2>/dev/null | sort -V | tail -1)
    if [[ -n "$XANMOD_KERNEL" && -n "$NVIDIA_VER" ]]; then
        info "Baue NVIDIA DKMS-Module für $XANMOD_KERNEL..."
        dkms install nvidia/"$NVIDIA_VER" -k "$XANMOD_KERNEL" 2>/dev/null || \
            warn "DKMS-Build fehlgeschlagen — nach Reboot prüfen"
        success "NVIDIA DKMS-Module gebaut"
    else
        warn "DKMS übersprungen (Kernel: ${XANMOD_KERNEL:-?}, NVIDIA: ${NVIDIA_VER:-?})"
    fi

    success "NVIDIA Stack installiert"

elif $HAS_AMD; then
    info "AMD GPU erkannt — Nutze Mesa..."
    apt-get install -y firmware-amd-graphics mesa-vulkan-drivers mesa-va-drivers
    success "AMD Stack installiert"
else
    info "Intel Grafik erkannt..."
    apt-get install -y intel-media-va-driver-non-free i965-va-driver 2>/dev/null || true
    success "Intel Stack installiert"
fi

if $IS_LAPTOP; then
    info "Laptop erkannt: Installiere Akku- & Touchpad-Tools..."
    apt-get install -y tlp tlp-rdw thermald xserver-xorg-input-libinput
    systemctl enable tlp thermald
    success "Laptop-Optimierung abgeschlossen"
fi

success "GPU-Treiber eingerichtet"

# ============================================================
# SCHRITT 3 — i3 Desktop
# ============================================================
step "3/10 — i3 + Polybar + Rofi + Dunst + i3lock"

wait_apt
apt-get install -y \
    i3 \
    i3status \
    i3lock \
    polybar \
    rofi \
    dunst \
    libnotify-bin \
    libappindicator3-1 \
    libayatana-appindicator3-1 \
    feh \
    xdg-desktop-portal-gtk \
    xdg-desktop-portal \
    libdbusmenu-gtk3-4 \
    redshift \
    scrot \
    brightnessctl \
    playerctl \
    network-manager \
    network-manager-gnome \
    bluez \
    blueman \
    fonts-inter \
    fonts-noto \
    fonts-noto-color-emoji \
    fonts-font-awesome \
    papirus-icon-theme \
    arc-theme \
    qt5ct \
    qt6ct \
    qt5-style-plugins \
    adwaita-qt \
    xsettingsd \
    lxpolkit \
    lxappearance \
    picom \
    xss-lock \
    xserver-xorg-input-libinput \
    diodon \
    cups cups-bsd cups-client \
    printer-driver-splix

systemctl enable bluetooth

mkdir -p /etc/X11/xorg.conf.d
if [[ -f "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" ]]; then
    cp "$SCRIPT_DIR/configs/xorg/30-touchpad.conf" /etc/X11/xorg.conf.d/30-touchpad.conf
    info "Touchpad-Config aus Repo kopiert"
else
    cat > /etc/X11/xorg.conf.d/30-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier      "libinput touchpad"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver          "libinput"
    Option          "Tapping"            "on"
    Option          "ClickMethod"        "clickfinger"
    Option          "NaturalScrolling"   "true"
    Option          "DisableWhileTyping" "on"
EndSection
EOF
    info "Touchpad-Config erstellt"
fi

BASH_PROFILE="$TARGET_HOME/.bash_profile"
if ! grep -q "startx" "$BASH_PROFILE" 2>/dev/null; then
    echo '' >> "$BASH_PROFILE"
    echo '# SnowFoxOS — i3 automatisch starten' >> "$BASH_PROFILE"
    echo '[ "$(tty)" = "/dev/tty1" ] && exec startx' >> "$BASH_PROFILE"
fi

cat > "$TARGET_HOME/.xinitrc" << 'EOF'
#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games

# Theme & Dark Mode Konfiguration
export GTK_THEME=Arc-Dark
export QT_QPA_PLATFORMTHEME=qt5ct
export _JAVA_AWT_WM_NONREPARENTING=1

# Globaler Dark Mode für GTK4/Electron/Modern Apps
gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
gsettings set org.gnome.desktop.interface gtk-theme 'Arc-Dark'

xsettingsd &

if [ -f /usr/bin/dbus-launch ]; then
    eval $(/usr/bin/dbus-launch --sh-syntax --exit-with-session)
fi
exec i3
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"
chmod +x "$TARGET_HOME/.xinitrc"

success "i3 Desktop & Autostart eingerichtet"

# ============================================================
# SCHRITT 4 — Audio (PipeWire)
# ============================================================
step "4/10 — Audio (PipeWire)"

wait_apt
apt-get install -y \
    pipewire \
    pipewire-pulse \
    pipewire-alsa \
    wireplumber \
    pavucontrol \
    pulseaudio-utils

apt-get remove --purge -y pulseaudio 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true

success "PipeWire installiert"

# ============================================================
# SCHRITT 5 — Terminal & Apps
# ============================================================
step "5/10 — Terminal & Standard-Apps"

wait_apt
apt-get install -y \
    kitty \
    mc \
    mousepad \
    ristretto \
    file-roller \
    mpv \
    ffmpeg

echo ""
echo -e "${PURPLE}${BOLD}  Dateimanager:${RESET}"
echo -e "  1) Thunar  (grafisch, empfohlen)"
echo -e "  2) MC      (Terminal, bereits installiert)"
echo -e "  3) Beide"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-3]: "${RESET})" FM_CHOICE
case "$FM_CHOICE" in
    1|3) apt-get install -y thunar thunar-archive-plugin thunar-volman gvfs gvfs-backends
         success "Thunar installiert" ;;
    2)   success "MC bereits installiert" ;;
    *)   apt-get install -y thunar thunar-archive-plugin thunar-volman gvfs gvfs-backends
         success "Thunar installiert (Standard)" ;;
esac

if ask_install "VLC Media Player"; then
    apt-get install -y vlc && success "VLC installiert"
fi

if ask_install "GIMP (Bildbearbeitung)"; then
    apt-get install -y gimp && success "GIMP installiert"
fi

if ask_install "VSCodium"; then
    curl -fsSL https://gitlab.com/paulcarroty/vscodium-deb-rpm-repo/raw/master/pub.gpg \
        | gpg --dearmor | tee /usr/share/keyrings/vscodium-archive-keyring.gpg > /dev/null
    echo "deb [signed-by=/usr/share/keyrings/vscodium-archive-keyring.gpg] https://download.vscodium.com/debs vscodium main" \
        | tee /etc/apt/sources.list.d/vscodium.list
    wait_apt; apt-get update -qq
    apt-get install -y codium && success "VSCodium installiert" || warn "VSCodium fehlgeschlagen"
fi

if ask_install "OnlyOffice"; then
    mkdir -p -m 755 /etc/apt/keyrings
    curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE \
        | gpg --dearmor -o /etc/apt/keyrings/onlyoffice.gpg
    echo "deb [signed-by=/etc/apt/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
        | tee /etc/apt/sources.list.d/onlyoffice.list
    wait_apt; apt-get update -qq
    apt-get install -y onlyoffice-desktopeditors && success "OnlyOffice installiert" || warn "OnlyOffice fehlgeschlagen"
fi

curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp \
    -o /usr/local/bin/yt-dlp && chmod +x /usr/local/bin/yt-dlp
success "yt-dlp installiert"

# ============================================================
# SCHRITT 6 — Browser
# ============================================================
step "6/10 — Browser"

echo ""
echo -e "${PURPLE}${BOLD}  Browser Wahl:${RESET}"
echo -e "  1) Zen Browser  (Firefox-Basis, Privacy — empfohlen)"
echo -e "  2) LibreWolf    (gehärteter Firefox, max. Privacy)"
echo -e "  3) Brave        (Chromium-Basis, Privacy)"
echo -e "  4) Firefox-ESR  (Standard, stabil)"
echo -e "  5) Chromium     (leicht)"
echo -e "  6) Keinen"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-6]: "${RESET})" BROWSER_CHOICE

DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
case "$BROWSER_CHOICE" in
    1)
        info "Installiere Zen Browser..."
        ZEN_URL=""
        ZEN_JSON=$(curl -sf https://api.github.com/repos/zen-browser/desktop/releases/latest 2>/dev/null)
        if [[ -n "$ZEN_JSON" ]]; then
            ZEN_URL=$(echo "$ZEN_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if a['name'].endswith('x86_64.AppImage'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)
        fi
        if [[ -n "$ZEN_URL" ]]; then
            curl -L "$ZEN_URL" -o /opt/zen-browser.AppImage
            chmod +x /opt/zen-browser.AppImage
            apt-get install -y libfuse2 2>/dev/null || true
            cat > /usr/share/applications/zen-browser.desktop << 'EOF'
[Desktop Entry]
Name=Zen Browser
Comment=Privacy-focused web browser
Exec=/opt/zen-browser.AppImage %u
Icon=firefox
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
StartupNotify=true
EOF
            DEFAULT_BROWSER_DESKTOP="zen-browser.desktop"
            success "Zen Browser installiert"
        else
            warn "Zen Browser nicht verfügbar — Fallback: Firefox-ESR"
            apt-get install -y firefox-esr
            DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
        fi ;;
    2)
        curl -fsSL https://deb.librewolf.net/keyring.gpg \
            | gpg --dearmor | tee /usr/share/keyrings/librewolf.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/librewolf.gpg arch=amd64] https://deb.librewolf.net bookworm main" \
            | tee /etc/apt/sources.list.d/librewolf.list
        wait_apt; apt-get update -qq
        apt-get install -y librewolf && success "LibreWolf installiert" || warn "LibreWolf fehlgeschlagen"
        DEFAULT_BROWSER_DESKTOP="librewolf.desktop" ;;
    3)
        curl -fsS https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
            | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" \
            | tee /etc/apt/sources.list.d/brave-browser.list
        wait_apt; apt-get update -qq; apt-get install -y brave-browser
        DEFAULT_BROWSER_DESKTOP="brave-browser.desktop"
        success "Brave installiert" ;;
    4)
        apt-get install -y firefox-esr
        DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
        success "Firefox-ESR installiert" ;;
    5)
        apt-get install -y chromium
        DEFAULT_BROWSER_DESKTOP="chromium.desktop"
        success "Chromium installiert" ;;
    *)
        warn "Kein Browser installiert" ;;
esac

# ============================================================
# SCHRITT 7 — Steam & Gaming
# ============================================================
step "7/10 — Steam & Gaming"

if ask_install "Steam"; then
    wait_apt
    apt-get install -y \
        steam steam-devices \
        libvulkan1 libvulkan1:i386 \
        vulkan-tools libgl1-mesa-dri:i386 \
        mesa-vulkan-drivers:i386 \
        gamemode 2>/dev/null || warn "Steam teilweise fehlgeschlagen"
    systemctl enable gamemoded 2>/dev/null || true
    success "Steam + GameMode installiert"

    info "Installiere Proton GE..."
    PROTON_GE_URL=""
    PROTON_GE_JSON=$(curl -sf https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>/dev/null)
    if [[ -n "$PROTON_GE_JSON" ]]; then
        PROTON_GE_URL=$(echo "$PROTON_GE_JSON" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    for a in data.get('assets', []):
        if a['name'].endswith('.tar.gz'):
            print(a['browser_download_url'])
            break
except: pass
" 2>/dev/null)
    fi
    if [[ -n "$PROTON_GE_URL" ]]; then
        curl -L "$PROTON_GE_URL" -o /tmp/proton-ge.tar.gz
        mkdir -p "$TARGET_HOME/.steam/root/compatibilitytools.d"
        tar -xzf /tmp/proton-ge.tar.gz -C "$TARGET_HOME/.steam/root/compatibilitytools.d/"
        rm -f /tmp/proton-ge.tar.gz
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.steam/root/compatibilitytools.d/"
        success "Proton GE installiert"
    else
        warn "Proton GE URL nicht ermittelt — manuell installieren"
    fi
fi

# ============================================================
# SCHRITT 8 — Performance & Sicherheit
# ============================================================
step "8/10 — Performance & Sicherheit"

wait_apt
apt-get install -y zram-tools earlyoom ufw
command -v tlp &>/dev/null || apt-get install -y tlp tlp-rdw

cat > /etc/default/zramswap << 'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

# Initramfs auf lz4 umstellen für schnelleren Boot
if [[ -f /etc/initramfs-tools/initramfs.conf ]]; then
    sed -i 's/^COMPRESS=.*/COMPRESS=lz4/' /etc/initramfs-tools/initramfs.conf
    update-initramfs -u 2>/dev/null || true
fi

systemctl enable zramswap earlyoom tlp 2>/dev/null || true

cat > /etc/sysctl.d/99-snowfox.conf << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=3
vm.dirty_ratio=6
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv6.conf.all.use_tempaddr=2
net.ipv6.conf.default.use_tempaddr=2
EOF

# root-Partition auf noatime setzen für weniger I/O-Overhead
info "Optimiere fstab (noatime)..."
sed -i 's/errors=remount-ro/errors=remount-ro,noatime/g' /etc/fstab

grep -q "tmpfs /tmp" /etc/fstab || \
    echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0" >> /etc/fstab

ufw default deny incoming  2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw --force enable         2>/dev/null || true
success "ufw Firewall aktiviert"

mkdir -p /etc/NetworkManager/conf.d

# managed=true — wichtig damit WiFi von NetworkManager verwaltet wird
cat > /etc/NetworkManager/NetworkManager.conf << 'EOF'
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true
EOF

cat > /etc/NetworkManager/conf.d/99-snowfox-privacy.conf << 'EOF'
[device]
wifi.scan-rand-mac-address=yes
[connection]
wifi.cloned-mac-address=stable-privacy
ethernet.cloned-mac-address=stable-privacy
EOF

cat > /etc/NetworkManager/conf.d/99-snowfox-wifi-powersave.conf << 'EOF'
[connection]
wifi.powersave=2 # 2 = off, 3 = on (default)
EOF

mkdir -p /etc/systemd/resolved.conf.d
cat > /etc/systemd/resolved.conf.d/snowfox.conf << 'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=8.8.8.8
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
EOF
systemctl enable systemd-resolved irqbalance 2>/dev/null || true

for svc in avahi-daemon cups-browsed ModemManager colord; do
    systemctl disable "$svc" 2>/dev/null || true
done

# NetworkManager-wait-online deaktivieren, um Boot-Verzögerung zu vermeiden
systemctl mask NetworkManager-wait-online.service 2>/dev/null || true
systemctl mask systemd-networkd-wait-online.service 2>/dev/null || true

sed -i 's/#HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf

success "Performance & Sicherheit optimiert"

# ============================================================
# SCHRITT 9 — Plymouth & Branding
# ============================================================
step "9/10 — Plymouth & Boot-Screen"

apt-get install -y plymouth plymouth-themes 2>/dev/null || true
PLYMOUTH_DIR="/usr/share/plymouth/themes/snowfox"
mkdir -p "$PLYMOUTH_DIR"

cat > "$PLYMOUTH_DIR/snowfox.plymouth" << 'EOF'
[Plymouth Theme]
Name=SnowFox
Description=SnowFoxOS Boot Theme
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/snowfox
ScriptFile=/usr/share/plymouth/themes/snowfox/snowfox.script
EOF

cat > "$PLYMOUTH_DIR/snowfox.script" << 'EOF'
wallpaper_image = Image("background.png");
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
wallpaper_sprite = Sprite(wallpaper_image);
wallpaper_sprite.SetX(screen_width / 2 - wallpaper_image.GetWidth() / 2);
wallpaper_sprite.SetY(screen_height / 2 - wallpaper_image.GetHeight() / 2);
logo_image = Image("logo.png");
logo_sprite = Sprite(logo_image);
logo_sprite.SetX(screen_width / 2 - logo_image.GetWidth() / 2);
logo_sprite.SetY(screen_height / 2 - logo_image.GetHeight() / 2);
EOF

[[ -f "$SCRIPT_DIR/assets/fuchs.png" ]] && \
    convert "$SCRIPT_DIR/assets/fuchs.png" -resize 200x200 "$PLYMOUTH_DIR/logo.png" 2>/dev/null || true
convert -size 1920x1080 xc:#0f0f0f "$PLYMOUTH_DIR/background.png" 2>/dev/null || true
# -R baut initramfs direkt nach theme-Wechsel neu
plymouth-set-default-theme -R snowfox 2>/dev/null || { plymouth-set-default-theme snowfox 2>/dev/null || true; update-initramfs -u 2>/dev/null || true; }

success "Boot-Screen bereit"

# ============================================================
# SCHRITT 10 — Konfiguration & Abschluss
# ============================================================
step "10/10 — Konfiguration & Finishing"

CONFIG_DIR="$TARGET_HOME/.config"
mkdir -p "$CONFIG_DIR/neofetch"
mkdir -p "$TARGET_HOME/Pictures/wallpapers"

# ── Distro-Identität ─────────────────────────────────────────
# /etc/os-release: bestimmt was neofetch, fastfetch usw. anzeigen
cat > /etc/os-release << 'EOF'
PRETTY_NAME="SnowFoxOS 2.1"
NAME="SnowFoxOS"
VERSION="2.1"
VERSION_ID="2.1"
ID=snowfoxos
ID_LIKE=debian
HOME_URL="https://github.com/Xr7-Code/SnowFoxOS-v2-i3"
ANSI_COLOR="0;35"
EOF

# /etc/lsb-release — wird von manchen Tools gelesen
cat > /etc/lsb-release << 'EOF'
DISTRIB_ID=SnowFoxOS
DISTRIB_RELEASE=2.1
DISTRIB_CODENAME=fox
DISTRIB_DESCRIPTION="SnowFoxOS 2.1"
EOF

echo "snowfox"                  > /etc/hostname
echo "SnowFoxOS 2.1"            > /etc/issue
echo "SnowFoxOS 2.1 \n \l"      > /etc/issue.net
hostname snowfox 2>/dev/null || true

success "Distro-Identität auf SnowFoxOS gesetzt"

# ── Dark Mode & Theme Aktivierung ────────────────────────────
info "Aktiviere Arc-Dark Design & Papirus Icons..."

# Verzeichnisse erstellen
mkdir -p "$CONFIG_DIR/xsettingsd"

# GTK3/4 Konfiguration
for version in "3.0" "4.0"; do
    mkdir -p "$CONFIG_DIR/gtk-$version"
    cat > "$CONFIG_DIR/gtk-$version/settings.ini" << GEOF
[Settings]
gtk-theme-name=Arc-Dark
gtk-icon-theme-name=Papirus-Dark
gtk-font-name=Inter 10
gtk-cursor-theme-name=Adwaita
gtk-application-prefer-dark-theme=1
GEOF
done

# GTK2 Konfiguration
cat > "$TARGET_HOME/.gtkrc-2.0" << G2EOF
include "/usr/share/themes/Arc-Dark/gtk-2.0/gtkrc"
gtk-theme-name="Arc-Dark"
gtk-icon-theme-name="Papirus-Dark"
gtk-font-name="Inter 10"
G2EOF

# xsettingsd (wichtig für i3/X11 Apps)
cat > "$CONFIG_DIR/xsettingsd/xsettingsd.conf" << XEOF
Net/ThemeName "Arc-Dark"
Net/IconThemeName "Papirus-Dark"
Gtk/CursorThemeName "Adwaita"
XEOF

# ── Qt Styling (Qt5 & Qt6) ───────────────────────────────────
info "Konfiguriere Qt-Styling für einheitliches Design..."
mkdir -p "$CONFIG_DIR/qt5ct" "$CONFIG_DIR/qt6ct"

cat > "$CONFIG_DIR/qt5ct/qt5ct.conf" << Q5EOF
[Appearance]
style=gtk2
Q5EOF

cat > "$CONFIG_DIR/qt6ct/qt6ct.conf" << Q6EOF
[Appearance]
style=adwaita-dark
Q6EOF

# ── Neofetch Konfiguration ───────────────────────────────────
cat > "$CONFIG_DIR/neofetch/config.conf" << EOF

print_info() {
    info title
    info underline
    info "OS" distro
    info "Kernel" kernel
    info "Uptime" uptime
    info "Packages" packages
    info "Shell" shell
    info "Resolution" resolution
    info "WM" wm
    info "CPU" cpu
    info "GPU" gpu
    info "Memory" memory # Zeigt RAM in MB an
}
image_backend="ascii"
ascii_distro=""
image_source="${TARGET_HOME}/.config/neofetch/snowfox.txt"
ascii_colors=(5 7)
EOF

cat > "$CONFIG_DIR/neofetch/snowfox.txt" << 'ASCIIEOF'
                .... .....-
   ..       ... ..- ........
   :@..........@-:...........=
   ::-...........: :...........
   ............... -::: ........
   :..........::::: - :.:........
   :..::@:...@...::     .........
    ::.... .:.: ................:-
  :.   : :.@. ::...............::
  .:......::::..............:.::-
   ..:......................::::
    :...::................::::-
      ::.............::::::::
        :::::::::::::::--:
              ----------
ASCIIEOF

# Repo-Configs kopieren
if [[ -d "$SCRIPT_DIR/configs" ]]; then
    cp -r "$SCRIPT_DIR/configs/"* "$CONFIG_DIR/"
    success "Konfigurationsdateien kopiert"

    # Visuelles Polishing: Rofi Icons & Picom Schatten
    info "Wende visuelle Optimierungen an (Icons & Schatten)..."
    sed -i 's/show-icons: .*/show-icons: false;/' "$CONFIG_DIR/rofi/config.rasi" 2>/dev/null
    sed -i 's/icon-theme: .*/icon-theme: "Papirus-Dark";/' "$CONFIG_DIR/rofi/config.rasi" 2>/dev/null
    
    if [[ -f "$CONFIG_DIR/picom/picom.conf" ]]; then
        sed -i 's/backend = .*/backend = "glx";/' "$CONFIG_DIR/picom/picom.conf"
        sed -i 's/shadow = .*/shadow = true;/' "$CONFIG_DIR/picom/picom.conf"
        # Polybar explizit von der Shadow-Exclusion Liste entfernen, falls vorhanden
        sed -i '/shadow-exclude = \[/,/\];/ s/"class_g = .Polybar."//g' "$CONFIG_DIR/picom/picom.conf"
        sed -i '/shadow-exclude = \[/,/\];/ s/"class_g = .Rofi."//g' "$CONFIG_DIR/picom/picom.conf"
        # Wintypes-Overrides anpassen, damit Panels (Docks) und Menüs Schatten werfen
        sed -i 's/dock = { shadow = false; }/dock = { shadow = true; }/g' "$CONFIG_DIR/picom/picom.conf"
    fi
else
    warn "configs/-Verzeichnis nicht gefunden"
fi

# Skripte ausführbar machen
find "$CONFIG_DIR" -name "*.sh" -exec chmod +x {} +

# Standard-Wallpaper initialisieren
[[ -d "$SCRIPT_DIR/wallpapers" ]] && \
    cp -r "$SCRIPT_DIR/wallpapers/." "$TARGET_HOME/Pictures/wallpapers/"

DEFAULT_WP=$(ls "$TARGET_HOME/Pictures/wallpapers" 2>/dev/null | grep -iE ".jpg$|.png$|.webp$|.jpeg$" | head -n 1)
if [[ -n "$DEFAULT_WP" ]]; then
    echo "#!/bin/sh" > "$TARGET_HOME/.fehbg"
    echo "feh --bg-fill '$TARGET_HOME/Pictures/wallpapers/$DEFAULT_WP'" >> "$TARGET_HOME/.fehbg"
    chmod +x "$TARGET_HOME/.fehbg"
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.fehbg"
    info "Standard-Wallpaper gesetzt: $DEFAULT_WP"
fi

# Polybar modules-right dynamisch anpassen
POLYBAR_CONF="$CONFIG_DIR/polybar/config.ini"
if [[ -f "$POLYBAR_CONF" ]]; then
    if [[ "$IS_LAPTOP" == "true" ]]; then
        # Hardware-Pfade für Akku und Backlight erkennen
        BAT_NAME=$(ls /sys/class/power_supply/ | grep -E "BAT|battery" | head -1)
        [[ -n "$BAT_NAME" ]] && sed -i "s/battery = BAT1/battery = $BAT_NAME/" "$POLYBAR_CONF"
        
        BL_NAME=$(ls /sys/class/backlight/ | head -1)
        [[ -n "$BL_NAME" ]] && sed -i "s/card = intel_backlight/card = $BL_NAME/" "$POLYBAR_CONF"

        success "Polybar: Akku + Helligkeit aktiviert (Laptop erkannt)"
    else
        # Auf Desktops Akku und Backlight aus der Leiste entfernen
        sed -i 's/backlight battery//' "$POLYBAR_CONF"
    fi
fi

if [[ -d "$SCRIPT_DIR/configs/modprobe" ]]; then
    cp "$SCRIPT_DIR/configs/modprobe/amdgpu.conf" /etc/modprobe.d/ 2>/dev/null || true
    cp "$SCRIPT_DIR/configs/modprobe/nvidia.conf"  /etc/modprobe.d/ 2>/dev/null || true
    update-initramfs -u 2>/dev/null || true
    success "modprobe Configs installiert"
fi

[[ -f "$SCRIPT_DIR/configs/powermenu.sh" ]] && \
    cp "$SCRIPT_DIR/configs/powermenu.sh" /usr/local/bin/snowfox-powermenu && \
    chmod +x /usr/local/bin/snowfox-powermenu

[[ -f "$SCRIPT_DIR/snowfox" ]] && \
    cp "$SCRIPT_DIR/snowfox" /usr/local/bin/snowfox && chmod +x /usr/local/bin/snowfox

[[ -f "$SCRIPT_DIR/snowfox-greeting.sh" ]] && \
    cp "$SCRIPT_DIR/snowfox-greeting.sh" /usr/local/bin/snowfox-greeting && \
    chmod +x /usr/local/bin/snowfox-greeting

grep -q "snowfox-greeting" "$TARGET_HOME/.bashrc" 2>/dev/null || \
    printf '\n# SnowFoxOS Greeting\n[[ -x /usr/local/bin/snowfox-greeting ]] && snowfox-greeting\n' \
    >> "$TARGET_HOME/.bashrc"

# Standard-Dateimanager
echo ""
echo -e "${PURPLE}${BOLD}  Standard-Dateimanager:${RESET}"
echo -e "  1) Thunar  (grafisch, empfohlen)"
echo -e "  2) Nautilus (GNOME)"
echo -e "  3) MC      (Terminal)"
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-3]: "${RESET})" DEFAULT_FM
case "$DEFAULT_FM" in
    2) DEFAULT_FM_DESKTOP="org.gnome.Nautilus.desktop" ;;
    3) DEFAULT_FM_DESKTOP="mc.desktop" ;;
    *) DEFAULT_FM_DESKTOP="thunar.desktop" ;;
esac

# Standard-Texteditor
echo ""
echo -e "${PURPLE}${BOLD}  Standard-Texteditor:${RESET}"
echo -e "  1) Mousepad (Standard)"
echo -e "  2) VSCodium"
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-2]: "${RESET})" DEFAULT_EDITOR
case "$DEFAULT_EDITOR" in
    2) DEFAULT_EDITOR_DESKTOP="codium.desktop" ;;
    *) DEFAULT_EDITOR_DESKTOP="mousepad.desktop" ;;
esac

cat > "$CONFIG_DIR/mimeapps.list" << MEOF
[Default Applications]
inode/directory=$DEFAULT_FM_DESKTOP
inode/directory=thunar.desktop
text/plain=$DEFAULT_EDITOR_DESKTOP
text/x-python=$DEFAULT_EDITOR_DESKTOP
text/x-shellscript=$DEFAULT_EDITOR_DESKTOP
application/x-shellscript=$DEFAULT_EDITOR_DESKTOP
x-scheme-handler/http=$DEFAULT_BROWSER_DESKTOP
x-scheme-handler/https=$DEFAULT_BROWSER_DESKTOP
text/html=$DEFAULT_BROWSER_DESKTOP
application/xhtml+xml=$DEFAULT_BROWSER_DESKTOP
application/pdf=$DEFAULT_BROWSER_DESKTOP
image/png=ristretto.desktop
image/jpeg=ristretto.desktop
image/gif=ristretto.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
audio/mpeg=mpv.desktop
application/zip=org.gnome.FileRoller.desktop
application/x-tar=org.gnome.FileRoller.desktop
MEOF
success "Standard-Anwendungen gesetzt"

# Berechtigungen — nach allen Kopieroperationen
chown -R "$TARGET_USER:$TARGET_USER" "$CONFIG_DIR"
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/Pictures/wallpapers"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.gtkrc-2.0"
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.bash_profile"

# DKMS-Hooks wiederherstellen
for hook in "${DKMS_HOOKS[@]}"; do
    [[ -f "${hook}.snowfox-bak" ]] && mv "${hook}.snowfox-bak" "$hook"
done
info "DKMS-Hooks wiederhergestellt"

# ============================================================
# Fertig!
# ============================================================
echo -e "${PURPLE}${BOLD}"
echo "  ███████╗███╗  ██╗ ██████╗ ██╗    ██╗███████╗ ██████╗ ██╗  ██╗"
echo "  ██╔════╝████╗ ██║██╔═══██╗██║    ██║██╔════╝██╔═══██╗╚██╗██╔╝"
echo "  ███████╗██╔██╗██║██║   ██║██║ █╗ ██║█████╗  ██║   ██║ ╚███╔╝ "
echo "  ╚════██║██║╚████║██║   ██║██║███╗██║██╔══╝  ██║   ██║ ██╔██╗ "
echo "  ███████║██║ ╚███║╚██████╔╝╚███╔███╔╝██║     ╚██████╔╝██╔╝╚██╗"
echo "  ╚══════╝╚═╝  ╚══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝"
echo -e "${RESET}"
success "SnowFoxOS v2.1 erfolgreich installiert!"
warn "Bitte neu starten: sudo reboot"
