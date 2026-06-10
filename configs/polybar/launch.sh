#!/bin/bash
# SnowFoxOS — Polybar Launcher
# Erkennt automatisch ob Laptop oder Desktop

killall -q polybar
while pgrep -u $UID -x polybar > /dev/null; do sleep 0.1; done

# Laptop-Erkennung via chassis type
CHASSIS=$(cat /sys/class/dmi/id/chassis_type 2>/dev/null || echo "0")
IS_LAPTOP=false
[[ "$CHASSIS" =~ ^(8|9|10|14)$ ]] && IS_LAPTOP=true

# Fallback: Akku vorhanden?
ls /sys/class/power_supply/BAT* &>/dev/null && IS_LAPTOP=true

if $IS_LAPTOP; then
    # Korrekten Akku-Pfad ermitteln und in Config setzen
    BAT=$(ls /sys/class/power_supply/ | grep -E '^BAT' | head -1)
    AC=$(ls /sys/class/power_supply/ | grep -E '^(AC|ADP|ACAD)' | head -1)
    if [[ -n "$BAT" && -n "$AC" ]]; then
        sed -i "s/^battery = .*/battery = $BAT/" ~/.config/polybar/config.ini
        sed -i "s/^adapter = .*/adapter = $AC/" ~/.config/polybar/config.ini
    fi
    polybar snowfox-laptop 2>&1 | tee -a /tmp/polybar.log & disown
else
    polybar snowfox 2>&1 | tee -a /tmp/polybar.log & disown
fi#!/bin/bash
# SnowFoxOS — Polybar Starter
# Dem System Zeit geben, Monitore zu initialisieren
sleep 2

# Alle bestehenden Polybar-Instanzen beenden
killall -q polybar
while pgrep -u $UID -x polybar >/dev/null; do sleep 0.1; done

# Primären Monitor ermitteln und Polybar starten
PRIMARY=$(xrandr --query | grep " connected primary" | cut -d" " -f1)

# Fallback falls kein primary gesetzt ist
if [[ -z "$PRIMARY" ]]; then
    PRIMARY=$(xrandr --query | grep " connected" | head -1 | cut -d" " -f1)
fi

MONITOR=$PRIMARY polybar snowfox 2>/tmp/polybar.log &
