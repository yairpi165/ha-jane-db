#!/usr/bin/with-contenv bashio

PG_PASSWORD=$(bashio::config 'pg_password')
PG_DATABASE=$(bashio::config 'pg_database')

bashio::log.info "Starting Jane Database (PostgreSQL + Redis)..."

# -----------------------------------------------
# PostgreSQL initialization (first run only)
# -----------------------------------------------
if [ ! -f /data/postgres/PG_VERSION ]; then
    bashio::log.info "First run — initializing PostgreSQL..."
    su postgres -c "initdb -D /data/postgres"

    # Start temporarily for setup
    su postgres -c "pg_ctl start -D /data/postgres -l /data/postgres/setup.log -w"

    # Set password and create database
    su postgres -c "psql -c \"ALTER USER postgres PASSWORD '${PG_PASSWORD}';\""
    su postgres -c "psql -c \"CREATE DATABASE ${PG_DATABASE};\""

    su postgres -c "pg_ctl stop -D /data/postgres -w"
    bashio::log.info "PostgreSQL initialized with database '${PG_DATABASE}'"
fi

# -----------------------------------------------
# Configure PostgreSQL networking
# -----------------------------------------------
# Allow connections from other HA containers
sed -i "s/#listen_addresses = 'localhost'/listen_addresses = '*'/" /data/postgres/postgresql.conf

# Ensure pg_hba allows md5 auth from any host
if ! grep -q "host all all 0.0.0.0/0 md5" /data/postgres/pg_hba.conf; then
    echo "host all all 0.0.0.0/0 md5" >> /data/postgres/pg_hba.conf
fi

# Performance tuning for Pi 5 (16GB RAM)
cat >> /data/postgres/postgresql.conf << 'PGCONF'
# Jane tuning
shared_buffers = 256MB
effective_cache_size = 512MB
work_mem = 16MB
maintenance_work_mem = 64MB
max_connections = 20
PGCONF

# -----------------------------------------------
# Start Redis (background)
# -----------------------------------------------
bashio::log.info "Starting Redis..."
redis-server \
    --dir /data/redis \
    --daemonize yes \
    --bind 0.0.0.0 \
    --maxmemory 128mb \
    --maxmemory-policy allkeys-lru \
    --save 60 1000 \
    --save 300 100

bashio::log.info "Redis started on port 6379"

# -----------------------------------------------
# Start PostgreSQL (foreground — keeps container alive)
# -----------------------------------------------
bashio::log.info "Starting PostgreSQL on port 5432..."
exec su postgres -c "postgres -D /data/postgres"
