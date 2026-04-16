ARG BUILD_FROM
FROM ${BUILD_FROM}

# Install PostgreSQL 16, Redis 7, and pgvector
RUN apk add --no-cache \
    postgresql16 \
    postgresql16-contrib \
    redis \
    && apk add --no-cache --virtual .build-deps \
        make gcc musl-dev postgresql16-dev git \
    && git clone --branch v0.8.0 https://github.com/pgvector/pgvector.git /tmp/pgvector \
    && cd /tmp/pgvector && make && make install \
    && cd / && rm -rf /tmp/pgvector \
    && apk del .build-deps

# Create data directories
RUN mkdir -p /data/postgres /data/redis /run/postgresql \
    && chown -R postgres:postgres /data/postgres /run/postgresql

# Copy startup script and schema
COPY run.sh /
COPY schema.sql /
RUN chmod a+x /run.sh

CMD [ "/run.sh" ]
