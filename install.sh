#!/bin/bash
# ============================================================
#  SnowFoxOS v2.1 — Installer
#  Basis: Debian 12 (Bookworm) minimal
#  Desktop: i3 + Polybar + Rofi + Dunst + i3lock
#  Ausführen: sudo bash install.sh
# ============================================================

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

wait_apt() {
    local i=0
    while fuser /var/lib/dpkg/lock-frontend /var/lib/apt/lists/lock > /dev/null 2>&1; do
        [[ $i -eq 0 ]] && info "Warte auf apt-Lock..."
        sleep 2; i=$((i+1))
        [[ $i -gt 60 ]] && error "apt-Lock nach 120s nicht frei"
    done
}

install_themes() {
    local TARGET_HOME="$1"
    local TARGET_USER="$2"

    # Build-Abhängigkeiten für Catppuccin Theme
    info "Installiere Build-Abhängigkeiten für GTK-Theme..."
    apt-get install -y sassc libglib2.0-dev

    # --- GTK Theme: Catppuccin ---
    info "Installiere Catppuccin GTK Theme (Mocha, Lavender accent)..."
    git clone --depth=1 https://github.com/catppuccin/gtk.git /tmp/catppuccin-gtk 2>/dev/null
    if [[ -d /tmp/catppuccin-gtk ]]; then
        cd /tmp/catppuccin-gtk || error "Konnte nicht in /tmp/catppuccin-gtk wechseln."
        ./install.sh -t mocha -a lavender -s standard 2>/dev/null || true
        cd / || error "Konnte nicht nach / wechseln."
        rm -rf /tmp/catppuccin-gtk
        success "Catppuccin-Mocha-Standard-Lavender Theme installiert"
    else
        warn "Catppuccin GTK Theme nicht verfügbar — nutze Adwaita-dark als Fallback"
    fi

    # --- Papirus Icon Theme ---
    info "Installiere und konfiguriere Papirus Icon Theme (Violet als Akzent)..."
    apt-get install -y papirus-icon-theme
    wget -qO- https://raw.githubusercontent.com/PapirusDevelopmentTeam/papirus-folders/master/papirus-folders | sudo tee /usr/local/bin/papirus-folders > /dev/null
    chmod +x /usr/local/bin/papirus-folders
    /usr/local/bin/papirus-folders -C violet -t Papirus-Dark
    success "Papirus-Dark Icons installiert und auf Violet gesetzt"

    # --- Cursor Theme: Adwaita (Gnome Default) ---
    info "Setze Adwaita Cursor als Standard..."
    # Adwaita ist der Standard-Gnome-Cursor und sollte auf Debian-Systemen verfügbar sein.
    sudo mkdir -p /usr/share/icons/default
    sudo tee /usr/share/icons/default/index.theme > /dev/null << 'EOF'
[Icon Theme]
Inherits=Adwaita
EOF
    success "Adwaita Cursor als Standard gesetzt"

    # Theme ermitteln
    local GTK_THEME="Catppuccin-Mocha-Standard-Lavender"
    # Fallback, falls Catppuccin-Installation fehlschlägt
    [[ ! -d "/usr/share/themes/Catppuccin-Mocha-Standard-Lavender" ]] && GTK_THEME="Adwaita-dark"
    local ICON_THEME="Papirus-Dark"
    local CURSOR_THEME="Adwaita"

    # GTK2 Config
    cat > "$TARGET_HOME/.gtkrc-2.0" << GEOF
gtk-theme-name="${GTK_THEME}"
gtk-icon-theme-name="${ICON_THEME}"
gtk-font-name="Inter 10"
gtk-cursor-theme-name="${CURSOR_THEME}"
gtk-cursor-theme-size=24
GEOF

    # GTK3 Config
    mkdir -p "$TARGET_HOME/.config/gtk-3.0"
    cat > "$TARGET_HOME/.config/gtk-3.0/settings.ini" << GEOF
[Settings]
gtk-theme-name=${GTK_THEME}
gtk-icon-theme-name=${ICON_THEME}
gtk-font-name=Inter 10
gtk-cursor-theme-name=${CURSOR_THEME}
gtk-cursor-theme-size=24
gtk-application-prefer-dark-theme=1
gtk-enable-event-sounds=0
gtk-enable-input-feedback-sounds=0
GEOF

    # GTK4 Config
    mkdir -p "$TARGET_HOME/.config/gtk-4.0"
    cat > "$TARGET_HOME/.config/gtk-4.0/settings.ini" << GEOF
[Settings]
gtk-theme-name=${GTK_THEME}
gtk-icon-theme-name=${ICON_THEME}
gtk-font-name=Inter 10
gtk-cursor-theme-name=${CURSOR_THEME}
gtk-application-prefer-dark-theme=1
GEOF

    # xsettingsd Config
    mkdir -p "$TARGET_HOME/.config/xsettingsd"
    cat > "$TARGET_HOME/.config/xsettingsd/xsettingsd.conf" << GEOF
Net/ThemeName "${GTK_THEME}"
Net/IconThemeName "${ICON_THEME}"
Gtk/CursorThemeName "${CURSOR_THEME}"
Gtk/CursorThemeSize 24
Gtk/FontName "Inter 10"
Net/EnableEventSounds 0
Net/EnableInputFeedbackSounds 0
Xft/Antialias 1
Xft/Hinting 1
Xft/HintStyle "hintslight"
Xft/RGBA "rgb"
GEOF

    # Qt Config
    mkdir -p "$TARGET_HOME/.config/qt5ct" "$TARGET_HOME/.config/qt6ct"
    cat > "$TARGET_HOME/.config/qt5ct/qt5ct.conf" << 'QEOF'
[Appearance]
style=gtk2
icon_theme=Papirus-Dark
QEOF
    cat > "$TARGET_HOME/.config/qt6ct/qt6ct.conf" << 'QEOF'
[Appearance]
style=gtk2
icon_theme=Papirus-Dark
QEOF

    chown -R "$TARGET_USER:$TARGET_USER" \
        "$TARGET_HOME/.gtkrc-2.0" \
        "$TARGET_HOME/.config/gtk-3.0" \
        "$TARGET_HOME/.config/gtk-4.0" \
        "$TARGET_HOME/.config/xsettingsd" \
        "$TARGET_HOME/.config/qt5ct" \
        "$TARGET_HOME/.config/qt6ct" 2>/dev/null || true

    # .xinitrc mit dem korrekten Theme aktualisieren
    sed -i "s|GTK_THEME_PLACEHOLDER|${GTK_THEME}|" "$TARGET_HOME/.xinitrc" 2>/dev/null || true
    chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc" 2>/dev/null || true

    success "Theme-System vollständig konfiguriert: $GTK_THEME + $ICON_THEME + $CURSOR_THEME"
}

