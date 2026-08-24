#!/bin/sh

set -eu

# =========================================================
# 9Router configuration
# =========================================================

DATA_DIR="${DATA_DIR:-/app/data}"

SPACES_BUCKET="${SPACES_BUCKET:-9router}"
SPACES_PREFIX="${SPACES_PREFIX:-prod}"
SPACES_ENDPOINT="${SPACES_ENDPOINT:-}"
SPACES_REGION="${SPACES_REGION:-sgp1}"

BACKUP_INTERVAL="${BACKUP_INTERVAL:-300}"

# =========================================================
# AWS / DigitalOcean Spaces credentials
# =========================================================

if [ -z "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${SPACES_ACCESS_KEY:-}" ]; then
    export AWS_ACCESS_KEY_ID="${SPACES_ACCESS_KEY}"
fi

if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ] && [ -n "${SPACES_SECRET_KEY:-}" ]; then
    export AWS_SECRET_ACCESS_KEY="${SPACES_SECRET_KEY}"
fi

export AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-${SPACES_REGION}}"

# =========================================================
# Paths
# =========================================================

DB_FILE="${DATA_DIR}/db/data.sqlite"

TMP_ROOT="/tmp/9router-backup"
TMP_DATA="${TMP_ROOT}/data"
TMP_DB="${TMP_DATA}/db/data.sqlite"
TMP_ARCHIVE="${TMP_ROOT}/data.tar.gz"

# =========================================================
# Validate configuration
# =========================================================

if [ -z "${SPACES_BUCKET}" ] || \
   [ -z "${SPACES_ENDPOINT}" ] || \
   [ -z "${AWS_ACCESS_KEY_ID:-}" ] || \
   [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then

    echo "[9Router Backup] ERROR: DigitalOcean Spaces credentials/configuration missing."
    echo "[9Router Backup] Backup worker stopped."

    exit 1
fi

# =========================================================
# Backup function
# =========================================================

backup_once() {

    echo "[9Router Backup] Starting backup..."

    # -----------------------------------------------------
    # Check database
    # -----------------------------------------------------

    if [ ! -f "${DB_FILE}" ]; then

        echo "[9Router Backup] Database does not exist yet."
        echo "[9Router Backup] Skipping backup."

        return 0
    fi

    # -----------------------------------------------------
    # Generate timestamp for THIS backup
    # -----------------------------------------------------

    BACKUP_DATE="$(date '+%Y-%m-%d')"
    BACKUP_TIME="$(date '+%H%M%S')"

    BACKUP_OBJECT="${SPACES_PREFIX}/backups/${BACKUP_DATE}/${BACKUP_TIME}.tar.gz"
    CURRENT_OBJECT="${SPACES_PREFIX}/current/data.tar.gz"

    echo "[9Router Backup] Backup object:"
    echo "  ${BACKUP_OBJECT}"

    # -----------------------------------------------------
    # Clean temporary directory
    # -----------------------------------------------------

    rm -rf "${TMP_ROOT}"

    mkdir -p \
        "${TMP_DATA}/db"

    # -----------------------------------------------------
    # Copy non-database data
    #
    # We exclude SQLite live files because SQLite needs
    # a consistent snapshot.
    # -----------------------------------------------------

    echo "[9Router Backup] Preparing data files..."

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
    # SQLite consistent snapshot
    # -----------------------------------------------------

    echo "[9Router Backup] Creating SQLite snapshot..."

    if sqlite3 "${DB_FILE}" \
        ".backup '${TMP_DB}'"; then

        echo "[9Router Backup] SQLite snapshot created."

    else

        echo "[9Router Backup] ERROR: SQLite backup failed."

        rm -rf "${TMP_ROOT}"

        return 1
    fi

    # -----------------------------------------------------
    # Package complete DATA_DIR
    # -----------------------------------------------------

    echo "[9Router Backup] Creating archive..."

    if tar \
        -C "${TMP_DATA}" \
        -czf "${TMP_ARCHIVE}" \
        .; then

        echo "[9Router Backup] Archive created."

    else

        echo "[9Router Backup] ERROR: Failed to create archive."

        rm -rf "${TMP_ROOT}"

        return 1
    fi

    # -----------------------------------------------------
    # Upload timestamped backup
    # -----------------------------------------------------

    echo "[9Router Backup] Uploading timestamped backup..."

    if aws s3 cp \
        "${TMP_ARCHIVE}" \
        "s3://${SPACES_BUCKET}/${BACKUP_OBJECT}" \
        --endpoint-url "${SPACES_ENDPOINT}"; then

        echo "[9Router Backup] Timestamped backup uploaded."

    else

        echo "[9Router Backup] ERROR: Timestamped backup upload failed."

        rm -rf "${TMP_ROOT}"

        return 1
    fi

    # -----------------------------------------------------
    # Update current backup
    # -----------------------------------------------------

    echo "[9Router Backup] Updating current backup..."

    if aws s3 cp \
        "${TMP_ARCHIVE}" \
        "s3://${SPACES_BUCKET}/${CURRENT_OBJECT}" \
        --endpoint-url "${SPACES_ENDPOINT}"; then

        echo "[9Router Backup] Current backup updated."

    else

        echo "[9Router Backup] ERROR: Current backup upload failed."

        rm -rf "${TMP_ROOT}"

        return 1
    fi

    # -----------------------------------------------------
    # Cleanup
    # -----------------------------------------------------

    rm -rf "${TMP_ROOT}"

    echo "[9Router Backup] Backup completed successfully."
    echo "[9Router Backup] ${BACKUP_OBJECT}"
}

# =========================================================
# Worker
# =========================================================

echo "[9Router Backup] Worker started."
echo "[9Router Backup] Interval: ${BACKUP_INTERVAL}s"

# Give 9Router time to initialize and create DB.
sleep 60

while true; do

    if backup_once; then
        :
    else
        echo "[9Router Backup] ERROR: Backup failed."
    fi

    sleep "${BACKUP_INTERVAL}"

done