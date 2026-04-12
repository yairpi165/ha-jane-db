#!/bin/bash
set -e

# Read config from options.json
PG_PASSWORD=$(jq -r '.pg_password' /data/options.json)
PG_DATABASE=$(jq -r '.pg_database' /data/options.json)

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [Jane DB] $*"; }

log "Starting PostgreSQL + Redis..."

# -----------------------------------------------
# Fix permissions (HA mounts /data at runtime)
# -----------------------------------------------
mkdir -p /data/postgres /data/redis /run/postgresql
chown -R postgres:postgres /data/postgres /run/postgresql

# -----------------------------------------------
# PostgreSQL initialization (first run only)
# -----------------------------------------------
if [ ! -f /data/postgres/PG_VERSION ]; then
    log "First run — initializing PostgreSQL..."
    su postgres -c "initdb -D /data/postgres"

    su postgres -c "pg_ctl start -D /data/postgres -l /data/postgres/setup.log -w"
    su postgres -c "psql -c \"ALTER USER postgres PASSWORD '${PG_PASSWORD}';\""
    su postgres -c "psql -c \"CREATE DATABASE ${PG_DATABASE};\""
    # Run schema
    su postgres -c "psql -d ${PG_DATABASE} -f /schema.sql"

    su postgres -c "pg_ctl stop -D /data/postgres -w"

    log "PostgreSQL initialized with database '${PG_DATABASE}' + schema applied"
fi

# -----------------------------------------------
# Configure PostgreSQL networking
# -----------------------------------------------
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /data/postgres/postgresql.conf

if ! grep -q "host all all 0.0.0.0/0 md5" /data/postgres/pg_hba.conf; then
    echo "host all all 0.0.0.0/0 md5" >> /data/postgres/pg_hba.conf
fi

# Performance tuning (only add once)
if ! grep -q "# Jane tuning" /data/postgres/postgresql.conf; then
    cat >> /data/postgres/postgresql.conf << 'PGCONF'
# Jane tuning
shared_buffers = 256MB
effective_cache_size = 512MB
work_mem = 16MB
maintenance_work_mem = 64MB
max_connections = 20
PGCONF
fi

# -----------------------------------------------
# Apply schema (safe — uses IF NOT EXISTS)
# -----------------------------------------------
log "Applying schema..."
su postgres -c "pg_ctl start -D /data/postgres -l /data/postgres/startup.log -w"
su postgres -c "psql -d ${PG_DATABASE} -f /schema.sql" 2>&1 | while read line; do log "  $line"; done
su postgres -c "pg_ctl stop -D /data/postgres -w"

# -----------------------------------------------
# Start Redis (background)
# -----------------------------------------------
log "Starting Redis on port 6379..."
redis-server \
    --dir /data/redis \
    --daemonize yes \
    --bind 0.0.0.0 \
    --maxmemory 128mb \
    --maxmemory-policy allkeys-lru \
    --save 60 1000 \
    --save 300 100

# -----------------------------------------------
# Start PostgreSQL (foreground — keeps container alive)
# -----------------------------------------------
log "Starting PostgreSQL on port 5432..."
exec su postgres -c "postgres -D /data/postgres"
