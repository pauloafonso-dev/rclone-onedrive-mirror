#!/usr/bin/env bash
# onedrive-backup.sh
# Sincroniza /backup -> OneDrive:Home usando rclone
set -euo pipefail

# ---------- Configurações ----------
SRC="/backup"
REMOTE="OneDrive:Home"
ARCHIVE_REMOTE_ROOT="OneDrive:Home/backup-archive"
USE_ARCHIVE=false
TRANSFERS=4
CHECKERS=8
FAST_LIST="--fast-list"
BWLIMIT=""
LOG_DIR="$HOME/.local/share/onedrive-backup"
LOG_RETENTION_DAYS=30            # manter logs por N dias
LOG_FILE="$LOG_DIR/backup-$(date +%F).log"
LOCKFILE="$LOG_DIR/backup.lock"
RCLONE_BIN="$(command -v rclone || true)"
DRY_RUN=false
# ---------- Fim das configurações ----------

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"
: "${RCLONE_BIN:?rclone não encontrado. Execute 'rclone config' e instale rclone.}"

# Compress logs older than 0 days (rotaciona logs anteriores)
find "$LOG_DIR" -maxdepth 1 -type f -name 'backup-*.log' ! -name "$(basename "$LOG_FILE")" -mtime +0 -exec gzip -f {} \; || true

# remover arquivos de log (compressos ou não) antigos além da retenção
find "$LOG_DIR" -maxdepth 1 -type f \( -name 'backup-*.log' -o -name 'backup-*.log.gz' \) -mtime +"$LOG_RETENTION_DAYS" -print -delete || true

# Lock (impede múltiplas instâncias simultâneas)
exec 200>"$LOCKFILE"
flock -n 200 || {
  echo "$(date '+%F %T') - Another backup is running. Exiting." | tee -a "$LOG_FILE"
  exit 0
}

# Função de log
log() {
  echo "$(date '+%F %T') - $*" | tee -a "$LOG_FILE"
}

[ -n "${RCLONE_BIN:-}" ] || RCLONE_BIN="$(command -v rclone || true)"
RCLONE_OPTS=("--transfers" "$TRANSFERS" "--checkers" "$CHECKERS" "--log-file" "$LOG_FILE" "--log-level" "INFO" "--stats=10s" "--stats-one-line" "--use-json-log")
[ -n "$FAST_LIST" ] && RCLONE_OPTS+=("$FAST_LIST")
[ -n "$BWLIMIT" ] && RCLONE_OPTS+=("--bwlimit" "$BWLIMIT")
$DRY_RUN && RCLONE_OPTS+=("--dry-run")

if $USE_ARCHIVE; then
  BACKUP_DIR_REMOTE="$ARCHIVE_REMOTE_ROOT/$(date +%F_%H%M%S)"
  RCLONE_OPTS+=("--backup-dir" "$BACKUP_DIR_REMOTE")
fi

log "Starting OneDrive backup: $SRC -> $REMOTE"
log "Rclone: $RCLONE_BIN"
log "Options: transfers=$TRANSFERS checkers=$CHECKERS fast-list=${FAST_LIST:+yes} bwlimit=${BWLIMIT:-none} archive=${USE_ARCHIVE} dry-run=${DRY_RUN}"

if $DRY_RUN; then
  log "Performing dry-run (no changes will be made)."
fi

"$RCLONE_BIN" sync "$SRC" "$REMOTE" "${RCLONE_OPTS[@]}"
RCLONE_EXIT=$?

if [ $RCLONE_EXIT -eq 0 ]; then
  log "Backup completed successfully."
else
  log "Backup finished with non-zero exit code: $RCLONE_EXIT"
fi

exit $RCLONE_EXIT