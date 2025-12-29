# onedrive-backup

Propósito
- Sincronizar o conteúdo de /backup para OneDrive (pasta `OneDrive:Home`) usando rclone.
- Rodar automaticamente a cada 30 minutos via systemd --user.
- Rotacionar e comprimir logs automaticamente.

Pré-requisitos
- Linux (Zorin OS 18 neste projeto).
- rclone instalado e configurado com um remote chamado `OneDrive`.
- systemd user (usuário habilitado para timers).
- Script principal: `onedrive-backup.sh` (presente no diretório do projeto).

Instalação (passo a passo)
1. Verificar/instalar rclone:
   - Instalar: `sudo apt install rclone` ou seguir docs rclone.
   - Configurar remote OneDrive:
     - `rclone config` → criar remote `OneDrive` → usar `rclone authorize "onedrive"` se necessário.
     - Testar: `rclone lsd OneDrive:` e `rclone ls OneDrive:Home | head`

2. Copiar script e tornar executável:
   ```bash
   cp /backup/Dev/ScriptBkp/onedrive-backup.sh ~/bin/onedrive-backup.sh
   chmod +x ~/bin/onedrive-backup.sh
   ```
   - Se necessário, editar variáveis no topo do script (SRC, REMOTE, DRY_RUN, LOG_RETENTION_DAYS, etc).

3. Instalar units systemd user (criar se não existirem):
   - Criar diretório:
     ```bash
     mkdir -p ~/.config/systemd/user
     ```
   - Criar (ou copiar) os arquivos:
     - `~/.config/systemd/user/onedrive-backup.service` — unit que executa o script.
     - `~/.config/systemd/user/onedrive-backup.timer` — timer com `OnUnitActiveSec=30min` e `Persistent=true`.
   - Exemplo de ativação:
     ```bash
     systemctl --user daemon-reload
     systemctl --user enable --now onedrive-backup.timer
     ```

Uso
- Executar manualmente (testa e executa sync):
  ```bash
  ~/bin/onedrive-backup.sh
  ```
- Forçar execução via systemd user:
  ```bash
  systemctl --user start onedrive-backup.service
  ```
- Ver status:
  ```bash
  systemctl --user status onedrive-backup.timer
  systemctl --user status onedrive-backup.service
  ```
- Ver logs:
  ```bash
  journalctl --user -u onedrive-backup.service -f
  tail -f ~/.local/share/onedrive-backup/backup-$(date +%F).log
  ```

Comportamento do rclone
- O script usa `rclone sync` — apenas alterações são transferidas (comparação por size + mtime por padrão).
- Para comparação por checksum (quando suportado), adicionar `--checksum` às opções do rclone no script.
- Atenção: `sync` também remove arquivos no destino que foram excluídos na origem.

Logs e rotação
- Local: `~/.local/share/onedrive-backup/`
- O script comprime logs antigos (`.log.gz`) e remove arquivos (comprimidos ou não) mais velhos que `LOG_RETENTION_DAYS` (configurável no script).

Notas rápidas
- Para execução sem navegador, use `rclone authorize` em outra máquina com navegador e cole o JSON no `rclone config`.
- Ajuste `TRANSFERS`, `CHECKERS`, `BWLIMIT` e `USE_ARCHIVE` conforme necessidade.
- Revisar `DRY_RUN` antes de ativar para garantir que sincronizações reais serão feitas.

Licença
- Livre para uso pessoal. Ajustar conforme necessário.