#!/bin/bash
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
