#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT_DIR/onedrive-backup.sh"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

MOCK_BIN="$TEST_ROOT/bin"
mkdir -p "$MOCK_BIN"

cat > "$MOCK_BIN/mountpoint" <<'EOF'
#!/usr/bin/env bash
if [[ "${MOCK_MOUNTPOINT:-1}" == 1 ]]; then
  exit 0
fi
exit 1
EOF

cat > "$MOCK_BIN/rclone" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "${MOCK_ARGS:?MOCK_ARGS não definido}"
exit "${MOCK_EXIT:-0}"
EOF

chmod +x "$MOCK_BIN/mountpoint" "$MOCK_BIN/rclone"

assert_contains() {
  grep -F -- "$2" "$1" >/dev/null || {
    printf 'Falha: esperado %s em %s\n' "$2" "$1" >&2
    exit 1
  }
}

assert_not_contains() {
  ! grep -F -- "$2" "$1" >/dev/null || {
    printf 'Falha: inesperado %s em %s\n' "$2" "$1" >&2
    exit 1
  }
}

make_config() {
  local config="$1"
  cat > "$config" <<EOF
SRC="$TEST_ROOT/source"
SOURCE_MOUNTPOINT="$TEST_ROOT/source"
REMOTE="OneDrive:Backup"
EXCLUDE_FILE="$TEST_ROOT/excludes"
LOCAL_EXCLUDE_FILE="$TEST_ROOT/local-excludes"
LOG_DIR="$TEST_ROOT/logs"
TRANSFERS=2
CHECKERS=3
FAST_LIST=true
DRY_RUN=false
DELETE_EXCLUDED=false
MAX_DELETE=7
TRACK_RENAMES=false
USE_ARCHIVE=false
RCLONE_BIN="$MOCK_BIN/rclone"
EOF
}

mkdir -p "$TEST_ROOT/source"
mkdir -p "$TEST_ROOT/source/documentos" "$TEST_ROOT/outside"
printf '%s\n' '**/.git/**' > "$TEST_ROOT/excludes"
printf '%s\n' '**/deploy/sessions/**' > "$TEST_ROOT/local-excludes"

assert_remote_rejected() {
  local remote_value="$1"
  local label="$2"
  local remote_config="$TEST_ROOT/remote-$label-config"
  local remote_args="$TEST_ROOT/remote-$label-args"

  make_config "$remote_config"
  printf 'REMOTE=%q\n' "$remote_value" >> "$remote_config"
  if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$remote_config" MOCK_MOUNTPOINT=1 MOCK_ARGS="$remote_args" \
      "$SCRIPT" >/dev/null 2>&1; then
    printf 'Falha: REMOTE inválido aceito: %s\n' "$remote_value" >&2
    exit 1
  fi
  [[ ! -e "$remote_args" ]] || {
    printf 'Falha: rclone foi chamado com REMOTE inválido: %s\n' "$remote_value" >&2
    exit 1
  }
}

# Remotes com subpasta explícita são aceitos e normalizados.
remote_config="$TEST_ROOT/remote-valid-config"
make_config "$remote_config"
printf 'REMOTE=%q\n' 'OtherCloud:/Documents/' >> "$remote_config"
PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$remote_config" MOCK_MOUNTPOINT=1 MOCK_ARGS="$TEST_ROOT/remote-valid-args" \
  "$SCRIPT" >/dev/null
assert_contains "$TEST_ROOT/remote-valid-args" 'OtherCloud:Documents'

assert_remote_rejected "" empty
assert_remote_rejected "OneDrive:" root
assert_remote_rejected "OneDrive:/" root-slash
assert_remote_rejected "OneDrive:////" root-slashes
assert_remote_rejected "OneDrive:./" root-dot
assert_remote_rejected "$TEST_ROOT/local-destination" local
assert_remote_rejected "/tmp/arquivo:Backup" local-colon

# CONFIG_FILE explícito ausente aborta antes do rclone.
if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$TEST_ROOT/config-does-not-exist" MOCK_ARGS="$TEST_ROOT/config-args" \
    "$SCRIPT" >/dev/null 2>&1; then
  printf 'Falha: CONFIG_FILE ausente deveria abortar\n' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/config-args" ]] || {
  printf 'Falha: rclone foi chamado com CONFIG_FILE ausente\n' >&2
  exit 1
}

