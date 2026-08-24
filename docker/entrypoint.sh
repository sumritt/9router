#!/bin/sh

set -eu

DATA_DIR="${DATA_DIR:-/app/data}"

DB_DIR="${DATA_DIR}/db"
DB_FILE="${DB_DIR}/data.sqlite"

SPACES_BUCKET="${SPACES_BUCKET:-}"
SPACES_PREFIX="${SPACES_PREFIX:-9router}"
SPACES_ENDPOINT="${SPACES_ENDPOINT:-}"
SPACES_REGION="${SPACES_REGION:-sgp1}"

RESTORE_OBJECT="${SPACES_PREFIX}/current/data.tar.gz"

echo "[9Router] DATA_DIR=${DATA_DIR}"

mkdir -p "${DATA_DIR}" "${DB_DIR}"

# ---------------------------------------------------------
# Restore from DigitalOcean Spaces
# ---------------------------------------------------------

if [ -n "${SPACES_BUCKET}" ] && \
   [ -n "${SPACES_ENDPOINT}" ] && \
   [ -n "${SPACES_ACCESS_KEY:-}" ] && \
   [ -n "${SPACES_SECRET_KEY:-}" ]; then

    if [ ! -f "${DB_FILE}" ]; then

        echo "[9Router] No local database found."

        RESTORE_FILE="/tmp/9router-restore.tar.gz"

        echo "[9Router] Checking DigitalOcean Spaces..."

        if aws s3api head-object \
            --bucket "${SPACES_BUCKET}" \
            --key "${RESTORE_OBJECT}" \
            --endpoint-url "${SPACES_ENDPOINT}" \
            >/dev/null 2>&1; then

            echo "[9Router] Backup found. Restoring..."

            aws s3 cp \
                "s3://${SPACES_BUCKET}/${RESTORE_OBJECT}" \
                "${RESTORE_FILE}" \
                --endpoint-url "${SPACES_ENDPOINT}"

            tar \
                -xzf "${RESTORE_FILE}" \
                -C "${DATA_DIR}"

            rm -f "${RESTORE_FILE}"

            echo "[9Router] Restore completed."

        else

            echo "[9Router] No backup found. Starting fresh."

        fi
    else
        echo "[9Router] Existing database found. Skipping restore."
    fi

else

    echo "[9Router] Spaces backup is not configured."
    echo "[9Router] Starting with local DATA_DIR only."

fi

# ---------------------------------------------------------
# Fix permissions
# ---------------------------------------------------------

chown -R node:node "${DATA_DIR}" 2>/dev/null || true

# ---------------------------------------------------------
# Start background backup worker
# ---------------------------------------------------------

if [ -n "${SPACES_BUCKET}" ] && \
   [ -n "${SPACES_ENDPOINT}" ] && \
   [ -n "${SPACES_ACCESS_KEY:-}" ] && \
   [ -n "${SPACES_SECRET_KEY:-}" ]; then

    echo "[9Router] Starting Spaces backup worker..."

    /app/scripts/backup.sh &

    BACKUP_PID=$!

    echo "[9Router] Backup worker PID=${BACKUP_PID}"

else

    echo "[9Router] Spaces backup worker disabled."

fi

# ---------------------------------------------------------
# Start 9Router as node user
# ---------------------------------------------------------

echo "[9Router] Starting application..."

exec su-exec node "$@"