# ── Root-Check ───────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    error "Bitte mit sudo ausführen: sudo bash install.sh"
fi

if [[ ! -f /etc/debian_version ]] || ! grep -q "^12\." /etc/debian_version; then
    warn "Dieses Script ist für Debian 12 (Bookworm) optimiert."
fi

# ── Phase 0: Installations-Ziel ──────────────────────────────
step "0/11 — Installations-Modus"
echo -e "Wie möchtest du SnowFoxOS installieren?"
echo -e "1) ${BOLD}Aktuelles System konfigurieren${RESET} (Du hast Debian schon installiert)"
echo -e "2) ${BOLD}Automatische Installation auf ausgewählter Festplatte${RESET} (Alle Daten werden gelöscht!)"
echo -e "3) ${BOLD}Manuelle Partitionierung & Installation${RESET} (Für Dual-Boot oder spezifische Partitionen)"
echo ""
read -rp "Auswahl [1-3]: " INSTALL_MODE

if [[ "$INSTALL_MODE" == "2" ]];
then
    info "Standalone-Installer gestartet."
    lsblk -p -n -o NAME,SIZE,MODEL | grep -v "loop"
    read -rp "Ziel-Laufwerk wählen (z.B. /dev/sda): " TARGET_DISK
    [[ ! -b "$TARGET_DISK" ]] && error "Ungültiges Laufwerk!"
    warn "ALLE DATEN AUF $TARGET_DISK WERDEN GELÖSCHT!"
    read -rp "Sicher? [JA/nein]: " CONFIRM
    [[ "$CONFIRM" != "JA" ]] && error "Abgebrochen."
    info "Partitioniere $TARGET_DISK..."
    parted -s "$TARGET_DISK" mklabel gpt
    parted -s "$TARGET_DISK" mkpart primary fat32 1MiB 513MiB
    parted -s "$TARGET_DISK" set 1 esp on
    parted -s "$TARGET_DISK" mkpart primary ext4 513MiB 100%
    mkfs.vfat -F32 "${TARGET_DISK}1" 2>/dev/null || mkfs.vfat -F32 "${TARGET_DISK}p1"
    mkfs.ext4 -F "${TARGET_DISK}2" 2>/dev/null || mkfs.ext4 -F "${TARGET_DISK}p2"
    mkdir -p /mnt/target
    mount "${TARGET_DISK}2" /mnt/target 2>/dev/null || mount "${TARGET_DISK}p2" /mnt/target
    mkdir -p /mnt/target/boot/efi
    mount "${TARGET_DISK}1" /mnt/target/boot/efi 2>/dev/null || mount "${TARGET_DISK}p1" /mnt/target/boot/efi
    info "Kopiere System-Dateien..."
    rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /mnt/target/
    read -rp "Neuer Benutzername: " TARGET_USER
    read -sp "Passwort für $TARGET_USER: " USER_PASS; echo ""
    read -sp "Root-Passwort: " ROOT_PASS; echo ""
    
    mount --bind /dev /mnt/target/dev
    mount --bind /proc /mnt/target/proc
    mount --bind /sys /mnt/target/sys
    
    # FIX: Exportiere die Variablen für die Chroot-Umgebung
    export TARGET_USER USER_PASS ROOT_PASS TARGET_DISK
    
    # FIX: 'EOF' maskiert, damit die Variablen sauber im chroot aufgelöst werden
    chroot /mnt/target /bin/bash << 'EOF'
useradd -m -s /bin/bash "${TARGET_USER}"
echo "${TARGET_USER}:${USER_PASS}" | chpasswd
echo "root:${ROOT_PASS}" | chpasswd
usermod -aG sudo "${TARGET_USER}"
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=SnowFoxOS --recheck
grub-install --target=i386-pc "${TARGET_DISK}" || true
update-grub
EOF
    success "Basis-Installation abgeschlossen."
    TARGET_HOME="/mnt/target/home/${TARGET_USER}"

elif [[ "$INSTALL_MODE" == "3" ]];
then
    info "Manuelle Partitionierung gestartet."
    lsblk -p -n -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v "loop"
    read -rp "Ziel-Laufwerk für GRUB (z.B. /dev/sda): " TARGET_DISK_GRUB
    [[ ! -b "$TARGET_DISK_GRUB" ]] && error "Ungültiges Laufwerk für GRUB!"
    read -rp "Root-Partition (z.B. /dev/sda2): " ROOT_PARTITION
    [[ ! -b "$ROOT_PARTITION" ]] && error "Ungültige Root-Partition!"
    read -rp "EFI-Partition (z.B. /dev/sda1, leer lassen für BIOS/MBR): " EFI_PARTITION
    FORMAT_EFI="n"
    [[ -n "$EFI_PARTITION" ]] && read -rp "EFI formatieren? [j/N]: " FORMAT_EFI
    warn "Die Root-Partition $ROOT_PARTITION wird formatiert!"
    read -rp "Sicher? [JA/nein]: " CONFIRM
    [[ "$CONFIRM" != "JA" ]] && error "Abgebrochen."
    mkfs.ext4 -F "$ROOT_PARTITION" || error "Fehler beim Formatieren."
    [[ -n "$EFI_PARTITION" && "$FORMAT_EFI" =~ ^[jJ]$ ]] && mkfs.vfat -F32 "$EFI_PARTITION"
    mkdir -p /mnt/target
    mount "$ROOT_PARTITION" /mnt/target || error "Fehler beim Mounten."
    [[ -n "$EFI_PARTITION" ]] && { mkdir -p /mnt/target/boot/efi; mount "$EFI_PARTITION" /mnt/target/boot/efi; }
    info "Kopiere System-Dateien..."
    rsync -aAXv --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /mnt/target/
    read -rp "Neuer Benutzername: " TARGET_USER
    read -sp "Passwort für $TARGET_USER: " USER_PASS; echo ""
    read -sp "Root-Passwort: " ROOT_PASS; echo ""
    
    mount --bind /dev /mnt/target/dev
    mount --bind /proc /mnt/target/proc
    mount --bind /sys /mnt/target/sys
    
    # FIX: Exportiere alle notwendigen Variablen
    export TARGET_USER USER_PASS ROOT_PASS EFI_PARTITION TARGET_DISK_GRUB
    
    # FIX: 'EOF' maskiert, um leere Variablen im chroot zu verhindern
    chroot /mnt/target /bin/bash << 'EOF'
