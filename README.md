# Umbrel Portable Node Monitoring Suite

A small set of scripts to monitor and safely operate a portable Umbrel Bitcoin node during Initial Block Download (IBD), especially on laptops or battery-powered systems.

## Components

- status_listener — Telegram interface for checking node status
- sync_monitor — Tracks IBD progress and estimated completion time
- watch_energy — Monitors battery level and power conditions
- safe_shutdown — Safely stops the node to prevent data corruption

Designed for long-running sync operations without constant supervision.
