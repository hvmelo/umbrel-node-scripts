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

STATE_FILE="/tmp/sync_monitor_state"

# ===================== FUNÇÕES =====================

check_rpc() {
  btc getblockchaininfo >/dev/null 2>&1
  return $?
}

notify_telegram() {
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

# ===================== INIT =====================

if [[ -f "$STATE_FILE" ]]; then
  source "$STATE_FILE"
else
  last_notified_percent=-1
  last_periodic_ts=0
  last_block=0
  last_time=$(date +%s)
fi

echo "[INIT] Sync monitor iniciado"
notify_telegram "📡 <b>Monitoramento de sync do Bitcoin iniciado</b>"

# ===================== LOOP =====================

if ! check_rpc; then
  sleep 10
  continue
fi

while true; do
  sleep "$SLEEP_INTERVAL"
  now=$(date +%s)

  info=$(btc getblockchaininfo)
  [[ -z "$info" ]] && continue

  blocks=$(echo "$info" | jq -r .blocks)
  headers=$(echo "$info" | jq -r .headers)
  progress_raw=$(echo "$info" | jq -r .verificationprogress)

  percent_real=$(echo "$progress_raw * 100" | bc -l)
  percent_floor=$(printf "%.0f" "$(echo "$percent_real / 1" | bc)")
  percent_fmt=$(printf "%.2f" "$percent_real")

  block_delta=$((blocks - last_block))
  time_delta=$((now - last_time))

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

  # ===== Percentual inteiro =====
  if (( percent_floor > last_notified_percent )); then
    echo "[EVENT] Percentual inteiro atingido: ${percent_floor}%"

    notify_telegram "📊 <b>Sync Bitcoin</b>
<b>Progresso:</b> ${percent_fmt}%
<b>Blocos:</b> ${blocks} / ${headers}
<b>Velocidade:</b> ${speed} blocos/min
<b>Tempo restante:</b> ${tempo_restante}
<b>ETA:</b> ${eta}"

    last_notified_percent=$percent_floor
  fi

  # ===== Atualização horária =====
  minutes_since=$(( (now - last_periodic_ts) / 60 ))
  if (( minutes_since >= PERIODIC_INTERVAL_MINUTES )); then
    echo "[EVENT] Atualização periódica (1h)"

    notify_telegram "🕓 <b>Atualização periódica</b>
<b>Progresso:</b> ${percent_fmt}%
<b>Blocos:</b> ${blocks} / ${headers}
<b>Velocidade:</b> ${speed} blocos/min
<b>Tempo restante:</b> ${tempo_restante}
<b>ETA:</b> ${eta}"

    last_periodic_ts=$now
  fi

  cat > "$STATE_FILE" <<EOF
last_notified_percent=${last_notified_percent}
last_periodic_ts=${last_periodic_ts}
last_block=${blocks}
last_time=${now}
EOF
done
