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

BITCOIN_CLI="/home/hvmelo/bitcoin/bitcoin-30.2/bin/bitcoin-cli"
BITCOIN_DATADIR="/mnt/umbrel/state/default/persist/data/umbrel-os/home/umbrel/umbrel/app-data/bitcoin/data/bitcoin"

LAST_UPDATE_FILE="/tmp/umbrel_last_update_id"
STATE_FILE="/tmp/status_prev"

# ===================== FUNÇÕES =====================

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

btc() {
  "$BITCOIN_CLI" \
    -datadir="$BITCOIN_DATADIR" \
    "$@" 2>/dev/null
}

format_time() {
  local min=$1
  local h=$((min / 60))
  local m=$((min % 60))
  echo "${h}h ${m}min"
}

get_battery_percent() {
  upower -i /org/freedesktop/UPower/devices/battery_BAT0 \
    | awk '/percentage/ {gsub("%",""); printf "%d\n", $2}'
}

# ===================== STATUS =====================

send_status() {
  echo "[STATUS] $(date '+%F %T') /status recebido"

  info=$(btc getblockchaininfo)
  if [[ -z "$info" ]]; then
    send_telegram "⚠️ <b>Não foi possível obter informações do node no momento.</b>"
    return
  fi

  blocks=$(echo "$info" | jq -r .blocks)
  headers=$(echo "$info" | jq -r .headers)
  progress_raw=$(echo "$info" | jq -r .verificationprogress)

  percent_sync=$(printf "%.2f" "$(echo "$progress_raw * 100" | bc -l)")
  battery=$(get_battery_percent)

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

  send_telegram "📡 <b>Bitcoin Node Status</b>
<b>Progresso:</b> ${percent_sync}%
<b>Blocos:</b> ${blocks} / ${headers}
<b>Velocidade:</b> ${speed} blocos/min
<b>Tempo restante:</b> ${tempo_restante}
<b>ETA:</b> ${eta}
<b>Bateria:</b> ${battery}%"

  cat > "$STATE_FILE" <<EOF
prev_blocks=$blocks
prev_time=$now
EOF
}

# ===================== SYSINFO =====================

send_sysinfo() {
  echo "[SYSINFO] $(date '+%F %T') /sysinfo recebido"

  disk_used=$(df -h / | awk 'NR==2 {print $3}')
  disk_total=$(df -h / | awk 'NR==2 {print $2}')

  ram_used=$(free -h | awk '/Mem:/ {print $3}')
  ram_total=$(free -h | awk '/Mem:/ {print $2}')

  cpu=$(top -bn1 | awk '/Cpu\(s\)/ {printf "%.1f", $2+$4}')

  battery=$(get_battery_percent)

  send_telegram "🧠 <b>System Info</b>
<b>Storage:</b> ${disk_used} / ${disk_total}
<b>RAM:</b> ${ram_used} / ${ram_total}
<b>CPU:</b> ${cpu}%
<b>Bateria:</b> ${battery}%"
}

# ===================== HELP =====================

send_help() {
  echo "[HELP] $(date '+%F %T') /help recebido"

  send_telegram "📖 <b>Comandos disponíveis</b>
<b>/status</b> — Status completo do node
<b>/help</b> — Mostra esta ajuda
<b>/sysinfo</b> — Informações do sistema"
}


# ===================== LOOP =====================

if ! check_rpc; then
  sleep 10
  continue
fi

echo "[INIT] Status listener iniciado"

while true; do
  last_update_id=$(cat "$LAST_UPDATE_FILE" 2>/dev/null || echo 0)

  response=$(curl -s "https://api.telegram.org/bot${TELEGRAM_TOKEN}/getUpdates?offset=$((last_update_id + 1))")

  updates=$(echo "$response" | jq -c '.result[]')
  [[ -z "$updates" ]] && sleep 5 && continue

  for update in $updates; do
    update_id=$(echo "$update" | jq '.update_id')
    message=$(echo "$update" | jq -r '.message.text // empty')

    echo "[CMD] $(date '+%F %T') comando recebido: '$message'"

    case "$message" in 
      "/status")
        send_status
        ;;
      "/help")
    	send_help
    	;;
      "/sysinfo")
    	send_sysinfo
    	;;
    esac

    echo "$update_id" > "$LAST_UPDATE_FILE"
  done
done
