# Contrato GraphQL planejado — MS-B

> O arquivo `contracts/schema.graphql` permanece vazio nesta fase. Este documento registra o desenho para revisão.

## Queries principais

- `clients(filter, first, after)`
- `client(id)`
- `machines(filter, first, after)`
- `machine(id)`
- `agents(filter, first, after)`
- `jobs(filter, first, after)`
- `job(id)`
- `executions(filter, first, after)`
- `execution(id)`
- `commands(filter, first, after)`
- `auditEvents(filter, first, after)`
- `fleetSummary(filter)`
- `failureSummary(filter)`

## Agregados úteis

`fleetSummary` deve permitir obter, numa consulta, contagens de agentes online/offline/degradados, versões do AutoRunner, versões do SQLBackupAndFTP, jobs com falha recente e máquinas sem inventário atual.

## Regras

- paginação cursor-based;
- autorização em cada resolver;
- DataLoader/batching ou mecanismo equivalente para evitar N+1;
- limite de profundidade, complexidade e tamanho de resposta;
- introspection configurável conforme ambiente;
- nenhuma mutação crítica no MS-B: write path permanece no REST/MS-A;
- campos sensíveis não entram no schema público por conveniência.
