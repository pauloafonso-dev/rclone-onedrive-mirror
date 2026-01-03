# Backup Computador para OneDrive

## Propósito
- Sincronizar (**espelhar**) o conteúdo de `/backup` para o OneDrive usando **rclone**.
- Rodar automaticamente a cada **30 minutos** via `systemd --user` (timer).
- Rotacionar e comprimir logs automaticamente.

> Importante: este projeto usa `rclone sync`, então a pasta remota de destino deve ser tratada como **pasta de backup gerenciada pelo PC**. Evite colocar arquivos manualmente nela pelo OneDrive web, pois “extras” no destino podem ser removidos para manter o espelho.

---

## Pré-requisitos
- Linux (Zorin OS 18 neste projeto).
- `rclone` instalado e configurado com um remote chamado `OneDrive`.
- `systemd` user (usuário habilitado para timers).
- Script principal: `onedrive-backup.sh` (presente no diretório do projeto).

---

## Configuração atual (padrões do projeto)
- Origem: `/backup`
- Destino: `OneDrive:Backup` (pasta remota dedicada para o espelho)
- Timer: `OnCalendar=*:0/30` e `Persistent=true`
- Logs: `~/.local/share/onedrive-backup/`

---

## Instalação (passo a passo)

### 1) Verificar/instalar rclone
- Instalar: `sudo apt install rclone` (ou seguir docs do rclone).
- Configurar remote OneDrive:
  - `rclone config` → criar remote `OneDrive` → usar `rclone authorize "onedrive"` se necessário.
- Testar:
  ```bash
  rclone lsd OneDrive:
  rclone lsd OneDrive:Backup
  ```

### 2) Copiar o script e tornar executável
```bash
cp /backup/Dev/ScriptBkp/onedrive-backup.sh ~/bin/onedrive-backup.sh
chmod +x ~/bin/onedrive-backup.sh
```

> Se necessário, edite variáveis no topo do script (SRC, REMOTE, DRY_RUN, LOG_RETENTION_DAYS, etc).

### 3) Instalar as units do systemd (user)
```bash
mkdir -p ~/.config/systemd/user
cp /backup/Dev/ScriptBkp/onedrive-backup.service ~/.config/systemd/user/
cp /backup/Dev/ScriptBkp/onedrive-backup.timer ~/.config/systemd/user/
```

Ativar:
```bash
systemctl --user daemon-reload
systemctl --user enable --now onedrive-backup.timer
systemctl --user list-timers --all | grep -i onedrive
```

> Dica (para rodar mesmo sem login aberto): habilite *linger* do usuário:
```bash
sudo loginctl enable-linger "$USER"
loginctl show-user "$USER" -p Linger
```

---

## Uso

### Executar manualmente
```bash
~/bin/onedrive-backup.sh
```

### Forçar execução via systemd user
```bash
systemctl --user start onedrive-backup.service
```

### Ver status
```bash
systemctl --user status onedrive-backup.timer
systemctl --user status onedrive-backup.service
```

### Ver logs
```bash
journalctl --user -u onedrive-backup.service -f
tail -f ~/.local/share/onedrive-backup/backup-$(date +%F).log
```

---

## Comportamento do rclone
- O script usa `rclone sync` — transfere apenas alterações (comparação por size + mtime por padrão).
- Atenção: `sync` também **remove no destino** arquivos que foram excluídos na origem (ou que sejam “extras” no destino).
- Para comparação por checksum (quando suportado), adicionar `--checksum` às opções do rclone no script.

---

## Logs e rotação
- Local: `~/.local/share/onedrive-backup/`
- O script comprime logs antigos (`.log.gz`) e remove logs mais velhos que `LOG_RETENTION_DAYS` (configurável no script).

---

## Notas rápidas
- Para execução sem navegador, use `rclone authorize` em outra máquina com navegador e cole o JSON no `rclone config`.
- Ajuste `TRANSFERS`, `CHECKERS`, `BWLIMIT` e `USE_ARCHIVE` conforme necessidade.
- Revise `DRY_RUN` antes de ativar para garantir que sincronizações reais serão feitas.

---

## Licença
- Livre para uso pessoal. Ajustar conforme necessário.