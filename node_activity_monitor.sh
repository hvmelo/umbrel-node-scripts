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

STATE_FILE="/tmp/node_activity_state"

# ===================== FUNÇÕES =====================

btc() {
  "$BITCOIN_CLI" -datadir="$BITCOIN_DATADIR" "$@" 2>/dev/null
}

notify_telegram() {
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    --data-urlencode "text=$1" \
    -d parse_mode="HTML"
}

check_rpc() {
  btc getblockchaininfo >/dev/null 2>&1
  return $?
}

format_time() {
  local sec=$1
  printf "%dm %ds" $((sec/60)) $((sec%60))
}

# ===================== INIT STATE =====================

if [[ -f "$STATE_FILE" ]]; then
  source "$STATE_FILE"
else
  last_block_height=0
  last_block_time=0
  last_alert_ts=0
  last_periodic_ts=0
  last_uptime=0
fi

echo "[INIT] Node activity monitor iniciado"
notify_telegram "🛰️ <b>Node activity monitoring started</b>"

# ===================== MAIN LOOP =====================

while true; do
  sleep "$SLEEP_INTERVAL"
  now=$(date +%s)

  if ! check_rpc; then
    continue
  fi

  info=$(btc getblockchaininfo)
  net=$(btc getnetworkinfo)

  blocks=$(echo "$info" | jq -r .blocks)
  headers=$(echo "$info" | jq -r .headers)
  ibd=$(echo "$info" | jq -r .initialblockdownload)

  peers=$(echo "$net" | jq -r .connections)

  besthash=$(btc getbestblockhash)
  block=$(btc getblock "$besthash")
  block_time=$(echo "$block" | jq -r .time)
  txs=$(echo "$block" | jq -r .nTx)

  uptime=$(btc uptime)

  # =====================================================
  # 🧱 NEW BLOCK EVENT
  # =====================================================

  if (( blocks > last_block_height )); then

    age=0

    notify_telegram "🧱 <b>New Bitcoin Block</b>
<b>Height:</b> ${blocks}
<b>Txs:</b> ${txs}
<b>Peers:</b> ${peers}"

    last_block_height=$blocks
    last_block_time=$now
  fi

  # =====================================================
  # ⏱ NO BLOCK ALERT
  # =====================================================

  minutes_since=$(( (now - last_block_time) / 60 ))

  if (( minutes_since >= NO_BLOCK_ALERT_MINUTES )); then
    if (( now - last_alert_ts > NO_BLOCK_ALERT_MINUTES * 60 )); then

      notify_telegram "⚠️ <b>No new blocks for ${minutes_since} minutes</b>
Node may be stalled or disconnected."

      last_alert_ts=$now
    fi
  fi

  # =====================================================
  # 🌐 NODE BEHIND NETWORK
  # =====================================================

  behind=$((headers - blocks))

  if (( behind > 1 )); then
    notify_telegram "⚠️ <b>Node is ${behind} blocks behind network</b>"
  fi

  # =====================================================
  # 🔌 LOW PEERS ALERT
  # =====================================================

  if (( peers == 0 )); then
    notify_telegram "🚨 <b>No peers connected</b>"
  elif (( peers <= LOW_PEER_THRESHOLD )); then
    notify_telegram "⚠️ <b>Low peer count:</b> ${peers}"
  fi

  # =====================================================
  # 🔁 NODE RESTART DETECTION
  # =====================================================

  if (( last_uptime > 0 && uptime < last_uptime )); then
    notify_telegram "⚠️ <b>Bitcoin node restarted</b>"
  fi

  last_uptime=$uptime

  # =====================================================
  # 🕓 PERIODIC STATUS
  # =====================================================

  minutes_since_periodic=$(( (now - last_periodic_ts) / 60 ))

  if (( minutes_since_periodic >= PERIODIC_INTERVAL_MINUTES )); then

    age=$((now - block_time))

    notify_telegram "🟢 <b>Node OK</b>
<b>Height:</b> ${blocks}
<b>Peers:</b> ${peers}
<b>Last block:</b> $(format_time $age) ago"

    last_periodic_ts=$now
  fi

  # =====================================================
  # SAVE STATE
  # =====================================================

  cat > "$STATE_FILE" <<EOF
last_block_height=${last_block_height}
last_block_time=${last_block_time}
last_alert_ts=${last_alert_ts}
last_periodic_ts=${last_periodic_ts}
last_uptime=${last_uptime}
EOF

done
