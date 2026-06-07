#!/bin/bash
# ============================================================
#  SnowFoxOS — Partition Table Fixer
#  Behebt "Missing partition table" Fehler in Balena Etcher
# ============================================================

if [[ $EUID -ne 0 ]]; then
    echo "Bitte mit sudo ausführen."
    exit 1
fi

ISO_IN="${1:-SnowFoxOS-v2.1-amd64.iso}"
ISO_OUT="${ISO_IN%.iso}-etcher.iso"

if [[ ! -f "$ISO_IN" ]]; then
    echo "FEHLER: ISO nicht gefunden: $ISO_IN"
    echo "Verwendung: sudo bash $0 /pfad/zur/iso"
    exit 1
fi

apt-get install -y xorriso gdisk 2>/dev/null

echo ""
echo "Eingabe : $ISO_IN"
echo "Ausgabe : $ISO_OUT"
echo ""

# ── Schritt 1: Boot-Katalog & EFI-Partition aus Original-ISO auslesen ──
echo "=== Lese Boot-Einträge aus Original-ISO ==="
BOOT_INFO=$(xorriso -indev "$ISO_IN" -report_el_torito as_mkisofs 2>/dev/null)
echo "$BOOT_INFO"
echo ""

# EFI-Image-Pfad aus der ISO extrahieren (typisch bei live-build + grub-efi)
EFI_IMG=$(xorriso -indev "$ISO_IN" -find / -name "efi.img" -exec echo {} 2>/dev/null | head -1 | tr -d '\r')
BOOT_IMG=$(xorriso -indev "$ISO_IN" -find / -name "bios.img" -o -name "boot.img" -exec echo {} 2>/dev/null | head -1 | tr -d '\r')

echo "EFI image  : ${EFI_IMG:-nicht gefunden}"
echo "BIOS image : ${BOOT_IMG:-nicht gefunden}"
echo ""

# ── Schritt 2: ISO mit expliziter MBR + GPT Hybrid-Tabelle neu bauen ──
echo "=== Schreibe ISO mit MBR + GPT Hybrid-Partitionstabelle ==="

# xorriso replay ist der sauberste Weg —
# --protective-msdos-label schreibt eine MBR-Partition die Etcher erkennt
xorriso \
    -indev "$ISO_IN" \
    -outdev "$ISO_OUT" \
    -boot_image any replay \
    -boot_image grub grub2_mbr=/usr/lib/grub/i386-pc/boot_hybrid.img \
    -append_partition 2 0xef --interval:appended_partition_2:all:: \
    -iso_mbr_part_type 0x00 \
    -compliance no_emul_toc \
    2>&1

STATUS=$?

# ── Fallback A: ohne grub2_mbr (falls boot_hybrid.img nicht vorhanden) ──
if [[ $STATUS -ne 0 ]]; then
    echo ""
    echo "Fallback A: ohne grub2_mbr..."
    xorriso \
        -indev "$ISO_IN" \
        -outdev "$ISO_OUT" \
        -boot_image any replay \
        -append_partition 2 0xef --interval:appended_partition_2:all:: \
        -iso_mbr_part_type 0x00 \
        -compliance no_emul_toc \
        2>&1
    STATUS=$?
fi

# ── Fallback B: dd MBR direkt in bestehende ISO-Kopie ──
if [[ $STATUS -ne 0 ]]; then
    echo ""
    echo "Fallback B: MBR per dd einschreiben..."
    cp "$ISO_IN" "$ISO_OUT"

    MBR_FILE=""
    for f in \
        /usr/lib/grub/i386-pc/boot_hybrid.img \
        /usr/lib/grub/i386-pc/boot.img \
        /usr/share/grub/boot.img; do
        [[ -f "$f" ]] && MBR_FILE="$f" && break
    done

    if [[ -n "$MBR_FILE" ]]; then
        echo "Schreibe MBR aus: $MBR_FILE"
        dd if="$MBR_FILE" of="$ISO_OUT" bs=432 count=1 conv=notrunc status=none
        echo "MBR eingeschrieben."
    else
        echo "FEHLER: Kein GRUB MBR gefunden. Installiere grub-pc-bin:"
        echo "  apt-get install grub-pc-bin"
        exit 1
    fi

    # GPT-Schutzpartition mit sgdisk hinzufügen
    if command -v sgdisk &>/dev/null; then
        echo "Schreibe GPT protective MBR mit sgdisk..."
        sgdisk --mbrtogpt "$ISO_OUT" 2>/dev/null || true
    fi
fi

# ── Schritt 3: Ergebnis prüfen ──
echo ""
echo "=== Partitionstabelle der fertigen ISO ==="
fdisk -l "$ISO_OUT" 2>/dev/null
echo ""
echo "=== file-Check ==="
file "$ISO_OUT"

echo ""
SIZE_IN=$(du -sh  "$ISO_IN"  | cut -f1)
SIZE_OUT=$(du -sh "$ISO_OUT" | cut -f1)
echo "Original : $SIZE_IN"
echo "Repariert: $SIZE_OUT"
echo ""

if [[ -f "$ISO_OUT" ]]; then
    echo "✓ FERTIG → $ISO_OUT"
    echo "  Diese Datei in Balena Etcher laden."
else
    echo "✗ FEHLER: Ausgabe-ISO nicht erstellt."
    exit 1
fi