mkdir "$TEST_ROOT/config-directory"
if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$TEST_ROOT/config-directory" MOCK_ARGS="$TEST_ROOT/config-directory-args" \
    "$SCRIPT" >/dev/null 2>&1; then
  printf 'Falha: CONFIG_FILE ilegível deveria abortar\n' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/config-directory-args" ]] || {
  printf 'Falha: rclone foi chamado com CONFIG_FILE ilegível\n' >&2
  exit 1
}

# Arquivo principal de filtros ausente aborta antes do rclone.
missing_config="$TEST_ROOT/missing-config"
cat > "$missing_config" <<EOF
EXCLUDE_FILE="$TEST_ROOT/missing"
SRC="$TEST_ROOT/source"
SOURCE_MOUNTPOINT="$TEST_ROOT/source"
LOG_DIR="$TEST_ROOT/missing-logs"
RCLONE_BIN="$MOCK_BIN/rclone"
EOF
if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$missing_config" MOCK_ARGS="$TEST_ROOT/missing-args" \
    "$SCRIPT" >/dev/null 2>&1; then
  printf 'Falha: filtro ausente deveria abortar\n' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/missing-args" ]] || {
  printf 'Falha: rclone foi chamado com filtro ausente\n' >&2
  exit 1
}

# Um SOURCE_MOUNTPOINT não montado aborta antes do rclone.
mount_config="$TEST_ROOT/mount-config"
make_config "$mount_config"
if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$mount_config" MOCK_MOUNTPOINT=0 MOCK_ARGS="$TEST_ROOT/mount-args" \
    "$SCRIPT" >/dev/null 2>&1; then
  printf 'Falha: mountpoint ausente deveria abortar\n' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/mount-args" ]] || {
  printf 'Falha: rclone foi chamado sem mountpoint\n' >&2
  exit 1
}

# Configuração e flags de segurança são encaminhadas ao rclone mockado.
config="$TEST_ROOT/config"
make_config "$config"
args="$TEST_ROOT/args"
log_file="$TEST_ROOT/logs/backup-$(date +%F).log"
PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$config" DRY_RUN=true DELETE_EXCLUDED=true MAX_DELETE=11 TRACK_RENAMES=true \
  MOCK_MOUNTPOINT=1 MOCK_ARGS="$args" \
  "$SCRIPT" >/dev/null
assert_contains "$args" '--dry-run'
assert_contains "$args" '--delete-excluded'
assert_contains "$args" '--track-renames'
assert_contains "$args" '--delete-after'
assert_contains "$args" '--max-delete'
assert_contains "$args" '11'
assert_contains "$args" '--fast-list'
assert_contains "$args" "$TEST_ROOT/excludes"
assert_contains "$args" "$TEST_ROOT/local-excludes"
assert_not_contains "$args" '--ignore-errors'
assert_not_contains "$args" '--backup-dir'
assert_contains "$log_file" "dry-run=true"
assert_contains "$log_file" "delete-excluded=true"
assert_contains "$log_file" "max-delete=11"
assert_contains "$log_file" "track-renames=true"

# Overrides inversos: o arquivo ativa as opções, mas o ambiente as desativa.
inverse_config="$TEST_ROOT/inverse-config"
make_config "$inverse_config"
cat >> "$inverse_config" <<EOF
DRY_RUN=true
DELETE_EXCLUDED=true
MAX_DELETE=13
TRACK_RENAMES=true
EOF
inverse_args="$TEST_ROOT/inverse-args"
inverse_log="$TEST_ROOT/logs/backup-$(date +%F).log"
PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$inverse_config" DRY_RUN=false DELETE_EXCLUDED=false MAX_DELETE=17 TRACK_RENAMES=false \
  MOCK_MOUNTPOINT=1 MOCK_ARGS="$inverse_args" \
  "$SCRIPT" >/dev/null
