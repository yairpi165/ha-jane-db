ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install PostgreSQL 16 and Redis 7
RUN apk add --no-cache \
    postgresql16 \
    postgresql16-contrib \
    redis

# Create data directories
RUN mkdir -p /data/postgres /data/redis /run/postgresql \
    && chown -R postgres:postgres /data/postgres /run/postgresql

# Copy startup script
COPY run.sh /
RUN chmod +x /run.sh

CMD ["/run.sh"]