useradd -m -s /bin/bash "${TARGET_USER}"
echo "${TARGET_USER}:${USER_PASS}" | chpasswd
echo "root:${ROOT_PASS}" | chpasswd
usermod -aG sudo "${TARGET_USER}"
if [ -n "${EFI_PARTITION}" ];
then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=SnowFoxOS --recheck || true
else
    grub-install --target=i386-pc "${TARGET_DISK_GRUB}" || true
fi
update-grub
EOF
    success "Basis-Installation abgeschlossen."
    TARGET_HOME="/mnt/target/home/${TARGET_USER}"
fi

if [[ "$INSTALL_MODE" == "1" ]];
then
    TARGET_USER="${SUDO_USER:-$(logname 2>/dev/null || echo '')}"
    [[ -z "$TARGET_USER" || "$TARGET_USER" == "root" ]] && read -rp "Benutzername: " TARGET_USER
    TARGET_HOME="/home/$TARGET_USER"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ ! -d "$TARGET_HOME" ]] && error "Home $TARGET_HOME nicht gefunden"
info "Installiere für: ${BOLD}$TARGET_USER${RESET}"
sleep 1

# ============================================================
# SCHRITT 1 — System & Repositories
# ============================================================
step "1/11 — System aktualisieren"

DKMS_HOOKS=(/etc/kernel/postinst.d/dkms /etc/kernel/prerm.d/dkms /usr/lib/kernel/install.d/50-dkms.install)
for hook in "${DKMS_HOOKS[@]}"; do [[ -f "$hook" ]] && mv "$hook" "${hook}.snowfox-bak"; done

systemctl disable apt-daily.service apt-daily.timer apt-daily-upgrade.service apt-daily-upgrade.timer 2>/dev/null || true
systemctl stop apt-daily.service apt-daily-upgrade.service 2>/dev/null || true

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
apt-get upgrade -y sassc libglib2.0-dev # sassc und libglib2.0-dev für Catppuccin
apt-get install -y \
    curl wget git unzip build-essential ca-certificates aria2 fzf lz4 gnupg \
    pciutils usbutils htop btop neofetch irqbalance bash-completion \
    xdg-utils xdg-user-dirs rfkill iw wireless-tools imagemagick bc \
    xorg xinit x11-utils x11-xserver-utils xclip xdotool dbus-x11 lm-sensors \
    librsvg2-bin libglib2.0-bin

sudo -u "$TARGET_USER" xdg-user-dirs-update
success "System aktualisiert"

info "Prüfe CPU-Kompatibilität für x64v3..."
grep -q "avx2" /proc/cpuinfo || error "CPU unterstützt kein AVX2."

apt-get install -y --no-install-recommends dkms libdw-dev clang lld llvm

mkdir -p /etc/apt/keyrings
wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor --yes -o /etc/apt/keyrings/xanmod-archive-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/xanmod-archive-keyring.gpg] http://deb.xanmod.org bookworm main" > /etc/apt/sources.list.d/xanmod-release.list
wait_apt; apt-get update -qq; wait_apt
DEBIAN_FRONTEND=noninteractive apt-get install -y linux-xanmod-lts-x64v3
XANMOD_EXIT=$?

if [[ $XANMOD_EXIT -eq 0 ]]; then
    if [[ -f /etc/default/grub ]]; then
        GRUB_PARAMS="quiet splash"
        lspci | grep -qi nvidia && GRUB_PARAMS="$GRUB_PARAMS nvidia-drm.modeset=1 nvidia.NVreg_PreserveVideoMemoryAllocations=1"
        { lspci | grep -qi nvidia && lspci | grep -qi amd; } && GRUB_PARAMS="$GRUB_PARAMS amd_iommu=on iommu=pt"
        sed -i "s/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT=\"$GRUB_PARAMS\"/" /etc/default/grub
        sed -i 's/GRUB_TIMEOUT=.*/GRUB_TIMEOUT=1/' /etc/default/grub
        sed -i '/GRUB_DISABLE_OS_PROBER/d' /etc/default/grub
        echo "GRUB_DISABLE_OS_PROBER=false" >> /etc/default/grub
    fi
    XANMOD_VER=$(ls /lib/modules 2>/dev/null | grep xanmod-lts | sort -V | tail -1)
    [[ -n "$XANMOD_VER" ]] && grub-set-default "Advanced options for SnowFoxOS GNU/Linux>SnowFoxOS GNU/Linux, with Linux $XANMOD_VER" 2>/dev/null || true
    update-grub 2>/dev/null || true
    success "XanMod LTS Kernel installiert"
else
    warn "XanMod fehlgeschlagen — Installation wird fortgesetzt"
fi

# ============================================================
# SCHRITT 2 — Hardware-Erkennung & Treiber
# ============================================================
step "2/11 — Hardware-Analyse & Treiber"

