# Contrato REST planejado — MS-A

> Este arquivo é documentação de desenho. `contracts/openapi.yaml` permanece vazio nesta fase, conforme decisão de não iniciar código/contrato executável antes da aprovação da arquitetura.

Base futura: `/api/v1`.

## Recursos principais

| Método | Endpoint | Finalidade |
|---|---|---|
| GET | `/clients` | Listar clientes autorizados. |
| POST | `/clients` | Cadastrar cliente. |
| GET | `/clients/{clientId}` | Detalhar cliente. |
| GET | `/clients/{clientId}/machines` | Listar máquinas. |
| POST | `/clients/{clientId}/machines` | Pré-cadastrar máquina, quando necessário. |
| GET | `/machines/{machineId}` | Detalhar máquina/agente. |
| GET | `/machines/{machineId}/capabilities` | Consultar capacidades atuais. |
| POST | `/agents/enrollments` | Gerar enrollment token. |
| POST | `/agents/{agentId}/revoke` | Revogar agente. |
| POST | `/agents/{agentId}/inventory-refresh` | Solicitar inventário imediato. |
| POST | `/agents/{agentId}/diagnostics` | Solicitar diagnóstico. |
| POST | `/agents/{agentId}/updates` | Solicitar atualização do AutoRunner. |
| GET | `/machines/{machineId}/jobs` | Listar jobs do inventário corrente. |
| GET | `/jobs/{jobId}` | Detalhar job conhecido. |
| POST | `/jobs/{jobId}/executions` | Executar job. |
| POST | `/jobs` | Criar job, somente se capability permitir. |
| PATCH | `/jobs/{jobId}` | Alterar job, somente se capability permitir. |
| DELETE | `/jobs/{jobId}` | Excluir job, somente se capability permitir. |
| GET | `/commands/{commandId}` | Consultar estado de comando. |
| POST | `/commands/{commandId}/cancel` | Solicitar cancelamento quando suportado. |
| GET | `/executions/{executionId}` | Resultado detalhado. |
| GET | `/webhooks` | Listar endpoints. |
| POST | `/webhooks` | Cadastrar webhook. |
| PATCH | `/webhooks/{webhookId}` | Alterar webhook. |
| DELETE | `/webhooks/{webhookId}` | Remover webhook. |

## Semântica de comando

Operações remotas respondem `202 Accepted`. Corpo de resposta conceitual:

```json
{
  "commandId": "uuid",
  "status": "queued",
  "createdAt": "RFC3339",
  "expiresAt": "RFC3339"
}
```

## Erros

A API deve usar `application/problem+json` ou formato equivalente consistente com `type`, `title`, `status`, `code`, `detail`, `traceId`.

Códigos de domínio mínimos:

- `AGENT_OFFLINE`
- `AGENT_REVOKED`
- `CAPABILITY_NOT_SUPPORTED`
- `JOB_NOT_FOUND`
- `COMMAND_EXPIRED`
- `COMMAND_ALREADY_EXISTS`
- `FORBIDDEN_SCOPE`
- `INVENTORY_STALE`
- `SQLBACKUPANDFTP_NOT_FOUND`
- `AGENT_VERSION_UNSUPPORTED`

## Idempotência

`POST` de operações remotas deve aceitar `Idempotency-Key`. Repetição com mesmo ator, endpoint e payload retorna o comando original. Reutilização da chave com payload diferente retorna conflito.
