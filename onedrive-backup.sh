#!/usr/bin/env bash
# onedrive-backup.sh
# Sincroniza unilateralmente uma origem local para um destino rclone.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# Captura overrides explícitos antes dos defaults e do arquivo de configuração.
ENV_SRC_SET="${SRC+x}"
ENV_SRC="${SRC-}"
ENV_SOURCE_MOUNTPOINT_SET="${SOURCE_MOUNTPOINT+x}"
ENV_SOURCE_MOUNTPOINT="${SOURCE_MOUNTPOINT-}"
ENV_REMOTE_SET="${REMOTE+x}"
ENV_REMOTE="${REMOTE-}"
ENV_EXCLUDE_FILE_SET="${EXCLUDE_FILE+x}"
ENV_EXCLUDE_FILE="${EXCLUDE_FILE-}"
ENV_LOCAL_EXCLUDE_FILE_SET="${LOCAL_EXCLUDE_FILE+x}"
ENV_LOCAL_EXCLUDE_FILE="${LOCAL_EXCLUDE_FILE-}"
ENV_LOG_DIR_SET="${LOG_DIR+x}"
ENV_LOG_DIR="${LOG_DIR-}"
ENV_LOG_RETENTION_DAYS_SET="${LOG_RETENTION_DAYS+x}"
ENV_LOG_RETENTION_DAYS="${LOG_RETENTION_DAYS-}"
ENV_TRANSFERS_SET="${TRANSFERS+x}"
ENV_TRANSFERS="${TRANSFERS-}"
ENV_CHECKERS_SET="${CHECKERS+x}"
ENV_CHECKERS="${CHECKERS-}"
ENV_FAST_LIST_SET="${FAST_LIST+x}"
ENV_FAST_LIST="${FAST_LIST-}"
ENV_BWLIMIT_SET="${BWLIMIT+x}"
ENV_BWLIMIT="${BWLIMIT-}"
ENV_DRY_RUN_SET="${DRY_RUN+x}"
ENV_DRY_RUN="${DRY_RUN-}"
ENV_DELETE_EXCLUDED_SET="${DELETE_EXCLUDED+x}"
ENV_DELETE_EXCLUDED="${DELETE_EXCLUDED-}"
ENV_MAX_DELETE_SET="${MAX_DELETE+x}"
ENV_MAX_DELETE="${MAX_DELETE-}"
ENV_TRACK_RENAMES_SET="${TRACK_RENAMES+x}"
ENV_TRACK_RENAMES="${TRACK_RENAMES-}"
ENV_USE_ARCHIVE_SET="${USE_ARCHIVE+x}"
ENV_USE_ARCHIVE="${USE_ARCHIVE-}"
ENV_ARCHIVE_REMOTE_ROOT_SET="${ARCHIVE_REMOTE_ROOT+x}"
ENV_ARCHIVE_REMOTE_ROOT="${ARCHIVE_REMOTE_ROOT-}"
ENV_RCLONE_BIN_SET="${RCLONE_BIN+x}"
ENV_RCLONE_BIN="${RCLONE_BIN-}"
ENV_CONFIG_FILE_SET="${CONFIG_FILE+x}"
ENV_CONFIG_FILE="${CONFIG_FILE-}"

# ---------- Configurações padrão ----------
SRC="/backup"
SOURCE_MOUNTPOINT="/backup"
REMOTE="OneDrive:Backup"
EXCLUDE_FILE="$SCRIPT_DIR/backup-excludes.txt"
LOCAL_EXCLUDE_FILE=""
LOG_DIR="${HOME}/.local/share/onedrive-backup"
LOG_RETENTION_DAYS=30
TRANSFERS=4
CHECKERS=8
FAST_LIST=true
BWLIMIT=""
DRY_RUN=false
DELETE_EXCLUDED=false
MAX_DELETE=1000
TRACK_RENAMES=false
USE_ARCHIVE=false
ARCHIVE_REMOTE_ROOT="OneDrive:Backup-archive"
RCLONE_BIN=""
if [[ "$ENV_CONFIG_FILE_SET" == x ]]; then
  CONFIG_FILE="$ENV_CONFIG_FILE"
  CONFIG_FILE_EXPLICIT=true
