#!/bin/bash
# SnowFoxOS — Display Manager via Rofi

# Angeschlossene Monitore ermitteln
MONITORS=$(xrandr | grep " connected" | awk '{print $1}')
PRIMARY=$(xrandr | grep " connected primary" | awk '{print $1}')

MENU=""
while IFS= read -r mon; do
    STATUS=$(xrandr | grep "^$mon" | grep -q " connected primary" && echo "★ PRIMARY" || echo "")
    ACTIVE=$(xrandr | grep "^$mon" | grep -q "\*" && echo "AN" || echo "AUS")
    MENU="${MENU}${mon}  [${ACTIVE}] ${STATUS}\n"
done <<< "$MONITORS"

MENU="${MENU}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n"
MENU="${MENU}  Alle spiegeln\n"
MENU="${MENU}  Alle erweitern (links-rechts)\n"
MENU="${MENU}  Nur primären Monitor\n"
MENU="${MENU}  Anordnung konfigurieren"

CHOICE=$(echo -e "$MENU" | rofi -dmenu \
    -p "Display" \
    -theme ~/.config/rofi/config.rasi \
    -width 450 \
    -lines 12)

[[ -z "$CHOICE" ]] && exit 0

case "$CHOICE" in
    *"Alle spiegeln"*)
        FIRST=""
        while IFS= read -r mon; do
            if [[ -z "$FIRST" ]]; then
                xrandr --output "$mon" --auto --primary
                FIRST="$mon"
            else
                xrandr --output "$mon" --same-as "$FIRST" --auto
            fi
        done <<< "$MONITORS"
        notify-send "🦊 SnowFox Display" "Alle Monitore gespiegelt"
        ;;

    *"Alle erweitern"*)
        PREV=""
        while IFS= read -r mon; do
            if [[ -z "$PREV" ]]; then
                xrandr --output "$mon" --auto --primary
                PREV="$mon"
            else
                xrandr --output "$mon" --auto --right-of "$PREV"
                PREV="$mon"
            fi
        done <<< "$MONITORS"
        notify-send "🦊 SnowFox Display" "Erweitert (links nach rechts)"
        ;;

    *"Nur primären"*)
        while IFS= read -r mon; do
            if [[ "$mon" == "$PRIMARY" ]]; then
                xrandr --output "$mon" --auto --primary
            else
                xrandr --output "$mon" --off
            fi
        done <<< "$MONITORS"
        notify-send "🦊 SnowFox Display" "Nur primärer Monitor aktiv"
        ;;

    *"Anordnung konfigurieren"*)
        NEW_PRIMARY=$(echo "$MONITORS" | rofi -dmenu \
            -p "Hauptmonitor wählen" \
            -theme ~/.config/rofi/config.rasi \
            -width 350 \
            -lines 5)
        [[ -z "$NEW_PRIMARY" ]] && exit 0

        OTHER=$(echo "$MONITORS" | grep -v "$NEW_PRIMARY" | head -1)
        if [[ -n "$OTHER" ]]; then
            POS=$(echo -e "Rechts von $NEW_PRIMARY\nLinks von $NEW_PRIMARY\nOben von $NEW_PRIMARY\nUnten von $NEW_PRIMARY\nAusschalten" | \
                rofi -dmenu \
                -p "$OTHER Position" \
                -theme ~/.config/rofi/config.rasi \
                -width 350 \
                -lines 5)

            xrandr --output "$NEW_PRIMARY" --auto --primary
            case "$POS" in
                *Rechts*)      xrandr --output "$OTHER" --auto --right-of "$NEW_PRIMARY" ;;
                *Links*)       xrandr --output "$OTHER" --auto --left-of "$NEW_PRIMARY" ;;
                *Oben*)        xrandr --output "$OTHER" --auto --above "$NEW_PRIMARY" ;;
                *Unten*)       xrandr --output "$OTHER" --auto --below "$NEW_PRIMARY" ;;
                *Ausschalten*) xrandr --output "$OTHER" --off ;;
            esac
            notify-send "🦊 SnowFox Display" "$NEW_PRIMARY ist jetzt primär"
        else
            xrandr --output "$NEW_PRIMARY" --auto --primary
            notify-send "🦊 SnowFox Display" "$NEW_PRIMARY ist jetzt primär"
        fi
        ;;

    *)
        MON=$(echo "$CHOICE" | awk '{print $1}')
        [[ -z "$MON" ]] && exit 0
        STATUS=$(xrandr | grep "^$MON" | grep -c "\*" || true)
        if [[ "$STATUS" -gt 0 ]]; then
            xrandr --output "$MON" --off
            notify-send "🦊 SnowFox Display" "$MON ausgeschaltet"
        else
            xrandr --output "$MON" --auto
            notify-send "🦊 SnowFox Display" "$MON eingeschaltet"
        fi
        ;;
esac

# i3 reload und Polybar auf primärem Monitor neu starten
i3-msg reload 2>/dev/null || true
sleep 0.5
~/.config/polybar/launch.sh
