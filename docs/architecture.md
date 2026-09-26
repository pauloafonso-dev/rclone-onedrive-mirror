# Arquitetura

## Fluxo

```text
diretório local (SRC) -> rclone sync -> OneDrive:Backup (REMOTE)
```

O fluxo é unilateral. A origem local é a autoridade: criações e alterações são enviadas, exclusões locais são propagadas e objetos extras no destino são removidos pelo `sync`. Alterações feitas diretamente no OneDrive não são copiadas de volta.

O Bash concentra configuração, validações, logs e lock. O rclone compara e transfere os objetos. O `systemd --user` apenas agenda o serviço `Type=oneshot` a cada 30 minutos.

## Filtros

`backup-excludes.txt` é obrigatório e fica ao lado do script. `backup-excludes.local` pode adicionar regras específicas sem ser versionado. O script falha antes do rclone se um arquivo configurado não existir ou não puder ser lido.

O filtro público exclui somente lixo conhecido de cache/runtime. Dados de projetos, uploads, mídia, ambientes virtuais, backups e diretórios temporários não são excluídos por padrão.

## Proteções

- `SOURCE_MOUNTPOINT` é validado independentemente de `SRC`, permitindo, por exemplo, `SRC=/backup/documentos` e `SOURCE_MOUNTPOINT=/backup`;
- `SRC` e `SOURCE_MOUNTPOINT` são resolvidos com segurança, e a origem precisa ser o próprio mountpoint ou uma subárvore dele;
- a unit possui `ConditionPathIsMountPoint=/backup`, que deve ser ajustada quando o mountpoint mudar;
- `flock` impede execuções simultâneas;
- `--delete-after` mantém as exclusões para depois das transferências;
- `--max-delete` interrompe uma limpeza acima do limite;
- `--max-delete` é um limite de segurança, não um rollback transacional;
- `--delete-excluded` só é incluído quando explicitamente habilitado;
- `TRACK_RENAMES` controla opcionalmente `--track-renames` e permanece `false` por padrão;
- `--ignore-errors` não é utilizado.

## Mirror versus backup versionado

Este é um mirror, não um backup versionado: uma exclusão local pode ser refletida remotamente. `USE_ARCHIVE` é opcional e, quando habilitado, usa `--backup-dir` fora da árvore remota espelhada. Ele não é uma política de retenção completa e permanece desabilitado por padrão.

## Por que não `bisync`

O objetivo é que o computador seja a origem autoritativa. `rclone bisync` teria regras e estados próprios para conciliar alterações dos dois lados, o que não corresponde a esse contrato.
