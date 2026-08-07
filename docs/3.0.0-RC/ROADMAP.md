# Roadmap da 3.0.0-RC

## Fase 0 — documentação e preparação do repositório (esta etapa)

- atualizar repositório para a base 2.3.5 RC;
- definir arquitetura de três microserviços;
- requisitos funcionais e não funcionais;
- modelo de domínio;
- contratos conceituais REST/GraphQL/WebSocket;
- modelo de ameaças;
- capability matrix do SQLBackupAndFTP;
- criar arquivos de implementação **vazios**;
- nenhuma lógica da API implementada.

## Fase 1 — spike técnico

- validar stack de MS-A/MS-B/MS-C;
- Better Auth com Organization/API Key em ambiente mínimo;
- prova de conexão WSS agente → MS-C;
- enrollment de laboratório;
- simulator de agente;
- benchmark de conexões;
- nenhum comando destrutivo.

## Fase 2 — observabilidade read-only

- heartbeat;
- inventário de máquina;
- detecção SQLBackupAndFTP;
- listagem de jobs;
- histórico AutoRunner;
- dashboard central;
- GraphQL read model;
- webhooks somente informativos.

## Fase 3 — execução remota controlada

- comando `executeJob`;
- idempotência/TTL;
- RBAC;
- auditoria;
- telemetria de progresso e resultado;
- rate limits;
- homologação em clientes de teste.

## Fase 4 — manutenção remota

- refresh de inventário;
- diagnósticos;
- atualização do agente;
- revoke/re-enroll;
- alertas de versão.

## Fase 5 — mutação de job, somente se suportada

- pesquisa de mecanismo oficialmente suportado pelo SQLBackupAndFTP;
- criação/edição/exclusão só após contrato estável;
- se não houver mecanismo suportado, manter capabilities falsas e não implementar escrita direta no banco interno.

## Gate para 3.0.0-RC

A primeira RC funcional só deve ser publicada quando Fases 1 a 3 estiverem homologadas e o agente continuar funcional offline. Recursos da Fase 5 não bloqueiam a 3.0.0-RC se forem explicitamente reportados como não suportados.