assert_not_contains "$inverse_args" '--dry-run'
assert_not_contains "$inverse_args" '--delete-excluded'
assert_not_contains "$inverse_args" '--track-renames'
assert_contains "$inverse_args" '--max-delete'
assert_contains "$inverse_args" '17'
assert_contains "$inverse_log" "dry-run=false"
assert_contains "$inverse_log" "delete-excluded=false"
assert_contains "$inverse_log" "max-delete=17"
assert_contains "$inverse_log" "track-renames=false"

# Sem arquivo de configuração padrão, os defaults continuam disponíveis e os
# valores de ambiente podem configurar a execução.
default_args="$TEST_ROOT/default-args"
env -u CONFIG_FILE PATH="$MOCK_BIN:$PATH" SRC="$TEST_ROOT/source" \
  SOURCE_MOUNTPOINT="$TEST_ROOT/source" EXCLUDE_FILE="$TEST_ROOT/excludes" \
  LOG_DIR="$TEST_ROOT/default-logs" RCLONE_BIN="$MOCK_BIN/rclone" \
  MOCK_MOUNTPOINT=1 MOCK_ARGS="$default_args" "$SCRIPT" >/dev/null
assert_contains "$default_args" '--max-delete'
assert_contains "$default_args" '1000'
assert_not_contains "$default_args" '--track-renames'

# SRC pode ser o próprio mountpoint ou uma subpasta dele.
subdir_config="$TEST_ROOT/subdir-config"
make_config "$subdir_config"
cat >> "$subdir_config" <<EOF
SRC="$TEST_ROOT/source/documentos"
SOURCE_MOUNTPOINT="$TEST_ROOT/source"
EOF
PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$subdir_config" MOCK_MOUNTPOINT=1 MOCK_ARGS="$TEST_ROOT/subdir-args" \
  "$SCRIPT" >/dev/null

# SRC fora do mountpoint deve abortar antes do rclone.
outside_config="$TEST_ROOT/outside-config"
make_config "$outside_config"
cat >> "$outside_config" <<EOF
SRC="$TEST_ROOT/outside"
SOURCE_MOUNTPOINT="$TEST_ROOT/source"
EOF
if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$outside_config" MOCK_MOUNTPOINT=1 MOCK_ARGS="$TEST_ROOT/outside-args" \
    "$SCRIPT" >/dev/null 2>&1; then
  printf 'Falha: SRC fora do mountpoint deveria abortar\n' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/outside-args" ]] || {
  printf 'Falha: rclone foi chamado com SRC fora do mountpoint\n' >&2
  exit 1
}

# USE_ARCHIVE só aceita uma raiz fora da árvore espelhada.
archive_config="$TEST_ROOT/archive-config"
make_config "$archive_config"
cat >> "$archive_config" <<EOF
USE_ARCHIVE=true
ARCHIVE_REMOTE_ROOT="OneDrive:Backup-archive"
EOF
PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$archive_config" MOCK_MOUNTPOINT=1 MOCK_ARGS="$TEST_ROOT/archive-args" \
  "$SCRIPT" >/dev/null
assert_contains "$TEST_ROOT/archive-args" '--backup-dir'
assert_contains "$TEST_ROOT/archive-args" 'OneDrive:Backup-archive/'

bad_archive_config="$TEST_ROOT/bad-archive-config"
make_config "$bad_archive_config"
cat >> "$bad_archive_config" <<EOF
REMOTE="OneDrive:Backup/"
USE_ARCHIVE=true
ARCHIVE_REMOTE_ROOT="OneDrive:/Backup/archive"
EOF
if PATH="$MOCK_BIN:$PATH" CONFIG_FILE="$bad_archive_config" MOCK_MOUNTPOINT=1 MOCK_ARGS="$TEST_ROOT/bad-archive-args" \
    "$SCRIPT" >/dev/null 2>&1; then
  printf 'Falha: archive dentro da árvore deveria abortar\n' >&2
  exit 1
fi
[[ ! -e "$TEST_ROOT/bad-archive-args" ]] || {
  printf 'Falha: rclone foi chamado com archive inseguro\n' >&2
  exit 1
}

