ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install PostgreSQL 16, Redis 7, and pgvector (Alpine native package)
RUN apk add --no-cache \
    postgresql16 \
    postgresql16-contrib \
    postgresql-pgvector \
    redis

# Create data directories
RUN mkdir -p /data/postgres /data/redis /run/postgresql \
    && chown -R postgres:postgres /data/postgres /run/postgresql

# Copy startup script and schema
COPY run.sh /
COPY schema.sql /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
