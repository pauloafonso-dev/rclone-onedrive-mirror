# Troubleshooting

Consulte primeiro o log:

```bash
tail -n 100 ~/.local/share/onedrive-backup/backup-$(date +%F).log
systemctl --user status onedrive-backup.service onedrive-backup.timer
journalctl --user -u onedrive-backup.service -n 100 --no-pager
```

## Problemas comuns

- **permission denied:** confirme permissões de leitura e adicione apenas o caminho de runtime comprovado ao filtro local. Não use `--ignore-errors`.
- **OneDrive sem espaço:** verifique a cota no provedor e o log do rclone; o job deve ser corrigido antes de permitir exclusões.
- **Arquivos remotos não foram apagados:** o rclone não apaga o destino quando ocorreram erros de leitura. Corrija o erro e repita primeiro com dry-run.
- **Exit code 1:** erro genérico de operação; leia as primeiras mensagens ERROR do log.
- **Exit code 3:** diretório não encontrado; confirme `SRC`, `SOURCE_MOUNTPOINT` e os caminhos resolvidos.
- **Exit code 7:** erro fatal; autenticação ou configuração do remote podem ser causas, mas não são as únicas. Leia o log completo antes de corrigir ou repetir a operação.
- **OAuth:** renove a autenticação usando `rclone config` fora do rollout e nunca publique o `rclone.conf`.
- **Serviço não inicia:** confira `systemctl --user status` e o caminho `%h/bin/onedrive-backup.sh`; valide também `bash -n`.
- **Timer não executa:** use `systemctl --user list-timers --all` e confirme que ele foi reativado após o rollout.
- **Filesystem desmontado:** o service pode ser pulado pela condição da unit; a execução manual também aborta por `SOURCE_MOUNTPOINT`.
- **Sincronização demorada:** examine transfers/checkers, tamanho da árvore e logs. Não altere flags sem confirmar suporte na versão instalada.
- **Execução interrompida:** não conclua que o destino está consistente; faça uma nova inspeção com dry-run.
- **Diferenças local/remoto:** lembre que o destino é um espelho e que filtros e erros de leitura alteram o conjunto comparado.

Nunca publique logs reais, pois nomes de arquivos e caminhos podem revelar informações privadas.