IS_LAPTOP=false
[[ "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true
ls /sys/class/power_supply/BAT* &>/dev/null && IS_LAPTOP=true

grep -m1 "vendor_id" /proc/cpuinfo | grep -qi "AuthenticAMD" \
    && apt-get install -y amd64-microcode \
    || apt-get install -y intel-microcode

GPU_INFO=$(lspci | grep -iE 'vga|3d|display')
HAS_NVIDIA=false; HAS_AMD=false; HAS_INTEL=false
echo "$GPU_INFO" | grep -qi "nvidia" && HAS_NVIDIA=true
echo "$GPU_INFO" | grep -qi "amd"    && HAS_AMD=true
echo "$GPU_INFO" | grep -qi "intel"  && HAS_INTEL=true

if $HAS_NVIDIA; then
    apt-get install -y clang-19 lld-19 2>/dev/null || apt-get install -y clang lld || true
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
    wait_apt; apt-get update -qq
    apt-get purge -y nvidia-driver nvidia-kernel-dkms 2>/dev/null || true
    wait_apt
    apt-get install -y cuda-drivers-580 libvulkan1 libvulkan1:i386 nvidia-vulkan-icd nvidia-vulkan-icd:i386

    if $HAS_AMD; then
        ENVY_URL=$(curl -sf https://api.github.com/repos/bayasdev/envycontrol/releases/latest 2>/dev/null \
            | python3 -c "import sys,json; [print(a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[]) if a['name'].endswith('.deb')]" 2>/dev/null | head -1)
        if [[ -n "$ENVY_URL" ]]; then
            curl -L "$ENVY_URL" -o /tmp/envycontrol.deb
            dpkg -i /tmp/envycontrol.deb 2>/dev/null || apt-get -f install -y
            rm -f /tmp/envycontrol.deb
        fi
        envycontrol -s hybrid 2>/dev/null || true
        cat > /etc/X11/xorg.conf.d/20-nvidia-hybrid.conf << 'XEOF'
Section "OutputClass"
    Identifier "nvidia"
    MatchDriver "nvidia-drm"
    Driver "nvidia"
    Option "PrimaryGPU" "yes"
EndSection
Section "OutputClass"
    Identifier "amdgpu"
    MatchDriver "amdgpu"
    Driver "amdgpu"
    Option "TearFree" "true"
EndSection
XEOF
    fi

    XANMOD_KERNEL=$(ls /lib/modules 2>/dev/null | grep xanmod | sort -V | tail -1)
    NVIDIA_VER=$(ls /var/lib/dkms/nvidia/ 2>/dev/null | sort -V | tail -1)
    [[ -n "$XANMOD_KERNEL" && -n "$NVIDIA_VER" ]] && \
        dkms install nvidia/"$NVIDIA_VER" -k "$XANMOD_KERNEL" 2>/dev/null || true
    success "NVIDIA Stack installiert"
elif $HAS_AMD; then
    apt-get install -y firmware-amd-graphics mesa-vulkan-drivers mesa-va-drivers
    success "AMD Stack installiert"
elif $HAS_INTEL; then
    apt-get install -y intel-media-va-driver-non-free i965-va-driver 2>/dev/null || true
    success "Intel Stack installiert"
fi

if $IS_LAPTOP; then
    apt-get install -y tlp tlp-rdw thermald xserver-xorg-input-libinput
    systemctl enable tlp thermald
    success "Laptop-Optimierung abgeschlossen"
fi

# USB WLAN Power Management Fix
cat > /etc/udev/rules.d/70-usb-wlan-power.rules << 'EOF'
ACTION=="add", SUBSYSTEM=="usb", ATTR{idVendor}=="057c", ATTR{power/control}="on"
ACTION=="add", SUBSYSTEM=="usb", DRIVER=="mt76x2u", ATTR{power/control}="on"
EOF
success "USB WLAN Power-Management deaktiviert"

# ============================================================
# SCHRITT 3 — i3 Desktop
# ============================================================
step "3/11 — i3 + Polybar + Rofi + Dunst + i3lock"

wait_apt
apt-get install -y \
    i3 i3status i3lock polybar rofi dunst libnotify-bin \
    libappindicator3-1 libayatana-appindicator3-1 feh \
    xdg-desktop-portal xdg-desktop-portal-gtk libdbusmenu-gtk3-4 \
    redshift scrot brightnessctl playerctl \
    network-manager bluez \
    fonts-inter fonts-noto fonts-noto-color-emoji fonts-font-awesome fonts-jetbrains-mono \
    papirus-icon-theme \
    gtk2-engines gtk2-engines-murrine gtk2-engines-pixbuf \
    qt5ct qt6ct qt5-style-plugins adwaita-qt \
    xsettingsd lxpolkit lxappearance \
    picom xss-lock xserver-xorg-input-libinput \
    diodon cups cups-bsd cups-client printer-driver-splix \
    gparted ntfs-3g udiskie \
    pcmanfm libfm-gtk3-bin gvfs gvfs-backends

systemctl enable cups bluetooth 2>/dev/null || true

# bluetui
BLUETUI_URL=$(curl -sf https://api.github.com/repos/pythops/bluetui/releases/latest 2>/dev/null \
    | python3 -c "
import sys,json
try:
    data=json.load(sys.stdin)
    [print(a['browser_download_url']) for a in data.get('assets',[]) if 'x86_64' in a['name'] and 'linux' in a['name'] and a['name'].endswith('.tar.gz')]
except: pass
" 2>/dev/null | head -1)
if [[ -n "$BLUETUI_URL" ]]; then
    curl -L "$BLUETUI_URL" -o /tmp/bluetui.tar.gz
    tar -xzf /tmp/bluetui.tar.gz -C /tmp/
    find /tmp -name "bluetui" -type f -exec mv {} /usr/local/bin/bluetui \; 2>/dev/null
    chmod +x /usr/local/bin/bluetui 2>/dev/null || true
    rm -f /tmp/bluetui.tar.gz
    success "bluetui installiert"
fi

# Touchpad
mkdir -p /etc/X11/xorg.conf.d
cat > /etc/X11/xorg.conf.d/30-touchpad.conf << 'EOF'
Section "InputClass"
    Identifier "libinput touchpad"
    MatchIsTouchpad "on"
    MatchDevicePath "/dev/input/event*"
    Driver "libinput"
    Option "Tapping" "on"
    Option "ClickMethod" "clickfinger"
    Option "NaturalScrolling" "true"
    Option "DisableWhileTyping" "on"
EndSection
EOF

# i3 Autostart
BASH_PROFILE="$TARGET_HOME/.bash_profile"
grep -q "startx" "$BASH_PROFILE" 2>/dev/null || {
    echo '' >> "$BASH_PROFILE"
    echo '# SnowFoxOS — i3 automatisch starten' >> "$BASH_PROFILE"
    echo '[ "$(tty)" = "/dev/tty1" ] && exec startx' >> "$BASH_PROFILE"
}

# .xinitrc — korrekt, kein Arc-Dark, kein gsettings, kein wlsunset
cat > "$TARGET_HOME/.xinitrc" << 'EOF'
#!/bin/sh
export PATH=/usr/local/bin:/usr/bin:/bin:/usr/local/games:/usr/games
export GTK_THEME=GTK_THEME_PLACEHOLDER # Platzhalter für install_themes
export GTK2_RC_FILES="$HOME/.gtkrc-2.0"
export QT_QPA_PLATFORMTHEME=qt5ct
export _JAVA_AWT_WM_NONREPARENTING=1
export XDG_CURRENT_DESKTOP=XFCE

xsettingsd &

if [ -f /usr/bin/dbus-launch ]; then
    eval $(/usr/bin/dbus-launch --sh-syntax --exit-with-session)
fi

exec i3
EOF
chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.xinitrc"
chmod +x "$TARGET_HOME/.xinitrc"

success "i3 Desktop & Autostart eingerichtet"

# Nerd Fonts
NERD_VERSION=$(curl -sf https://api.github.com/repos/ryanoasis/nerd-fonts/releases/latest 2>/dev/null \
    | python3 -c "import sys,json; print(json.load(sys.stdin).get('tag_name','v3.2.1'))" 2>/dev/null || echo "v3.2.1")
mkdir -p /usr/local/share/fonts/nerd-fonts
curl -L "https://github.com/ryanoasis/nerd-fonts/releases/download/${NERD_VERSION}/JetBrainsMono.zip" \
    -o /tmp/JetBrainsMono.zip 2>/dev/null && \
    unzip -o /tmp/JetBrainsMono.zip "*.ttf" -d /usr/local/share/fonts/nerd-fonts/ 2>/dev/null && \
    fc-cache -fv /usr/local/share/fonts/nerd-fonts/ 2>/dev/null && \
    rm -f /tmp/JetBrainsMono.zip && success "JetBrainsMono Nerd Font installiert" || true

# ============================================================
# SCHRITT 4 — Audio (PipeWire)
# ============================================================
step "4/11 — Audio (PipeWire)"

apt-get install -y pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol pulseaudio-utils
apt-get remove --purge -y pulseaudio 2>/dev/null || true
sudo -u "$TARGET_USER" systemctl --user enable pipewire pipewire-pulse wireplumber 2>/dev/null || true
success "PipeWire installiert"

# ============================================================
# SCHRITT 5 — Terminal & Apps
# ============================================================
step "5/11 — Terminal & Standard-Apps"

apt-get install -y kitty mc mousepad ristretto file-roller mpv ffmpeg

if ask_install "VLC Media Player"; then apt-get install -y vlc && success "VLC installiert"; fi
if ask_install "GIMP (Bildbearbeitung)"; then apt-get install -y gimp && success "GIMP installiert"; fi

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
    curl -fsSL https://download.onlyoffice.com/GPG-KEY-ONLYOFFICE | gpg --dearmor -o /etc/apt/keyrings/onlyoffice.gpg
    echo "deb [signed-by=/etc/apt/keyrings/onlyoffice.gpg] https://download.onlyoffice.com/repo/debian squeeze main" \
        | tee /etc/apt/sources.list.d/onlyoffice.list
    wait_apt; apt-get update -qq
    apt-get install -y onlyoffice-desktopeditors && success "OnlyOffice installiert" || warn "OnlyOffice fehlgeschlagen"
fi

if ask_install "Logseq (Notizen)"; then
    LOGSEQ_URL=$(curl -sf https://api.github.com/repos/logseq/logseq/releases/latest 2>/dev/null \
        | python3 -c "import sys,json; [print(a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[]) if a['name'].endswith('.AppImage')]" 2>/dev/null | head -1)
    if [[ -n "$LOGSEQ_URL" ]]; then
        mkdir -p "$TARGET_HOME/Applications"
        curl -L "$LOGSEQ_URL" -o "$TARGET_HOME/Applications/logseq.AppImage"
        chmod +x "$TARGET_HOME/Applications/logseq.AppImage"
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/Applications"
        cat > "$TARGET_HOME/.local/share/applications/logseq.desktop" << LSEOF
[Desktop Entry]
Name=Logseq
Exec=$TARGET_HOME/Applications/logseq.AppImage --no-sandbox %U
Icon=accessories-text-editor
Type=Application
Categories=Office;
LSEOF
        success "Logseq installiert"
    fi
fi

curl -sL https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
chmod +x /usr/local/bin/yt-dlp
success "yt-dlp installiert"

# ============================================================
# SCHRITT 6 — Browser
# ============================================================
step "6/11 — Browser"

echo ""
echo -e "${PURPLE}${BOLD}  Browser Wahl:${RESET}"
echo -e "  1) Zen Browser  (Firefox-Basis, Privacy — empfohlen)"
echo -e "  2) Helium       (Chromium-Basis, ungoogled, max. Privacy)"
echo -e "  3) LibreWolf    (gehärteter Firefox)"
echo -e "  4) Brave        (Chromium-Basis)"
echo -e "  5) Firefox-ESR  (Standard)"
echo -e "  6) Chromium     (leicht)"
echo -e "  7) Keinen"
echo ""
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-7]: "${RESET})" BROWSER_CHOICE

DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
case "$BROWSER_CHOICE" in
    1)
        ZEN_URL=$(curl -sf https://api.github.com/repos/zen-browser/desktop/releases/latest 2>/dev/null \
            | python3 -c "import sys,json; [print(a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[]) if a['name'].endswith('x86_64.AppImage')]" 2>/dev/null | head -1)
        if [[ -n "$ZEN_URL" ]]; then
            curl -L "$ZEN_URL" -o /opt/zen-browser.AppImage
            chmod +x /opt/zen-browser.AppImage
            apt-get install -y libfuse2 2>/dev/null || true
            cat > /usr/share/applications/zen-browser.desktop << 'EOF'
[Desktop Entry]
Name=Zen Browser
Exec=/opt/zen-browser.AppImage %u
Icon=firefox
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
EOF
            DEFAULT_BROWSER_DESKTOP="zen-browser.desktop"
            success "Zen Browser installiert"
        else
            apt-get install -y firefox-esr; DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
        fi ;;
    2)
        HELIUM_URL=$(curl -sf https://api.github.com/repos/imputnet/helium-linux/releases/latest 2>/dev/null \
            | python3 -c "import sys,json; [print(a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[]) if a['name'].endswith('x86_64.AppImage')]" 2>/dev/null | head -1)
        if [[ -n "$HELIUM_URL" ]]; then
            curl -L "$HELIUM_URL" -o /opt/helium-browser.AppImage
            chmod +x /opt/helium-browser.AppImage
            apt-get install -y libfuse2 2>/dev/null || true
            echo 'kernel.unprivileged_userns_clone=1' > /etc/sysctl.d/99-userns.conf
            sysctl -p /etc/sysctl.d/99-userns.conf > /dev/null 2>&1 || true
            cat > /usr/share/applications/helium-browser.desktop << 'EOF'