else
  CONFIG_FILE="$SCRIPT_DIR/backup-config"
  CONFIG_FILE_EXPLICIT=false
fi
# ---------- Fim das configurações padrão ----------

if [[ "$CONFIG_FILE_EXPLICIT" == true ]]; then
  if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
    printf 'ERROR: arquivo CONFIG_FILE ausente ou ilegível: %s\n' "$CONFIG_FILE" >&2
    exit 1
  fi
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
elif [[ -e "$CONFIG_FILE" ]]; then
  if [[ ! -f "$CONFIG_FILE" || ! -r "$CONFIG_FILE" ]]; then
    printf 'ERROR: arquivo de configuração padrão ausente ou ilegível: %s\n' "$CONFIG_FILE" >&2
    exit 1
  fi
  # O arquivo é uma configuração local administrada pelo próprio usuário.
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

# Overrides de ambiente têm precedência sobre o arquivo de configuração.
[[ "$ENV_SRC_SET" == x ]] && SRC="$ENV_SRC"
[[ "$ENV_SOURCE_MOUNTPOINT_SET" == x ]] && SOURCE_MOUNTPOINT="$ENV_SOURCE_MOUNTPOINT"
[[ "$ENV_REMOTE_SET" == x ]] && REMOTE="$ENV_REMOTE"
[[ "$ENV_EXCLUDE_FILE_SET" == x ]] && EXCLUDE_FILE="$ENV_EXCLUDE_FILE"
[[ "$ENV_LOCAL_EXCLUDE_FILE_SET" == x ]] && LOCAL_EXCLUDE_FILE="$ENV_LOCAL_EXCLUDE_FILE"
[[ "$ENV_LOG_DIR_SET" == x ]] && LOG_DIR="$ENV_LOG_DIR"
[[ "$ENV_LOG_RETENTION_DAYS_SET" == x ]] && LOG_RETENTION_DAYS="$ENV_LOG_RETENTION_DAYS"
[[ "$ENV_TRANSFERS_SET" == x ]] && TRANSFERS="$ENV_TRANSFERS"
[[ "$ENV_CHECKERS_SET" == x ]] && CHECKERS="$ENV_CHECKERS"
[[ "$ENV_FAST_LIST_SET" == x ]] && FAST_LIST="$ENV_FAST_LIST"
[[ "$ENV_BWLIMIT_SET" == x ]] && BWLIMIT="$ENV_BWLIMIT"
[[ "$ENV_DRY_RUN_SET" == x ]] && DRY_RUN="$ENV_DRY_RUN"
[[ "$ENV_DELETE_EXCLUDED_SET" == x ]] && DELETE_EXCLUDED="$ENV_DELETE_EXCLUDED"
[[ "$ENV_MAX_DELETE_SET" == x ]] && MAX_DELETE="$ENV_MAX_DELETE"
[[ "$ENV_TRACK_RENAMES_SET" == x ]] && TRACK_RENAMES="$ENV_TRACK_RENAMES"
[[ "$ENV_USE_ARCHIVE_SET" == x ]] && USE_ARCHIVE="$ENV_USE_ARCHIVE"
[[ "$ENV_ARCHIVE_REMOTE_ROOT_SET" == x ]] && ARCHIVE_REMOTE_ROOT="$ENV_ARCHIVE_REMOTE_ROOT"
[[ "$ENV_RCLONE_BIN_SET" == x ]] && RCLONE_BIN="$ENV_RCLONE_BIN"

# O caminho do arquivo é definido pelo ambiente, não pelo conteúdo do arquivo.
if [[ "$ENV_CONFIG_FILE_SET" == x ]]; then
  CONFIG_FILE="$ENV_CONFIG_FILE"
else
  CONFIG_FILE="$SCRIPT_DIR/backup-config"
fi

LOG_FILE="$LOG_DIR/backup-$(date +%F).log"
LOCKFILE="$LOG_DIR/backup.lock"

bool_value() {
  case "$1" in
    true|false) return 0 ;;
    *) return 1 ;;
  esac
}

