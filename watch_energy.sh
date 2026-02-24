#!/bin/bash

# ===================== LOAD CONFIG =====================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

CONFIG_FILE="$SCRIPT_DIR/config.env"

if [[ -f "$CONFIG_FILE" ]]; then
  source "$CONFIG_FILE"
else
  echo "Config file not found: $CONFIG_FILE"
  exit 1
fi

# ================= FUNÇÕES =================

notify() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" \
    -d parse_mode="Markdown" >/dev/null
}

get_battery_pct() {
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 \
    | awk '/percentage/ {gsub("%",""); print $2}'
}

# ================= LOOP =================

alerted=0

while true; do
  sleep "$CHECK_INTERVAL"

  ac=$(cat "$POWER_FILE")
  pct=$(get_battery_pct)

  if [[ "$ac" == "0" && "$pct" -le "$CRITICAL_BATTERY" && "$alerted" == "0" ]]; then
    notify "*🔥 BATERIA CRÍTICA!*  
🔋 ${pct}%  
⚠️ Energia desconectada. Intervenção necessária."
    alerted=1
  fi

  # reset quando volta energia
  if [[ "$ac" == "1" ]]; then
    alerted=0
  fi
done