[Desktop Entry]
Name=Helium Browser
Exec=/opt/helium-browser.AppImage %u
Icon=chromium
Type=Application
Categories=Network;WebBrowser;
MimeType=x-scheme-handler/http;x-scheme-handler/https;text/html;
EOF
            DEFAULT_BROWSER_DESKTOP="helium-browser.desktop"
            success "Helium Browser installiert"
        else
            apt-get install -y firefox-esr; DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"
        fi ;;
    3)
        curl -fsSL https://deb.librewolf.net/keyring.gpg | gpg --dearmor | tee /usr/share/keyrings/librewolf.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/librewolf.gpg arch=amd64] https://deb.librewolf.net bookworm main" | tee /etc/apt/sources.list.d/librewolf.list
        wait_apt; apt-get update -qq; apt-get install -y librewolf && success "LibreWolf installiert" || warn "LibreWolf fehlgeschlagen"
        DEFAULT_BROWSER_DESKTOP="librewolf.desktop" ;;
    4)
        curl -fsS https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg | tee /usr/share/keyrings/brave-browser-archive-keyring.gpg > /dev/null
        echo "deb [signed-by=/usr/share/keyrings/brave-browser-archive-keyring.gpg] https://brave-browser-apt-release.s3.brave.com/ stable main" | tee /etc/apt/sources.list.d/brave-browser.list
        wait_apt; apt-get update -qq; apt-get install -y brave-browser
        DEFAULT_BROWSER_DESKTOP="brave-browser.desktop"; success "Brave installiert" ;;
    5) apt-get install -y firefox-esr; DEFAULT_BROWSER_DESKTOP="firefox-esr.desktop"; success "Firefox-ESR installiert" ;;
    6) apt-get install -y chromium; DEFAULT_BROWSER_DESKTOP="chromium.desktop"; success "Chromium installiert" ;;
    *) warn "Kein Browser installiert" ;;
