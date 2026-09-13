#!/bin/sh
# ЛР №4: запуск Replica. Если каталог данных пуст, снимаем базовую копию Primary
# (pg_basebackup) и запускаем PostgreSQL в режиме standby: дальше он догоняет Primary
# по потоку WAL. Если данные уже есть, копия не снимается — сервер просто стартует.
set -e

PGDATA=${PGDATA:-/var/lib/postgresql/data}
PRIMARY_HOST=${PRIMARY_HOST:-postgres}
PRIMARY_PORT=${PRIMARY_PORT:-5432}
SLOT=${REPLICATION_SLOT:-replica_slot}

if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Replica: жду Primary $PRIMARY_HOST:$PRIMARY_PORT"
    until PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -tAc 'SELECT 1' > /dev/null 2>&1; do
        sleep 2
    done

    echo "Replica: создаю на Primary роль $REPLICATION_USER и слот $SLOT, если их ещё нет"
    PGPASSWORD="$POSTGRES_PASSWORD" psql -h "$PRIMARY_HOST" -p "$PRIMARY_PORT" \
        -U "$POSTGRES_USER" -d "$POSTGRES_DB" -v ON_ERROR_STOP=1 <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$REPLICATION_USER') THEN
        CREATE ROLE $REPLICATION_USER WITH REPLICATION LOGIN PASSWORD '$REPLICATION_PASSWORD';
    END IF;
    -- Слот гарантирует, что Primary не удалит WAL, которые Replica ещё не получила
    IF NOT EXISTS (SELECT 1 FROM pg_replication_slots WHERE slot_name = '$SLOT') THEN
        PERFORM pg_create_physical_replication_slot('$SLOT');
    END IF;
END
\$\$;
SQL

    echo "Replica: снимаю базовую копию Primary"
    mkdir -p "$PGDATA"
    chown postgres:postgres "$PGDATA"
    chmod 0700 "$PGDATA"
    # -R создаёт standby.signal и primary_conninfo, -Xs тянет WAL потоком во время копирования,
    # -S подключает слот репликации, -c fast не ждёт очередной контрольной точки
    su-exec postgres env PGPASSWORD="$REPLICATION_PASSWORD" pg_basebackup \
        --host="$PRIMARY_HOST" --port="$PRIMARY_PORT" --username="$REPLICATION_USER" \
        --pgdata="$PGDATA" --format=plain --wal-method=stream --write-recovery-conf \
        --slot="$SLOT" --checkpoint=fast --progress
    echo "Replica: копия снята, запускаю PostgreSQL"
fi

exec docker-entrypoint.sh "$@"
