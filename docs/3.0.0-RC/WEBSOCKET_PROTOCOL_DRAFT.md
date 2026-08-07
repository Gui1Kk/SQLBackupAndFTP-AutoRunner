# Protocolo WebSocket planejado — MS-C

## Canais

MS-C atenderá dois papéis separados por autenticação/subprotocol:

1. **Agent channel**: conexão de saída do AutoRunner Agent.
2. **UI realtime channel**: atualização do painel para usuários autenticados.

## Envelope conceitual

```json
{
  "protocolVersion": 1,
  "messageId": "uuid",
  "type": "command.executeJob",
  "sentAt": "RFC3339",
  "correlationId": "uuid",
  "payload": {}
}
```

## Mensagens do agente

- `hello`
- `heartbeat`
- `inventory.snapshot`
- `inventory.changed`
- `command.accepted`
- `command.rejected`
- `command.progress`
- `command.completed`
- `execution.started`
- `execution.completed`
- `diagnostic.completed`
- `agent.updating`

## Mensagens do servidor

- `welcome`
- `ping`
- `command.executeJob`
- `command.refreshInventory`
- `command.collectDiagnostics`
- `command.updateAgent`
- `command.cancel`
- `session.revoke`

## Regras de entrega

- `commandId` é durável fora do WebSocket;
- agente confirma recebimento antes da execução;
- reconexão inclui cursor/último ack conhecido;
- comandos expirados são recusados;
- comando já concluído com mesmo ID retorna o resultado conhecido e não é repetido;
- mensagens possuem tamanho máximo;
- heartbeat não carrega inventário completo a cada ciclo;
- inventário completo é snapshot periódico ou sob demanda, com delta opcional futuro.

## Presença

O estado online é derivado da conexão/heartbeat. “Offline” não significa falha do backup local. O painel deve separar `agentConnectivity` de `backupHealth`.