# Integração opcional: usa somente diretórios temporários e o rclone local.
RCLONE_REAL="$(command -v rclone || true)"
if [[ -n "$RCLONE_REAL" && -x "$RCLONE_REAL" ]]; then
  integration_src="$TEST_ROOT/integration-source"
  integration_dest="$TEST_ROOT/integration-destination"
  mkdir -p "$integration_src" "$integration_dest"

  # Fixture de filtros: arquivos proibidos na raiz e em uma subpasta.
  mkdir -p \
    "$integration_src/.git" \
    "$integration_src/.ruff_cache" \
    "$integration_src/.Trash-1000" \
    "$integration_src/.ipython/profile_default/security" \
    "$integration_src/wp-content/wflogs" \
    "$integration_src/deploy/sessions" \
    "$integration_src/nested/.git" \
    "$integration_src/nested/.ruff_cache" \
    "$integration_src/nested/.Trash-1000" \
    "$integration_src/nested/.ipython/profile_default/security" \
    "$integration_src/nested/wp-content/wflogs" \
    "$integration_src/nested/deploy/sessions"
  touch \
    "$integration_src/.git/config" \
    "$integration_src/.ruff_cache/cache.txt" \
    "$integration_src/.Trash-1000/trash.txt" \
    "$integration_src/.python_history" \
    "$integration_src/.ipython/profile_default/security/token" \
    "$integration_src/wp-content/wflogs/template.php" \
    "$integration_src/deploy/sessions/session.txt" \
    "$integration_src/nested/.git/config" \
    "$integration_src/nested/.ruff_cache/cache.txt" \
    "$integration_src/nested/.Trash-1000/trash.txt" \
    "$integration_src/nested/.python_history" \
    "$integration_src/nested/.ipython/profile_default/security/token" \
    "$integration_src/nested/wp-content/wflogs/template.php" \
    "$integration_src/nested/deploy/sessions/session.txt"
  printf 'root\n' > "$integration_src/keep-root.txt"
  printf 'nested\n' > "$integration_src/nested/keep-nested.txt"
  integration_local_excludes="$TEST_ROOT/integration-excludes.local"
  printf 'deploy/sessions/**\n' > "$integration_local_excludes"
  integration_listing="$TEST_ROOT/integration-listing"
  "$RCLONE_REAL" lsf "$integration_src" --recursive --files-only \
    --exclude-from "$ROOT_DIR/backup-excludes.txt" \
    --exclude-from "$integration_local_excludes" > "$integration_listing"
  assert_contains "$integration_listing" 'keep-root.txt'
  assert_contains "$integration_listing" 'nested/keep-nested.txt'
  assert_not_contains "$integration_listing" '.git/config'
  assert_not_contains "$integration_listing" '.ruff_cache/cache.txt'
  assert_not_contains "$integration_listing" '.Trash-1000/trash.txt'
  assert_not_contains "$integration_listing" '.python_history'
  assert_not_contains "$integration_listing" '.ipython/profile_default/security/token'
  assert_not_contains "$integration_listing" 'wp-content/wflogs/template.php'
  assert_not_contains "$integration_listing" 'deploy/sessions/session.txt'

  printf 'v1\n' > "$integration_src/example.txt"
  "$RCLONE_REAL" sync "$integration_src" "$integration_dest"
  [[ "$(< "$integration_dest/example.txt")" == "v1" ]] || {
    printf 'Falha: integração local não transferiu arquivo\n' >&2
    exit 1
  }

  printf 'v2\n' > "$integration_src/example.txt"
  "$RCLONE_REAL" sync "$integration_src" "$integration_dest"
  [[ "$(< "$integration_dest/example.txt")" == "v2" ]] || {
    printf 'Falha: integração local não atualizou arquivo\n' >&2
    exit 1
  }

  rm "$integration_src/example.txt"
  "$RCLONE_REAL" sync "$integration_src" "$integration_dest"
  [[ ! -e "$integration_dest/example.txt" ]] || {
    printf 'Falha: integração local não propagou exclusão\n' >&2
    exit 1
  }
else
  printf 'test-backup.sh: integração real ignorada (rclone não encontrado)\n'
fi

printf 'test-backup.sh: OK\n'
