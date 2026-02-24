# Umbrel Portable Node Monitoring Suite

A small set of scripts to monitor and safely operate a portable Umbrel Bitcoin full node, especially on laptops or battery-powered systems.

Designed for unattended operation, remote supervision, and safe handling of power instability.

## Components

### `status_listener`

Telegram bot interface that responds to commands and provides real-time information about the node and system.

Features:

- Adaptive status reporting (IBD or fully synced)
- Blockchain height and sync state
- Peer count
- System metrics (CPU, RAM, disk, battery)
- Remote monitoring without exposing RPC ports


### `node_activity_monitor`

Monitors node activity after synchronization and sends alerts for important events.

Tracks:

- New blocks received (including avg fee rate in sat/vB)
- Long periods without new blocks
- Node lag behind the network
- Low or zero peer count
- Node restarts
- Periodic health status


### `watch_energy`

Monitors battery level and power conditions in portable environments.

Helps prevent unexpected shutdowns that could corrupt blockchain data.


### `safe_shutdown`

Safely stops the Bitcoin node and system to protect the blockchain database.

Ensures a clean shutdown of `bitcoind` before power-off.


## Configuration

Sensitive credentials (e.g., Telegram tokens) are stored in an external `config.env` file and must not be committed to version control.

Use `config.env.example` as a template.


## Typical Use Cases

- Operating a portable or temporary full node
- Running a node on a laptop or UPS
- Remote monitoring of node health
- Maintenance or migration scenarios
- Environments with unstable power


## Notes

This toolkit prioritizes reliability, low overhead, and data safety over complexity.