esac

# ============================================================
# SCHRITT 7 — Steam & Gaming
# ============================================================
step "7/11 — Steam & Gaming"

if ask_install "Steam"; then
    apt-get install -y steam steam-devices libvulkan1 libvulkan1:i386 vulkan-tools \
        libgl1-mesa-dri:i386 mesa-vulkan-drivers:i386 gamemode 2>/dev/null || true
    systemctl enable gamemoded 2>/dev/null || true
    PROTON_URL=$(curl -sf https://api.github.com/repos/GloriousEggroll/proton-ge-custom/releases/latest 2>/dev/null \
        | python3 -c "import sys,json; [print(a['browser_download_url']) for a in json.load(sys.stdin).get('assets',[]) if a['name'].endswith('.tar.gz')]" 2>/dev/null | head -1)
    if [[ -n "$PROTON_URL" ]]; then
        curl -L "$PROTON_URL" -o /tmp/proton-ge.tar.gz
        mkdir -p "$TARGET_HOME/.steam/root/compatibilitytools.d"
        tar -xzf /tmp/proton-ge.tar.gz -C "$TARGET_HOME/.steam/root/compatibilitytools.d/"
        rm -f /tmp/proton-ge.tar.gz
        chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.steam/root/compatibilitytools.d/"
        success "Steam + Proton GE installiert"
    fi
fi

# ============================================================
# SCHRITT 7b — Ollama
# ============================================================
step "7b/11 — Ollama (Lokale KI)"

if ask_install "Ollama (lokale KI — nur Engine)"; then
    curl -fsSL https://ollama.com/install.sh | sh 2>/dev/null || warn "Ollama fehlgeschlagen"
    systemctl disable ollama 2>/dev/null || true
    success "Ollama installiert (inaktiv — start: ollama serve)"
fi

# ============================================================
# SCHRITT 8 — Zusatzwerkzeuge
# ============================================================
step "8/11 — Zusatzwerkzeuge"

apt-get install -y ffmpegthumbnailer poppler-utils bat unar

# Desktop-Einträge
mkdir -p "$TARGET_HOME/.local/share/applications"
cat > "$TARGET_HOME/.local/share/applications/nmtui.desktop" << 'EOF'
[Desktop Entry]
Name=Netzwerk
Exec=kitty -e nmtui
Icon=network-wireless
Type=Application
Categories=Network;System;
EOF
cat > "$TARGET_HOME/.local/share/applications/bluetui.desktop" << 'EOF'
[Desktop Entry]
Name=Bluetooth
Exec=kitty -e bluetui
Icon=bluetooth
Type=Application
Categories=System;
EOF
cat > "$TARGET_HOME/.local/share/applications/pcmanfm.desktop" << 'EOF'
[Desktop Entry]
Name=Dateien
Exec=pcmanfm
Icon=system-file-manager
Type=Application
Categories=System;FileManager;
EOF

# i3: udiskie + mod+e auf pcmanfm
I3_CONFIG_PATH="$TARGET_HOME/.config/i3/config"
if [[ -f "$I3_CONFIG_PATH" ]]; then
    grep -q "udiskie --tray" "$I3_CONFIG_PATH" || echo 'exec --no-startup-id udiskie --tray' >> "$I3_CONFIG_PATH"
    if grep -q '^bindsym \$mod+e' "$I3_CONFIG_PATH"; then
        sed -i 's|^bindsym \$mod+e.*|bindsym $mod+e exec pcmanfm|' "$I3_CONFIG_PATH"
    else
        echo 'bindsym $mod+e exec pcmanfm' >> "$I3_CONFIG_PATH"
    fi
fi
success "Zusatzwerkzeuge installiert"

# ============================================================
# SCHRITT 9 — Performance & Sicherheit
# ============================================================
step "9/11 — Performance & Sicherheit"

apt-get install -y zram-tools earlyoom ufw fail2ban apparmor apparmor-profiles apparmor-utils
command -v tlp &>/dev/null || apt-get install -y tlp tlp-rdw

cat > /etc/default/zramswap << 'EOF'
ALGO=lz4
PERCENT=50
PRIORITY=100
EOF

[[ -f /etc/initramfs-tools/initramfs.conf ]] && \
    sed -i 's/^COMPRESS=.*/COMPRESS=lz4/' /etc/initramfs-tools/initramfs.conf && \
    update-initramfs -u 2>/dev/null || true

systemctl enable zramswap earlyoom tlp apparmor 2>/dev/null || true

