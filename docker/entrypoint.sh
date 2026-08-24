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

# =========================================================
# AWS / DigitalOcean Spaces credentials
#
# Preferred:
#   AWS_ACCESS_KEY_ID
#   AWS_SECRET_ACCESS_KEY
#
# Also supports:
#   SPACES_ACCESS_KEY
#   SPACES_SECRET_KEY
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

DB_DIR="${DATA_DIR}/db"
DB_FILE="${DB_DIR}/data.sqlite"

RESTORE_OBJECT="${SPACES_PREFIX}/current/data.tar.gz"

RESTORE_FILE="/tmp/9router-restore.tar.gz"

# =========================================================
# Startup information
# =========================================================

echo "[9Router] DATA_DIR=${DATA_DIR}"

mkdir -p "${DATA_DIR}"
mkdir -p "${DB_DIR}"

# =========================================================
# Check Spaces configuration
# =========================================================

SPACES_ENABLED="false"

if [ -n "${SPACES_BUCKET}" ] && \
   [ -n "${SPACES_ENDPOINT}" ] && \
   [ -n "${AWS_ACCESS_KEY_ID:-}" ] && \
   [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then

    SPACES_ENABLED="true"

    echo "[9Router] DigitalOcean Spaces backup enabled."
    echo "[9Router] Bucket=${SPACES_BUCKET}"
    echo "[9Router] Prefix=${SPACES_PREFIX}"
    echo "[9Router] Endpoint=${SPACES_ENDPOINT}"

else

    echo "[9Router] WARNING: DigitalOcean Spaces is not fully configured."

    if [ -z "${SPACES_BUCKET}" ]; then
        echo "[9Router] Missing SPACES_BUCKET"
    fi

    if [ -z "${SPACES_ENDPOINT}" ]; then
        echo "[9Router] Missing SPACES_ENDPOINT"
    fi

    if [ -z "${AWS_ACCESS_KEY_ID:-}" ]; then
        echo "[9Router] Missing AWS_ACCESS_KEY_ID / SPACES_ACCESS_KEY"
    fi

    if [ -z "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        echo "[9Router] Missing AWS_SECRET_ACCESS_KEY / SPACES_SECRET_KEY"
    fi
fi

# =========================================================
# Restore from DigitalOcean Spaces
# =========================================================

if [ ! -f "${DB_FILE}" ]; then

    echo "[9Router] No local database found."

    if [ "${SPACES_ENABLED}" = "true" ]; then

        echo "[9Router] Checking DigitalOcean Spaces..."

        if aws s3api head-object \
            --bucket "${SPACES_BUCKET}" \
            --key "${RESTORE_OBJECT}" \
            --endpoint-url "${SPACES_ENDPOINT}" \
            >/dev/null 2>&1; then

            echo "[9Router] Backup found."
            echo "[9Router] Restoring ${RESTORE_OBJECT}..."

            rm -f "${RESTORE_FILE}"

            if aws s3 cp \
                "s3://${SPACES_BUCKET}/${RESTORE_OBJECT}" \
                "${RESTORE_FILE}" \
                --endpoint-url "${SPACES_ENDPOINT}"; then

                echo "[9Router] Backup downloaded."

            else

                echo "[9Router] ERROR: Failed to download backup."
                rm -f "${RESTORE_FILE}"

            fi

            if [ -f "${RESTORE_FILE}" ]; then

                echo "[9Router] Extracting backup..."

                if tar \
                    -xzf "${RESTORE_FILE}" \
                    -C "${DATA_DIR}"; then

                    echo "[9Router] Restore completed."

                else

                    echo "[9Router] ERROR: Failed to extract backup."

                    rm -f "${RESTORE_FILE}"

                    exit 1
                fi

                rm -f "${RESTORE_FILE}"
            fi

        else

            echo "[9Router] No backup found. Starting fresh."

        fi

    else

        echo "[9Router] Spaces backup unavailable."
        echo "[9Router] Starting with local storage."

    fi

else

    echo "[9Router] Existing database found."
    echo "[9Router] Skipping restore."

fi

# =========================================================
# Fix ownership
# =========================================================

echo "[9Router] Fixing data permissions..."

chown -R node:node "${DATA_DIR}" 2>/dev/null || true

# =========================================================
# Start backup worker
# =========================================================

if [ "${SPACES_ENABLED}" = "true" ]; then

    echo "[9Router] Starting Spaces backup worker..."

    /app/scripts/backup.sh &

    BACKUP_PID=$!

    echo "[9Router] Backup worker PID=${BACKUP_PID}"

else

    echo "[9Router] Spaces backup worker disabled."

fi

# =========================================================
# Start 9Router
# =========================================================

echo "[9Router] Starting application..."

exec su-exec node "$@"