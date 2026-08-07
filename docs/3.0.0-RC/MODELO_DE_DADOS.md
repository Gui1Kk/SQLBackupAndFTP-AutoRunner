# Modelo de domínio e dados — 3.0.0-RC

## Entidades

### Organization

Agrupa usuários, integrações, políticas e clientes visíveis. Campos conceituais: `id`, `name`, `slug`, `status`, `createdAt`.

### Client

Empresa/cliente atendido. `id`, `organizationId`, `code`, `name`, `status`, `metadata`.

### Site

Filial/local opcional. `id`, `clientId`, `name`, `timezone`, `metadata`.

### Machine

Computador/servidor. `id`, `clientId`, `siteId`, `displayName`, `hostname`, `os`, `architecture`, `tags`.

### Agent

Instalação do AutoRunner. `id`, `machineId`, `installId`, `version`, `channel`, `protocolVersion`, `status`, `lastSeenAt`, `enrolledAt`, `revokedAt`.

### SqlBackupInstallation

Snapshot da instalação detectada. `machineId`, `present`, `installPath`, `appVersion`, `cliVersion`, `serviceStatus`, `detectedAt`. Caminhos podem ser considerados dados de diagnóstico e ter exposição limitada conforme perfil.

### CapabilitySet

Conjunto versionado de capacidades do agente/SQLBackupAndFTP.

### Job

Representação central de um job descoberto. `id` central, `machineId`, `nativeJobId`, `name`, `type`, `scheduleState`, `lastNativeRunAt`, `inventoryVersion`, `source`, `confidence`.

### Execution

Execução observada ou disparada. `id`, `jobId`, `commandId?`, `source` (`remote`, `autorunner_boot`, `native`, `manual_observed`), `backupType`, timestamps, resultado, categoria de erro, exit code, resumo sanitizado.

### Command

Unidade durável de controle remoto. `id`, `agentId`, `type`, `payloadHash`, `idempotencyKey`, `status`, `actorType`, `actorId`, `createdAt`, `expiresAt`, `acceptedAt`, `completedAt`, `resultRef`.

### AuditEvent

Evento imutável de auditoria: ator, ação, recurso, escopo, IP/origem quando aplicável, timestamps, decisão de autorização e resultado.

### WebhookEndpoint / WebhookDelivery

Configuração e cada tentativa de entrega, sem armazenar segredo de assinatura em claro onde não necessário.

## Relações

```text
Organization 1─N Client 1─N Site
                    │
                    └─N Machine 1─1..N Agent(history)
                                 │
                                 ├─1 SqlBackupInstallation(snapshot)
                                 ├─N Job ─N Execution
                                 └─N Command

Organization 1─N WebhookEndpoint ─N WebhookDelivery
Organization 1─N AuditEvent
```

## Identidade nativa versus central

Nunca usar apenas nome do job como chave global. Um mesmo nome pode existir em máquinas diferentes. O domínio central usa UUID/ULID próprio e guarda `nativeJobId`/nome como referência da instalação.
