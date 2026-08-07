# Matriz de capacidades do SQLBackupAndFTP

## Objetivo

Separar o que o AutoRunner **já consegue comprovar**, o que é tecnicamente inferível e o que depende de funcionalidade que o SQLBackupAndFTP não expõe oficialmente.

## Evidência disponível

A documentação oficial do SQLBackupAndFTP confirma o uso de `SqlBak.Job.Cli.exe -runJob -jobName <JobName>` para iniciar um job já configurado. A documentação histórica também descreve `-backupType` com `Full`, `FullCopy`, `Diff`, `TranLog` e `TranLogCopy`.

O AutoRunner 2.3.5 RC já contém descoberta de jobs por snapshot read-only do SQLite quando o esquema é reconhecido e fallback `-listJobs` de baixa confiança. O snapshot atual lê campos como nome, ID, tipo, `IsScheduled` e `LastRunAt` quando presentes.

Em resposta oficial da comunidade do SQLBackupAndFTP em 2022, a equipe informou que **não existe forma de criar um novo backup job por linha de comando** para a linha moderna do SQLBackupAndFTP e sugeriu outro produto (SqlBak) para esse cenário. Portanto, a 3.0.0-RC não deve prometer criação remota de job como funcionalidade universal.

## Matriz

| Capacidade | 2.3.5 local | Alvo 3.0.0 | Confiança | Observação |
|---|---:|---:|---|---|
| Detectar instalação | Sim | Sim | Alta | Multi-origem, sem pasta fixa. |
| Obter versão CLI/app | Sim | Sim | Alta | Metadata do executável. |
| Listar nomes de jobs | Sim | Sim | Média/Alta | SQLite validado ou fallback CLI. |
| Identificar tipo do job | Parcial | Sim | Média | Depende do schema local. |
| Saber se agendamento está ativo | Parcial | Sim | Média | Quando coluna reconhecida existir. |
| Obter última execução | Parcial | Sim | Média | Quando coluna reconhecida existir. |
| Executar job existente | Sim | Sim remoto | Alta | CLI oficialmente documentada. |
| Escolher tipo de backup no disparo | Sim | Sim remoto | Alta | CLI documentada. |
| Capturar exit code e stdout/stderr | Sim | Sim | Alta | Resultado do processo CLI. |
| Afirmar que arquivo chegou ao destino só pelo exit code | Não | Não | Alta | Requer evidência adicional. |
| Ler bases selecionadas no job | Não consolidado | Pesquisa | Baixa | Exige mapear schema/contrato com redaction. |
| Ler destinos e retenção | Não consolidado | Pesquisa | Baixa | Nunca exportar segredo. |
| Explicar causa completa da falha | Parcial | Pesquisa | Média | Combinar CLI, logs e histórico nativo. |
| Criar job SQLBackupAndFTP | Não | Capability-gated | Baixa | Não suportado oficialmente via CLI conhecida. |
| Alterar job SQLBackupAndFTP | Não | Capability-gated | Baixa | Não escrever diretamente em SQLite. |
| Excluir job SQLBackupAndFTP | Não | Capability-gated | Baixa | Depende de mecanismo suportado. |

## Regra de capability negotiation

Cada agente envia um objeto semelhante conceitualmente a:

```text
jobList=true
jobRun=true
jobRunBackupType=true
jobDetails=schedule,lastRun,type
jobCreate=false
jobUpdate=false
jobDelete=false
executionNativeHistory=unknown
```

A representação final será definida no contrato de implementação. O MS-A jamais despacha uma operação com capability falsa/ausente.

## Fontes externas consultadas

- https://sqlbackupandftp.com/docs/docs/job-settings/backup-job/scripts/cmd-scripts/
- https://sqlbackupandftp.com/blog/run-sqlbackupandftp-v11-command-line/
- https://community.sqlbackupandftp.com/t/create-new-backup-job-using-command-line/3762
- https://sqlbackupandftp.com/docs/docs/introduction-and-getting-started/how-to-create-and-configure-a-basic-backup-job/