normalize_remote() {
  local value="$1"
  local remote_name
  local remote_path

  while [[ "$value" == */ ]]; do
    value="${value%/}"
  done
  [[ "$value" == *:* ]] || return 1

  remote_name="${value%%:*}"
  remote_path="${value#*:}"
  [[ -n "$remote_name" ]] || return 1
  [[ "$remote_name" != */* && "$remote_name" != *\\* ]] || return 1

  while [[ "$remote_path" == /* ]]; do
    remote_path="${remote_path#/}"
  done
  while [[ "$remote_path" == */ ]]; do
    remote_path="${remote_path%/}"
  done
  while [[ "$remote_path" == ./* ]]; do
    remote_path="${remote_path#./}"
  done
  while [[ "$remote_path" == */. ]]; do
    remote_path="${remote_path%/.}"
  done
  case "$remote_path" in
    ..|../*|*/..|*/../*) return 1 ;;
  esac
  [[ -n "$remote_path" && "$remote_path" != "." ]] || return 1

  NORMALIZED_REMOTE="$remote_name:$remote_path"
}

die() {
  log "ERROR: $*"
  exit 1
}

log() {
  echo "$(date '+%F %T') - $*" | tee -a "$LOG_FILE"
}

mkdir -p "$LOG_DIR"
touch "$LOG_FILE"

[[ -n "$SRC" ]] || die "SRC não pode estar vazio."
[[ -n "$SOURCE_MOUNTPOINT" ]] || die "SOURCE_MOUNTPOINT não pode estar vazio."
[[ -r "$EXCLUDE_FILE" ]] || die "Arquivo de exclusões ausente ou ilegível: $EXCLUDE_FILE"
if [[ -n "$LOCAL_EXCLUDE_FILE" ]]; then
  [[ -r "$LOCAL_EXCLUDE_FILE" ]] || die "Arquivo de exclusões local ausente ou ilegível: $LOCAL_EXCLUDE_FILE"
fi

bool_value "$FAST_LIST" || die "FAST_LIST deve ser true ou false."
bool_value "$DRY_RUN" || die "DRY_RUN deve ser true ou false."
bool_value "$DELETE_EXCLUDED" || die "DELETE_EXCLUDED deve ser true ou false."
bool_value "$TRACK_RENAMES" || die "TRACK_RENAMES deve ser true ou false."
bool_value "$USE_ARCHIVE" || die "USE_ARCHIVE deve ser true ou false."
[[ "$TRANSFERS" =~ ^[1-9][0-9]*$ ]] || die "TRANSFERS deve ser um inteiro positivo."
[[ "$CHECKERS" =~ ^[1-9][0-9]*$ ]] || die "CHECKERS deve ser um inteiro positivo."
[[ "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]] || die "LOG_RETENTION_DAYS deve ser um inteiro não negativo."
[[ "$MAX_DELETE" =~ ^[0-9]+$ ]] || die "MAX_DELETE deve ser um inteiro não negativo."

normalize_remote "$REMOTE" || die "REMOTE deve ser um remote com subpasta explícita; destinos locais e a raiz do remote não são aceitos: $REMOTE"
REMOTE="$NORMALIZED_REMOTE"

RCLONE_BIN="${RCLONE_BIN:-$(command -v rclone || true)}"
[[ -n "$RCLONE_BIN" ]] || die "rclone não encontrado. Instale-o e configure o remote separadamente."
[[ -x "$RCLONE_BIN" ]] || die "Executável rclone inválido ou não executável: $RCLONE_BIN"

if ! mountpoint -q "$SOURCE_MOUNTPOINT"; then
  die "A origem não está montada em SOURCE_MOUNTPOINT=$SOURCE_MOUNTPOINT; execução abortada."
fi

SOURCE_MOUNTPOINT_REAL="$(realpath -e -- "$SOURCE_MOUNTPOINT")" || die "SOURCE_MOUNTPOINT não pode ser resolvido: $SOURCE_MOUNTPOINT"
SRC_REAL="$(realpath -e -- "$SRC")" || die "Diretório de origem não encontrado: $SRC"
if [[ "$SOURCE_MOUNTPOINT_REAL" != "/" \
    && "$SRC_REAL" != "$SOURCE_MOUNTPOINT_REAL" \
    && "$SRC_REAL" != "$SOURCE_MOUNTPOINT_REAL/"* ]]; then
  die "SRC está fora de SOURCE_MOUNTPOINT: SRC=$SRC SOURCE_MOUNTPOINT=$SOURCE_MOUNTPOINT"
fi

if [[ "$USE_ARCHIVE" == true ]]; then
  [[ -n "$ARCHIVE_REMOTE_ROOT" ]] || die "ARCHIVE_REMOTE_ROOT não pode estar vazio quando USE_ARCHIVE=true."
  normalize_remote "$ARCHIVE_REMOTE_ROOT" || die "ARCHIVE_REMOTE_ROOT deve ser um remote válido com subpasta explícita: $ARCHIVE_REMOTE_ROOT"
  ARCHIVE_REMOTE_ROOT="$NORMALIZED_REMOTE"
  if [[ "$ARCHIVE_REMOTE_ROOT" == "$REMOTE" || "$ARCHIVE_REMOTE_ROOT" == "$REMOTE/"* ]]; then
    die "ARCHIVE_REMOTE_ROOT não pode ficar dentro da árvore remota espelhada: $ARCHIVE_REMOTE_ROOT"
  fi
fi

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

RCLONE_OPTS=(
  "--transfers" "$TRANSFERS"
  "--checkers" "$CHECKERS"
  "--log-file" "$LOG_FILE"
  "--log-level" "INFO"
  "--stats=10s"
  "--stats-one-line"
  "--use-json-log"
  "--exclude-from" "$EXCLUDE_FILE"
  "--delete-after"
  "--max-delete" "$MAX_DELETE"
)
[[ "$FAST_LIST" == true ]] && RCLONE_OPTS+=("--fast-list")
[[ -n "$BWLIMIT" ]] && RCLONE_OPTS+=("--bwlimit" "$BWLIMIT")
[[ "$DRY_RUN" == true ]] && RCLONE_OPTS+=("--dry-run")
[[ "$DELETE_EXCLUDED" == true ]] && RCLONE_OPTS+=("--delete-excluded")
[[ "$TRACK_RENAMES" == true ]] && RCLONE_OPTS+=("--track-renames")
[[ -n "$LOCAL_EXCLUDE_FILE" ]] && RCLONE_OPTS+=("--exclude-from" "$LOCAL_EXCLUDE_FILE")

if [[ "$USE_ARCHIVE" == true ]]; then
  BACKUP_DIR_REMOTE="${ARCHIVE_REMOTE_ROOT%/}/$(date +%F_%H%M%S)"
  RCLONE_OPTS+=("--backup-dir" "$BACKUP_DIR_REMOTE")
fi

log "Starting OneDrive mirror: $SRC -> $REMOTE"
log "Configuration: source=$SRC destination=$REMOTE source-mountpoint=$SOURCE_MOUNTPOINT transfers=$TRANSFERS checkers=$CHECKERS fast-list=$FAST_LIST dry-run=$DRY_RUN delete-excluded=$DELETE_EXCLUDED max-delete=$MAX_DELETE track-renames=$TRACK_RENAMES use-archive=$USE_ARCHIVE config-file=$CONFIG_FILE excludes=$EXCLUDE_FILE${LOCAL_EXCLUDE_FILE:+ local-excludes=$LOCAL_EXCLUDE_FILE}"
log "Rclone: $RCLONE_BIN"

if [[ "$DRY_RUN" == true ]]; then
  log "Performing dry-run (no changes will be made)."
fi

set +e
"$RCLONE_BIN" sync "$SRC" "$REMOTE" "${RCLONE_OPTS[@]}"
RCLONE_EXIT=$?
set -e

if [[ "$RCLONE_EXIT" -eq 0 ]]; then
  log "Backup completed successfully."
else
  log "Backup finished with non-zero exit code: $RCLONE_EXIT"
fi

exit "$RCLONE_EXIT"
