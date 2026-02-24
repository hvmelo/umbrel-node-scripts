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

# ===================== CONFIG =====================


LAST_UPDATE_FILE="/tmp/umbrel_last_update_id"
STATE_FILE="/tmp/status_prev"

# ===================== FUNÇÕES =====================

btc() {
  # ===== 1) CLI direto (Ubuntu / sistema externo) =====
  if [[ -n "$BITCOIN_CLI" && -x "$BITCOIN_CLI" ]]; then
    "$BITCOIN_CLI" -datadir="$BITCOIN_DATADIR" "$@" 2>/dev/null && return
  fi

  # ===== 2) Umbrel via Docker (sudo) =====
  if command -v docker >/dev/null 2>&1; then
    sudo docker exec bitcoin_app_1 \
      bitcoin-cli -rpccookiefile=/data/bitcoin/.cookie \
      "$@" 2>/dev/null && return
  fi

  echo "ERROR: Cannot access bitcoin-cli in this environment." >&2
  return 1
}

check_rpc() {
  btc getblockchaininfo >/dev/null 2>&1
  return $?
}

send_telegram() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" \
    -d parse_mode="HTML"
}

format_time() {
  local min=$1
  local h=$((min / 60))
  local m=$((min % 60))
  echo "${h}h ${m}min"
}

get_battery_percent() {
  if command -v upower >/dev/null 2>&1; then
    battery=$(upower -e | grep battery)

    if [[ -n "$battery" ]]; then
      info=$(upower -i "$battery")

      percent=$(echo "$info" | awk '/percentage/ {print $2}')
      state=$(echo "$info" | awk '/state/ {print $2}')

      case "$state" in
        charging)
          echo "AC (charging $percent)"
          ;;
        discharging)
          echo "$percent"
          ;;
        fully-charged)
          echo "AC (full $percent)"
          ;;
        *)
          echo "$percent"
          ;;
      esac
    else
      echo "AC"
    fi
  else
    echo "N/A"
  fi
}

get_temperature() {
  # ===== Raspberry Pi =====
  if command -v vcgencmd >/dev/null 2>&1; then
    vcgencmd measure_temp | cut -d= -f2
    return
  fi

  # ===== Linux padrão =====
  if [[ -f /sys/class/thermal/thermal_zone0/temp ]]; then
    temp_raw=$(cat /sys/class/thermal/thermal_zone0/temp)
    awk "BEGIN {printf \"%.1f°C\", $temp_raw/1000}"
    return
  fi

  # ===== lm-sensors =====
  if command -v sensors >/dev/null 2>&1; then
    sensors | awk '/Package id 0:/ {print $4; exit}'
    return
  fi

  echo "N/A"
}

seconds_to_human() {
  local sec=$1
  printf "%dh %dm" $((sec/3600)) $(((sec%3600)/60))
}

# ===================== STATUS =====================

