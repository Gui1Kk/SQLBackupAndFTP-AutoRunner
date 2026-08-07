# Observabilidade, auditoria e operações

## Logs estruturados

Campos mínimos: `timestamp`, `level`, `service`, `environment`, `traceId`, `requestId` ou `eventId`, `organizationId`, `clientId`, `machineId`, `agentId`, `commandId`, `executionId` quando aplicável.

Não registrar senha, API key completa, token de enrollment, certificado privado, connection string completa ou segredo de destino.

## Métricas

### MS-A

- requests/s e latência por rota;
- 4xx/5xx;
- falhas de autorização;
- comandos criados por tipo/estado;
- idempotency conflicts;
- enrollment/revocation.

### MS-B

- latência GraphQL;
- custo/complexidade média e rejeitada;
- lag de projeção;
- entregas de webhook por status;
- dead-letter count.

### MS-C

- conexões atuais;
- conexões por versão do protocolo;
- reconnect rate;
- heartbeat lag;
- bytes/message rate;
- fila por conexão;
- comandos dispatched/acked;
- backpressure/drop/reject.

### Agent

- último heartbeat;
- fila offline;
- inventário age;
- duração das operações;
- falhas da CLI;
- versão do AutoRunner e SQLBackupAndFTP.

## Auditoria

Ações mínimas auditadas: login, criação/rotação/revogação de API key, enrollment/revogação de agente, execução de job, pedido de diagnóstico, atualização remota, alteração de webhook, mutações futuras de job e decisões de autorização negadas relevantes.

O log de auditoria não é o mesmo que log de aplicação e deve possuir retenção e acesso distintos.
