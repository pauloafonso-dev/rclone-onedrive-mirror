# Implantação

## Pré-requisitos

Instale o rclone pelo pacote da distribuição ou pela versão estável oficial. O pacote da distribuição é integrado ao ciclo de atualizações do sistema; a versão oficial normalmente chega mais cedo e exige atualização própria. A versão mínima declarada deste projeto é 1.60.1. Os testes desta rodada foram executados com a versão estável local 1.75.1; confirme as opções na instalação local com:

```bash
rclone version
rclone help flags
```

Configure o remote sem colocar credenciais no repositório:

```bash
rclone config
rclone lsd OneDrive:
```

## Instalação inicial

Na raiz do projeto:

```bash
mkdir -p ~/bin ~/.config/systemd/user
cp onedrive-backup.sh backup-excludes.txt ~/bin/
if [ ! -e ~/bin/backup-config ]; then
  cp backup-config.example ~/bin/backup-config
fi
chmod +x ~/bin/onedrive-backup.sh
cp onedrive-backup.service onedrive-backup.timer ~/.config/systemd/user/
```

Edite `~/bin/backup-config`. O exemplo mantém `SRC=/backup`, `SOURCE_MOUNTPOINT=/backup` e `REMOTE=OneDrive:Backup`. Para subpastas, configure `SRC` para a subpasta e `SOURCE_MOUNTPOINT` para o filesystem que realmente deve estar montado. O script também valida, após resolver os caminhos, que `SRC` está dentro desse mountpoint.

A precedência é: defaults do script < `backup-config` < variáveis de ambiente. Se `CONFIG_FILE` for informado, ele precisa existir e ser legível; sem essa variável, a ausência de `backup-config` mantém os defaults do script.

Se a origem mudar, edite também `ConditionPathIsMountPoint=` na unit instalada. O script sempre faz sua própria validação.

Para filtros específicos, crie um arquivo local e configure-o sem versioná-lo:

```bash
cat > ~/bin/backup-excludes.local <<'EOF'
deploy/sessions/**
EOF
```

No `backup-config`, use `LOCAL_EXCLUDE_FILE="$SCRIPT_DIR/backup-excludes.local"`. O filtro `deploy/sessions` é apenas um exemplo; confirme antes que esse conteúdo é descartável no seu ambiente.

## Rollout seguro

Pare o timer antes de substituir qualquer arquivo:

```bash
systemctl --user stop onedrive-backup.timer
cp onedrive-backup.sh backup-excludes.txt ~/bin/
cp onedrive-backup.service onedrive-backup.timer ~/.config/systemd/user/
chmod +x ~/bin/onedrive-backup.sh
systemctl --user daemon-reload
```

Antes de reativar o timer, faça uma inspeção sem alterações. Na primeira reconciliação, `MAX_DELETE=1000` pode interromper uma limpeza legítima grande. O valor alto abaixo serve apenas para permitir visualizar essa limpeza no dry-run; revise o log antes de escolher um limite para uma execução real e não o mantenha assim. `--max-delete` não fornece rollback transacional:

```bash
DRY_RUN=true DELETE_EXCLUDED=true MAX_DELETE=100000 \
  ~/bin/onedrive-backup.sh
```

Revise o log em `~/.local/share/onedrive-backup/`, especialmente filtros e exclusões. Depois escolha um limite normal e habilite `DELETE_EXCLUDED=true` somente se desejar remover do OneDrive objetos que passaram a ser filtrados.

`TRACK_RENAMES=false` é o padrão. Habilite `TRACK_RENAMES=true` somente se desejar adicionar `--track-renames` ao comando.

Ative o timer apenas após a revisão:

```bash
systemctl --user enable --now onedrive-backup.timer
systemctl --user list-timers --all | grep onedrive-backup
```

Não execute o service manualmente durante o rollout sem revisar o dry-run.

## Atualização, rollback e desinstalação

Para atualizar, pare o timer, substitua os arquivos, faça `daemon-reload`, repita o dry-run e reative o timer. Para rollback, pare o timer e restaure os arquivos da versão anterior antes do reload.

Para desinstalar o agendamento:

```bash
systemctl --user disable --now onedrive-backup.timer
rm ~/.config/systemd/user/onedrive-backup.service ~/.config/systemd/user/onedrive-backup.timer
systemctl --user daemon-reload
```

Os dados locais e remotos não são apagados por esse procedimento.
