# rclone-onedrive-mirror

Espelhamento unilateral de arquivos Linux para o Microsoft OneDrive usando Bash, rclone e `systemd --user`.

O projeto executa `rclone sync`: a origem local é a autoridade. Arquivos criados ou alterados são enviados, arquivos removidos localmente podem ser removidos no destino e objetos extras no destino são removidos pelo espelho. Alterações feitas diretamente no OneDrive não retornam para o computador.

## Funcionalidades

- origem e destino configuráveis;
- filtros de exclusão versionados e filtros locais opcionais;
- proteção contra filesystem desmontado;
- `flock` contra execuções simultâneas;
- `--delete-after`, `--max-delete` e `--track-renames` opcional;
- `DRY_RUN` e ativação explícita de `DELETE_EXCLUDED`;
- logs com rotação;
- timer de 30 minutos com `Persistent=true`.

## Requisitos

- Linux com Bash, `mountpoint`, `flock` e systemd user;
- rclone instalado e configurado com um remote OneDrive;
- rclone mínimo declarado: 1.60.1, versão em que as flags usadas por este projeto foram confirmadas; os testes desta rodada foram executados com a versão estável local 1.75.1.

O rclone pode ser instalado pelo pacote da distribuição, que recebe atualizações conforme o ciclo do sistema operacional, ou pela versão estável oficial, que normalmente disponibiliza releases mais recentes antes do pacote da distribuição. Em qualquer caso, confirme as flags locais com `rclone help flags` antes de atualizar a instalação do projeto.

## Arquitetura e instalação

Por padrão, a configuração preserva:

```text
SRC=/backup
REMOTE=OneDrive:Backup
SOURCE_MOUNTPOINT=/backup
```

Consulte [docs/architecture.md](docs/architecture.md) para o fluxo e [docs/deploy.md](docs/deploy.md) para instalação, rollout e atualização. O arquivo `backup-config.example` mostra as configurações disponíveis; copie-o para `backup-config` e ajuste os caminhos. Não coloque tokens ou credenciais nesse arquivo.

A precedência é: defaults do script < `backup-config` < variáveis de ambiente. Assim, `DRY_RUN=true DELETE_EXCLUDED=true MAX_DELETE=100000 ~/bin/onedrive-backup.sh` sobrescreve temporariamente a configuração local. Se `CONFIG_FILE` for informado, o arquivo precisa existir e ser legível; sem ele, o arquivo local opcional `backup-config` é usado quando existir.

Instalação rápida dos arquivos:

```bash
mkdir -p ~/bin ~/.config/systemd/user
cp onedrive-backup.sh backup-excludes.txt ~/bin/
if [ ! -e ~/bin/backup-config ]; then
  cp backup-config.example ~/bin/backup-config
fi
chmod +x ~/bin/onedrive-backup.sh
cp onedrive-backup.service onedrive-backup.timer ~/.config/systemd/user/
```

O service usa `%h/bin/onedrive-backup.sh` e possui `ConditionPathIsMountPoint=/backup`. Para outra origem, ajuste `SOURCE_MOUNTPOINT` no `backup-config` e a condição da unit conforme descrito na documentação.

## Exclusões e segurança

`backup-excludes.txt` exclui somente classes genéricas de cache, runtime, lixeira e arquivos de histórico já conhecidas. Para criar filtros locais:

```bash
cat > ~/bin/backup-excludes.local <<'EOF'
deploy/sessions/**
EOF
```

Depois configure `LOCAL_EXCLUDE_FILE="$SCRIPT_DIR/backup-excludes.local"` em `backup-config`. Esse arquivo não é versionado.

O arquivo principal de filtros é obrigatório. Se estiver ausente ou ilegível, o script aborta antes do rclone. `DELETE_EXCLUDED=false` é o padrão; habilite-o somente após revisar um dry-run. Na primeira reconciliação, `MAX_DELETE=1000` pode interromper uma limpeza legítima grande. Revise o dry-run e aumente o limite somente para uma execução real conscientemente autorizada. `--max-delete` é apenas um limite de segurança; não fornece rollback transacional.

`USE_ARCHIVE=false` é o padrão. Quando habilitado, `ARCHIVE_REMOTE_ROOT` precisa ficar fora da árvore `REMOTE`.

`TRACK_RENAMES=false` é o padrão do primeiro rollout. Defina-o como `true` somente após revisar a compatibilidade e o comportamento desejado.

## Operação

Execução manual:

```bash
~/bin/onedrive-backup.sh
```

O timer executa a cada 30 minutos. Durante rollout ou substituição dos arquivos, pare-o primeiro:

```bash
systemctl --user stop onedrive-backup.timer
```

Depois da instalação, recarregue as units, faça o dry-run, revise o log e só então reative o timer. Veja [docs/troubleshooting.md](docs/troubleshooting.md) para diagnóstico.

## Escopo

Este projeto não implementa `bisync`, GUI, Docker, inotify, múltiplos provedores ou notificações externas. A autenticação permanece sob responsabilidade do rclone e de seu `rclone.conf`.

## Licença

MIT. Consulte [LICENSE](LICENSE).
