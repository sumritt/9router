#!/bin/sh

set -eu

DATA_DIR="${DATA_DIR:-/app/data}"

DB_FILE="${DATA_DIR}/db/data.sqlite"

SPACES_BUCKET="${SPACES_BUCKET:-}"
SPACES_PREFIX="${SPACES_PREFIX:-9router}"
SPACES_ENDPOINT="${SPACES_ENDPOINT:-}"

BACKUP_INTERVAL="${BACKUP_INTERVAL:-300}"

CURRENT_OBJECT="${SPACES_PREFIX}/current/data.tar.gz"

BACKUP_DATE="$(date '+%Y-%m-%d')"
BACKUP_TIME="$(date '+%H%M%S')"

BACKUP_OBJECT="${SPACES_PREFIX}/backups/${BACKUP_DATE}/${BACKUP_TIME}.tar.gz"

TMP_ROOT="/tmp/9router-backup"
TMP_DATA="${TMP_ROOT}/data"
TMP_DB="${TMP_DATA}/db/data.sqlite"
TMP_ARCHIVE="${TMP_ROOT}/data.tar.gz"

mkdir -p "${TMP_ROOT}"

backup_once() {

    echo "[9Router Backup] Starting backup..."

    if [ ! -f "${DB_FILE}" ]; then
        echo "[9Router Backup] Database does not exist yet."
        return 0
    fi

    rm -rf "${TMP_ROOT}"

    mkdir -p \
        "${TMP_DATA}/db"

    # -----------------------------------------------------
    # Copy everything except the live SQLite database.
    # -----------------------------------------------------

    tar \
        -C "${DATA_DIR}" \
        --exclude="./db/data.sqlite" \
        --exclude="./db/data.sqlite-wal" \
        --exclude="./db/data.sqlite-shm" \
        -czf "${TMP_ROOT}/data-extra.tar.gz" \
        .

    tar \
        -xzf "${TMP_ROOT}/data-extra.tar.gz" \
        -C "${TMP_DATA}"

    rm -f "${TMP_ROOT}/data-extra.tar.gz"

    # -----------------------------------------------------
    # Safe SQLite snapshot
    #
    # sqlite3 .backup creates a consistent snapshot while
    # the application is running.
    # -----------------------------------------------------

    echo "[9Router Backup] Creating SQLite snapshot..."

    sqlite3 "${DB_FILE}" \
        ".backup '${TMP_DB}'"

    # -----------------------------------------------------
    # Package complete DATA_DIR
    # -----------------------------------------------------

    tar \
        -C "${TMP_DATA}" \
        -czf "${TMP_ARCHIVE}" \
        .

    # -----------------------------------------------------
    # Upload immutable timestamped backup
    # -----------------------------------------------------

    echo "[9Router Backup] Uploading timestamped backup..."

    aws s3 cp \
        "${TMP_ARCHIVE}" \
        "s3://${SPACES_BUCKET}/${BACKUP_OBJECT}" \
        --endpoint-url "${SPACES_ENDPOINT}"

    # -----------------------------------------------------
    # Update current backup
    # -----------------------------------------------------

    echo "[9Router Backup] Updating current backup..."

    aws s3 cp \
        "${TMP_ARCHIVE}" \
        "s3://${SPACES_BUCKET}/${CURRENT_OBJECT}" \
        --endpoint-url "${SPACES_ENDPOINT}"

    echo "[9Router Backup] Backup completed:"
    echo "  ${BACKUP_OBJECT}"

    rm -rf "${TMP_ROOT}"
}


# ---------------------------------------------------------
# Backup loop
# ---------------------------------------------------------

echo "[9Router Backup] Worker started."
echo "[9Router Backup] Interval: ${BACKUP_INTERVAL}s"

# Give 9Router a little time to initialize first.
sleep 60

while true; do

    if backup_once; then
        :
    else
        echo "[9Router Backup] Backup failed."
    fi

    sleep "${BACKUP_INTERVAL}"

done