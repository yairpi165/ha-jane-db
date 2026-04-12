# Jane Database — HA Add-on

PostgreSQL 16 + Redis 7 add-on for Home Assistant, powering Jane's memory system.

## What This Does

Runs PostgreSQL and Redis in a single HA-managed container on your Raspberry Pi. Jane uses these for structured memory storage (replacing flat Markdown files).

## Installation

1. Copy this folder to your Pi: `/addons/jane_db/`
2. Go to Settings → Apps → Check for updates
3. Find "Jane Database" → Install → Start

## Configuration

| Option | Default | Description |
|--------|---------|-------------|
| pg_password | jane_secure_password | PostgreSQL password |
| pg_database | jane | Database name |

## Ports

- **5432** — PostgreSQL
- **6379** — Redis

## Data

Persistent data stored in `/data/postgres` and `/data/redis`. Survives restarts and updates.

## After Installation

Run `schema.sql` to create the Jane tables:

```bash
psql -h localhost -U postgres -d jane -f schema.sql
```