send_status() {

  info=$(btc getblockchaininfo)
  [[ -z "$info" ]] && send_telegram "⚠️ Node não respondeu." && return

  ibd=$(echo "$info" | jq -r .initialblockdownload)
  blocks=$(echo "$info" | jq -r .blocks)
  headers=$(echo "$info" | jq -r .headers)
  progress_raw=$(echo "$info" | jq -r .verificationprogress)
  percent_sync=$(printf "%.2f" "$(echo "$progress_raw * 100" | bc -l)")
  battery=$(get_battery_percent)
  temp=$(get_temperature)

  # =========================================================
  # 🟡 MODO IBD
  # =========================================================

  if [[ "$ibd" == "true" ]]; then

    now=$(date +%s)

    if [[ -f "$STATE_FILE" ]]; then
      source "$STATE_FILE"
      block_delta=$((blocks - prev_blocks))
      time_delta=$((now - prev_time))
    else
      block_delta=0
      time_delta=0
    fi

    if (( time_delta > 0 && block_delta > 0 )); then
      speed=$(echo "scale=2; ($block_delta * 60) / $time_delta" | bc)
    else
      speed=0
    fi

    remaining=$((headers - blocks))

    if (( $(echo "$speed > 0" | bc -l) )); then
      minutes=$(echo "$remaining / $speed" | bc)
      tempo_restante=$(format_time "$minutes")
      eta=$(date -d "+$minutes minutes" +"%Y-%m-%d %H:%M")
    else
      tempo_restante="Indefinido"
      eta="Indefinido"
    fi

    send_telegram "📡 <b>Bitcoin Node Status (IBD)</b>
<b>Progress:</b> ${percent_sync}%
<b>Blocks:</b> ${blocks} / ${headers}
<b>Speed:</b> ${speed} blocos/min
<b>Remaining:</b> ${tempo_restante}
<b>ETA:</b> ${eta}
<b>Temperature:</b> ${temp}
<b>Battery:</b> ${battery}"

    cat > "$STATE_FILE" <<EOF
prev_blocks=$blocks
prev_time=$now
EOF

    return
  fi

  # =========================================================
  # 🟢 MODO SINCRONIZADO
  # =========================================================

  net=$(btc getnetworkinfo)

  peers=$(echo "$net" | jq -r .connections)
  inbound=$(echo "$net" | jq '[.connections_in] // 0' 2>/dev/null)

  besthash=$(btc getbestblockhash)
  block=$(btc getblock "$besthash")

  block_time=$(echo "$block" | jq -r .time)
  txs=$(echo "$block" | jq -r '.nTx')

  now=$(date +%s)
  age=$((now - block_time))

  uptime=$(btc uptime)
  uptime_human=$(seconds_to_human "$uptime")

  send_telegram "📡 <b>Bitcoin Node Status</b>
🟢 <b>Synced:</b> YES
📦 <b>Height:</b> ${blocks}
🌐 <b>Peers:</b> ${peers}
⏱ <b>Last block:</b> ${age}s ago
🧱 <b>Txs in block:</b> ${txs}
⏳ <b>Uptime:</b> ${uptime_human}
🌡️ <b>Temperature:</b> ${temp}
🔋 <b>Battery:</b> ${battery}"
}

# ===================== SYSINFO =====================

send_sysinfo() {

  disk_used=$(df -h / | awk 'NR==2 {print $3}')
  disk_total=$(df -h / | awk 'NR==2 {print $2}')

  ram_used=$(free -h | awk '/Mem:/ {print $3}')
  ram_total=$(free -h | awk '/Mem:/ {print $2}')

  cpu=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f", $2+$4}')

  battery=$(get_battery_percent)
  
  temp=$(get_temperature)

  send_telegram "🧠 <b>System Info</b>
<b>Storage:</b> ${disk_used} / ${disk_total}
<b>RAM:</b> ${ram_used} / ${ram_total}
<b>CPU:</b> ${cpu}%
<b>Temperature:</b> ${temp}
<b>Battery:</b> ${battery}"
}

# ===================== HELP =====================

send_help() {

  send_telegram "📖 <b>Comandos disponíveis</b>
<b>/status</b> — Status do node (adaptativo)
<b>/sysinfo</b> — Informações do sistema
<b>/help</b> — Ajuda"
}

# ===================== LOOP =====================

echo "[INIT] Status listener iniciado"

while true; do

  if ! check_rpc; then
    sleep 10
    continue
  fi

  last_update_id=$(cat "$LAST_UPDATE_FILE" 2>/dev/null || echo 0)

  response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?offset=$((last_update_id + 1))")

  updates=$(echo "$response" | jq -c '.result[]')
  [[ -z "$updates" ]] && sleep 5 && continue

  for update in $updates; do

    update_id=$(echo "$update" | jq '.update_id')
    message=$(echo "$update" | jq -r '.message.text // empty')

    case "$message" in
      "/status") send_status ;;
      "/sysinfo") send_sysinfo ;;
      "/help") send_help ;;
    esac

    echo "$update_id" > "$LAST_UPDATE_FILE"
  done
done