cat > /etc/sysctl.d/99-snowfox.conf << 'EOF'
vm.swappiness=10
vm.vfs_cache_pressure=50
vm.dirty_background_ratio=3
vm.dirty_ratio=6
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.core.rmem_max=16777216
net.core.wmem_max=16777216
net.ipv6.conf.all.use_tempaddr=2
net.ipv6.conf.default.use_tempaddr=2
kernel.nmi_watchdog=0
kernel.kptr_restrict=2
kernel.core_uses_pid=1
kernel.perf_event_paranoid=3
net.core.bpf_jit_harden=2
net.ipv4.conf.all.log_martians=1
net.ipv4.conf.default.log_martians=1
net.ipv4.conf.all.rp_filter=1
net.ipv4.conf.all.send_redirects=0
net.ipv4.conf.default.accept_source_route=0
fs.protected_fifos=2
dev.tty.ldisc_autoload=0
EOF

sed -i 's/errors=remount-ro/errors=remount-ro,noatime/g' /etc/fstab
sed -i '/tmpfs \/tmp tmpfs/d' /etc/fstab
echo "tmpfs /tmp tmpfs defaults,noatime,size=4G,mode=1777 0 0" >> /etc/fstab

ufw default deny incoming 2>/dev/null || true
ufw default allow outgoing 2>/dev/null || true
ufw --force enable 2>/dev/null || true

mkdir -p /etc/NetworkManager/conf.d
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
wifi.powersave=2
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
for svc in avahi-daemon cups-browsed ModemManager colord blueman; do
    systemctl disable "$svc" 2>/dev/null || true
done
systemctl mask NetworkManager-wait-online.service systemd-networkd-wait-online.service 2>/dev/null || true
sed -i 's/#HandlePowerKey=.*/HandlePowerKey=ignore/' /etc/systemd/logind.conf

# Core dumps deaktivieren
echo '* hard core 0' >> /etc/security/limits.conf

# umask härten
sed -i 's/^UMASK.*/UMASK\t\t027/' /etc/login.defs 2>/dev/null || true

# Dateiberechtigungen
chmod 600 /etc/crontab /etc/ssh/sshd_config 2>/dev/null || true
chmod 700 /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly 2>/dev/null || true

# Unnötige Protokolle deaktivieren
cat > /etc/modprobe.d/snowfox-blacklist.conf << 'EOF'
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
EOF

success "Performance & Sicherheit optimiert"

# ============================================================
# SCHRITT 10 — Plymouth & Branding
# ============================================================
step "10/11 — Plymouth & Boot-Screen"

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
convert -size 1920x1080 xc:#1a1a1a "$PLYMOUTH_DIR/background.png" 2>/dev/null || true
plymouth-set-default-theme -R snowfox 2>/dev/null || \
    { plymouth-set-default-theme snowfox 2>/dev/null; update-initramfs -u 2>/dev/null; }
success "Boot-Screen bereit"

# ============================================================
# SCHRITT 11 — Konfiguration & Abschluss
# ============================================================
step "11/11 — Konfiguration & Finishing"

CONFIG_DIR="$TARGET_HOME/.config"
mkdir -p "$CONFIG_DIR/neofetch" "$TARGET_HOME/Pictures/wallpapers"

cat > /etc/os-release << 'EOF'
PRETTY_NAME="SnowFoxOS 2.1"
NAME="SnowFoxOS"
VERSION="2.1"
VERSION_ID="2.1"
ID=snowfoxos
ID_LIKE=debian
HOME_URL="https://github.com/Xr7-Code/SnowFoxOS-v2.1-i3"
ANSI_COLOR="0;35"
EOF
cat > /etc/lsb-release << 'EOF'
DISTRIB_ID=SnowFoxOS
DISTRIB_RELEASE=2.1
DISTRIB_CODENAME=fox
DISTRIB_DESCRIPTION="SnowFoxOS 2.1"
EOF
echo "snowfox" > /etc/hostname
echo "SnowFoxOS 2.1" > /etc/issue
# Hostname in /etc/hosts eintragen, um Auflösungsfehler zu vermeiden
if ! grep -q "127.0.1.1.*snowfox" /etc/hosts; then
    # Entferne alte 127.0.1.1 Einträge, falls vorhanden
    sed -i '/^127\.0\.1\.1/d' /etc/hosts
    echo "127.0.1.1       snowfox" >> /etc/hosts
fi
hostname snowfox 2>/dev/null || true

# Themes installieren (zentrale Funktion)
install_themes "$TARGET_HOME" "$TARGET_USER"

