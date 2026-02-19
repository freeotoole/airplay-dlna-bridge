#!/usr/bin/env bash
set -euo pipefail

echo "--- WHOAMI ---"
id || true
echo

echo "--- PS (audio services) ---"
ps aux | egrep 'pulseaudio|shairport-sync|pulseaudio-dlna' || true
echo

echo "--- PULSE SOCKETS ---"
ls -l /run/pulse /run/pulse/native || true
echo

echo "--- PACTL INFO ---"
pactl info || true
echo

echo "--- PACTL LIST SINKS ---"
pactl list short sinks || true
echo

echo "--- PACTL LIST SOURCES ---"
pactl list short sources || true
echo

echo "--- SHAIRPORT-SYNC LOG (if any) ---"
# shairport-sync logs to stderr; show recent journal if available
ps aux | grep shairport-sync >/dev/null 2>&1 && echo "shairport-sync running" || echo "shairport-sync not running"
echo

echo "--- PULSEAUDIO-DLNA LOG ---"
if [ -f /root/.config/pulseaudio-dlna.log ]; then
  tail -n 200 /root/.config/pulseaudio-dlna.log || true
else
  echo "no pulseaudio-dlna.log"
fi
echo

echo "--- LAST 200 lines of syslog (if available) ---"
tail -n 200 /var/log/syslog 2>/dev/null || true

exit 0