# Neofetch
cat > "$CONFIG_DIR/neofetch/config.conf" << EOF
print_info() {
    info title; info underline
    info "OS" distro; info "Kernel" kernel; info "Uptime" uptime
    info "Packages" packages; info "Shell" shell; info "Resolution" resolution
    info "WM" wm; info "CPU" cpu; info "GPU" gpu; info "Memory" memory
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
    sed -i 's/show-icons: .*/show-icons: false;/' "$CONFIG_DIR/rofi/config.rasi" 2>/dev/null || true
    if [[ -f "$CONFIG_DIR/picom.conf" ]]; then
        sed -i 's/backend = .*/backend = "glx";/' "$CONFIG_DIR/picom.conf"
        sed -i 's/fading = .*/fading = false;/' "$CONFIG_DIR/picom.conf"
    fi
fi

find "$CONFIG_DIR" -name "*.sh" -exec chmod +x {} +

# Wallpaper
[[ -d "$SCRIPT_DIR/wallpapers" ]] && cp -r "$SCRIPT_DIR/wallpapers/." "$TARGET_HOME/Pictures/wallpapers/"
DEFAULT_WP=$(ls "$TARGET_HOME/Pictures/wallpapers" 2>/dev/null | grep -iE "\.(jpg|png|webp|jpeg)$" | head -1)
if [[ -n "$DEFAULT_WP" ]]; then
    printf '#!/bin/sh\nfeh --bg-fill "%s/Pictures/wallpapers/%s"\n' "$TARGET_HOME" "$DEFAULT_WP" > "$TARGET_HOME/.fehbg"
    chmod +x "$TARGET_HOME/.fehbg"
fi

# Polybar Laptop/Desktop
POLYBAR_CONF="$CONFIG_DIR/polybar/config.ini"
if [[ -f "$POLYBAR_CONF" ]]; then
    if $IS_LAPTOP; then
        BAT_NAME=$(ls /sys/class/power_supply/ 2>/dev/null | grep -E "^BAT" | head -1)
        BL_NAME=$(ls /sys/class/backlight/ 2>/dev/null | head -1)
        [[ -n "$BAT_NAME" ]] && sed -i "s/^battery = .*/battery = $BAT_NAME/" "$POLYBAR_CONF"
        [[ -n "$BL_NAME" ]]  && sed -i "s/^card = .*/card = $BL_NAME/" "$POLYBAR_CONF"
        sed -i 's/^modules-right =.*/modules-right = backlight battery memory network pulseaudio/' "$POLYBAR_CONF"
    else
        sed -i 's/^modules-right =.*/modules-right = memory network pulseaudio/' "$POLYBAR_CONF"
    fi
fi

# launch.sh mit Laptop-Erkennung
mkdir -p "$CONFIG_DIR/polybar"
cat > "$CONFIG_DIR/polybar/launch.sh" << 'LAUNCHEOF'
#!/bin/bash
sleep 2
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done
PRIMARY=$(xrandr --query | grep " connected primary" | cut -d" " -f1)
[[ -z "$PRIMARY" ]] && PRIMARY=$(xrandr --query | grep " connected" | head -1 | cut -d" " -f1)
CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
IS_LAPTOP=false
[[ "$CHASSIS" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true
ls /sys/class/power_supply/BAT* &>/dev/null && IS_LAPTOP=true
if $IS_LAPTOP; then
    BAT=$(ls /sys/class/power_supply/ | grep -E "^BAT" | head -1)
    AC=$(ls /sys/class/power_supply/ | grep -E "^(AC|ADP|ACAD)" | head -1)
    [[ -n "$BAT" ]] && sed -i "s/^battery = .*/battery = $BAT/" ~/.config/polybar/config.ini
    [[ -n "$AC" ]]  && sed -i "s/^adapter = .*/adapter = $AC/"  ~/.config/polybar/config.ini
    MONITOR=$PRIMARY polybar snowfox-laptop 2>/tmp/polybar.log &
else
    MONITOR=$PRIMARY polybar snowfox 2>/tmp/polybar.log &
fi
LAUNCHEOF
chmod +x "$CONFIG_DIR/polybar/launch.sh"

# Skripte
[[ -f "$SCRIPT_DIR/configs/powermenu.sh" ]] && \
    cp "$SCRIPT_DIR/configs/powermenu.sh" /usr/local/bin/snowfox-powermenu && \
    chmod +x /usr/local/bin/snowfox-powermenu

[[ -f "$SCRIPT_DIR/snowfox" ]] && \
    cp "$SCRIPT_DIR/snowfox" /usr/local/bin/snowfox && chmod +x /usr/local/bin/snowfox

[[ -f "$SCRIPT_DIR/snowfox-greeting.sh" ]] && \
    cp "$SCRIPT_DIR/snowfox-greeting.sh" /usr/local/bin/snowfox-greeting && \
    chmod +x /usr/local/bin/snowfox-greeting

grep -q "snowfox-greeting" "$TARGET_HOME/.bashrc" 2>/dev/null || \
    printf '\n[[ -x /usr/local/bin/snowfox-greeting ]] && snowfox-greeting\n' >> "$TARGET_HOME/.bashrc"

# Standard-Apps
echo ""
echo -e "${PURPLE}${BOLD}  Standard-Texteditor:${RESET}"
echo -e "  1) Mousepad  2) VSCodium"
read -rp "$(echo -e ${PURPLE}${BOLD}"Auswahl [1-2]: "${RESET})" DEFAULT_EDITOR
[[ "$DEFAULT_EDITOR" == "2" ]] && DEFAULT_EDITOR_DESKTOP="codium.desktop" || DEFAULT_EDITOR_DESKTOP="mousepad.desktop"

cat > "$CONFIG_DIR/mimeapps.list" << MEOF
[Default Applications]
inode/directory=pcmanfm.desktop
text/plain=$DEFAULT_EDITOR_DESKTOP
text/x-python=$DEFAULT_EDITOR_DESKTOP
text/x-shellscript=$DEFAULT_EDITOR_DESKTOP
x-scheme-handler/http=$DEFAULT_BROWSER_DESKTOP
x-scheme-handler/https=$DEFAULT_BROWSER_DESKTOP
text/html=$DEFAULT_BROWSER_DESKTOP
application/pdf=$DEFAULT_BROWSER_DESKTOP
image/png=ristretto.desktop
image/jpeg=ristretto.desktop
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
audio/mpeg=mpv.desktop
application/zip=file-roller.desktop
MEOF

# Berechtigungen
info "Setze finale Berechtigungen für $TARGET_HOME..."
chown -R "$TARGET_USER:$TARGET_USER" "$TARGET_HOME" 2>/dev/null || true
[[ -f "$TARGET_HOME/.gtkrc-2.0" ]] && chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.gtkrc-2.0"
[[ -f "$TARGET_HOME/.fehbg" ]] && chown "$TARGET_USER:$TARGET_USER" "$TARGET_HOME/.fehbg"

# DKMS-Hooks wiederherstellen
for hook in "${DKMS_HOOKS[@]}"; do
    [[ -f "${hook}.snowfox-bak" ]] && mv "${hook}.snowfox-bak" "$hook"
done

apt-get autoremove --purge -y 2>/dev/null || true

echo -e "${PURPLE}${BOLD}"
echo "  ███████╗███╗  ██╗ ██████╗ ██╗    ██╗███████╗ ██████╗ ██╗  ██╗"
echo "  ██╔════╝████╗ ██║██╔═══██╗██║    ██║██╔════╝██╔═══██╗╚██╗██╔╝"
echo "  ███████╗██╔██╗██║██║   ██║██║ █╗ ██║█████╗  ██║   ██║ ╚███╔╝ "
echo "  ╚════██║██║╚████║██║   ██║██║███╗██║██╔══╝  ██║   ██║ ██╔██╗ "
echo "  ███████║██║ ╚███║╚██████╔╝╚███╔███╔╝██║     ╚██████╔╝██╔╝╚██╗"
echo "  ╚══════╝╚═╝  ╚══╝ ╚═════╝  ╚══╝╚══╝ ╚═╝     ╚═════╝ ╚═╝  ╚═╝"
echo -e "${RESET}"
success "SnowFoxOS v2.1 erfolgreich installiert!"
warn   "Bitte neu starten: sudo reboot"
