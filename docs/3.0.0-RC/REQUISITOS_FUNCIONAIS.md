# Requisitos funcionais — 3.0.0-RC

## Convenções

Prioridade: `MUST` obrigatório para a 3.0.0-RC, `SHOULD` desejável sem bloquear o primeiro RC, `MAY` evolução. Estados: `Planejado`, `Dependência externa`, `Experimental`.

## Identidade, clientes e máquinas

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-001 | MUST | Cadastrar organizações/tenants. | Planejado |
| RF-002 | MUST | Cadastrar clientes vinculados a uma organização. | Planejado |
| RF-003 | MUST | Cadastrar unidades/filiais opcionais por cliente. | Planejado |
| RF-004 | MUST | Registrar máquinas/servidores por cliente. | Planejado |
| RF-005 | MUST | Cada máquina possuir identificador estável independente de hostname. | Planejado |
| RF-006 | MUST | Permitir renomear rótulo amigável sem alterar identidade do agente. | Planejado |
| RF-007 | MUST | Exibir hostname, SO, arquitetura, versão do agente, versão do SQLBackupAndFTP e última atividade. | Planejado |
| RF-008 | MUST | Marcar agente como online, offline, degradado, bloqueado ou revogado. | Planejado |
| RF-009 | MUST | Manter histórico de versões do agente por máquina. | Planejado |

## Enrollment e conectividade

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-010 | MUST | Gerar token de enrollment de uso único e curta duração. | Planejado |
| RF-011 | MUST | Agente trocar token de enrollment por identidade permanente de dispositivo. | Planejado |
| RF-012 | MUST | Permitir revogar agente sem remover o cadastro histórico da máquina. | Planejado |
| RF-013 | MUST | Agente iniciar conexão WSS de saída; nenhuma porta de entrada será exigida no cliente. | Planejado |
| RF-014 | MUST | Agente enviar heartbeat periódico. | Planejado |
| RF-015 | MUST | Agente reconectar com exponential backoff + jitter. | Planejado |
| RF-016 | MUST | Eventos produzidos offline serem armazenados localmente dentro de limite configurável e enviados após reconexão. | Planejado |
| RF-017 | MUST | Servidor detectar conexão duplicada do mesmo `agentId` e aplicar política determinística. | Planejado |

## Descoberta e inventário do SQLBackupAndFTP

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-018 | MUST | Detectar SQLBackupAndFTP sem depender de caminho fixo. | Herdado/Planejado integração |
| RF-019 | MUST | Reportar caminho, versão da CLI, versão do aplicativo e serviço detectado sem expor credenciais. | Planejado |
| RF-020 | MUST | Reportar ausência do SQLBackupAndFTP como estado válido. | Planejado |
| RF-021 | MUST | Inventariar jobs encontrados e fonte/confiança da descoberta. | Planejado |
| RF-022 | MUST | Para cada job, reportar nome, ID quando disponível, tipo, agendamento quando disponível e última execução quando disponível. | Planejado |
| RF-023 | SHOULD | Reportar bancos incluídos no job quando for possível obter essa informação sem descriptografar/expor segredo. | Pesquisa |
| RF-024 | SHOULD | Reportar destinos de backup de forma sanitizada, sem tokens/senhas. | Pesquisa |
| RF-025 | SHOULD | Reportar políticas de retenção, compressão, criptografia e schedule quando o formato puder ser interpretado com segurança. | Pesquisa |
| RF-026 | MUST | Cada resposta de inventário incluir `capabilities` que declare operações realmente suportadas naquela máquina/versão. | Planejado |

## Execuções e histórico

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-027 | MUST | Consultar execuções iniciadas pelo AutoRunner e seu resultado. | Planejado |
| RF-028 | MUST | Registrar início, fim, duração, tipo de backup, exit code e resumo do resultado. | Planejado |
| RF-029 | MUST | Distinguir falha de despacho, falha da CLI, falha do job e resultado ainda não confirmado. | Planejado |
| RF-030 | MUST | Expor saída da CLI de forma sanitizada e limitada. | Planejado |
| RF-031 | SHOULD | Correlacionar execução com histórico nativo do SQLBackupAndFTP quando houver fonte confiável. | Pesquisa |
| RF-032 | SHOULD | Identificar causa categorizada de falha: conexão DB, autenticação, espaço, destino, rede, script, timeout, licença, serviço, desconhecida. | Pesquisa |
| RF-033 | MUST | Preservar erro bruto sanitizado para diagnóstico, limitado por tamanho e retenção. | Planejado |
| RF-034 | MUST | Consultar a timeline de execuções por cliente, máquina e job. | Planejado |

## Comandos remotos

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-035 | MUST | `POST` para solicitar execução de job existente. | Planejado/viável |
| RF-036 | MUST | Permitir escolher `Default`, `Full`, `FullCopy`, `Diff`, `TranLog` ou `TranLogCopy` quando suportado. | Planejado/viável |
| RF-037 | MUST | Retornar `202 Accepted` com `commandId`; operação não ficará presa à conexão HTTP. | Planejado |
| RF-038 | MUST | Consultar estado de comando (`queued`, `dispatched`, `accepted`, `running`, `succeeded`, `failed`, `cancelled`, `expired`, `rejected`). | Planejado |
| RF-039 | MUST | Comando possuir TTL e `idempotencyKey`. | Planejado |
| RF-040 | MUST | Reenvio da mesma idempotency key não duplicar execução. | Planejado |
| RF-041 | SHOULD | Permitir cancelamento apenas quando a operação local oferecer cancelamento seguro. | Pesquisa |
| RF-042 | MUST | Permitir solicitar refresh imediato do inventário. | Planejado |
| RF-043 | MUST | Permitir solicitar pacote de diagnóstico sanitizado. | Planejado |
| RF-044 | SHOULD | Permitir solicitar atualização do AutoRunner para versão aprovada. | Planejado |
| RF-045 | MUST | Toda ação remota registrar ator, origem, escopo, payload resumido e resultado. | Planejado |

## Criação, alteração e remoção de jobs

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-046 | SHOULD | Expor operação de criação de job no contrato de domínio. | Dependência externa |
| RF-047 | SHOULD | Expor alteração de job no contrato de domínio. | Dependência externa |
| RF-048 | SHOULD | Expor exclusão/desativação de job no contrato de domínio. | Dependência externa |
| RF-049 | MUST | MS-A negar operações de mutação quando `capabilities.jobCreate/jobUpdate/jobDelete` forem falsas. | Planejado |
| RF-050 | MUST | Agente não modificar diretamente `context.db` para criar/editar/excluir jobs na 3.0.0-RC. | Planejado |
| RF-051 | MUST | Se não existir API/CLI/formato oficialmente suportado, retornar erro de capacidade, não simular sucesso. | Planejado |

## GraphQL e painel central

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-052 | MUST | Consultar clientes com agregados de máquinas online/offline, jobs e falhas recentes. | Planejado |
| RF-053 | MUST | Consultar máquina com agente, SQLBackupAndFTP, jobs e execuções em uma única query. | Planejado |
| RF-054 | MUST | Permitir filtros por status, versão, falha, cliente e período. | Planejado |
| RF-055 | MUST | Paginação por cursor para coleções grandes. | Planejado |
| RF-056 | MUST | Limitar profundidade/complexidade de queries GraphQL. | Planejado |
| RF-057 | MUST | Resolver autorização por objeto em todos os resolvers. | Planejado |

## Webhooks e integrações

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-058 | MUST | Cadastrar endpoint de webhook por organização/integração. | Planejado |
| RF-059 | MUST | Eventos suportados: `agent.online`, `agent.offline`, `inventory.changed`, `job.execution.started`, `job.execution.succeeded`, `job.execution.failed`, `agent.version.outdated`, `command.failed`. | Planejado |
| RF-060 | MUST | Assinar webhook com HMAC e timestamp. | Planejado |
| RF-061 | MUST | Retry com backoff e dead-letter após limite. | Planejado |
| RF-062 | MUST | Incluir `eventId` idempotente. | Planejado |
| RF-063 | MUST | Bloquear destinos privados/loopback/metadados de cloud por padrão para mitigar SSRF. | Planejado |
| RF-064 | MUST | Permitir integração AlphaExpress via API key organizacional e webhooks. | Planejado |

## Atualização, manutenção e suporte

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-065 | MUST | Central visualizar versão do agente e canal da release. | Planejado |
| RF-066 | SHOULD | Central comparar versão aprovada e sinalizar drift. | Planejado |
| RF-067 | SHOULD | Operador solicitar atualização remota com confirmação/política. | Planejado |
| RF-068 | MUST | Atualização preservar `agentId` e enrollment. | Planejado |
| RF-069 | MUST | Rollback de versão do agente não apagar histórico central. | Planejado |
| RF-070 | MUST | Central permitir revogar dispositivo comprometido. | Planejado |

## ACL local obrigatória definida pelo produto

| ID | Pri. | Requisito | Estado |
|---|---|---|---|
| RF-071 | MUST | A árvore instalada do AutoRunner 3.0.0-RC conceder **Controle Total**, nunca apenas leitura/escrita/modificação, a `SYSTEM` e `Administradores`. | Decisão de produto |
| RF-072 | MUST | Conceder **Controle Total** ao usuário proprietário/instalador efetivo. | Decisão de produto |
| RF-073 | MUST | Conceder **Controle Total** a `Everyone/Todos` (`S-1-1-0`). | Decisão de produto |
| RF-074 | MUST | Conceder **Controle Total** a `Users` e `Authenticated Users`. | Decisão de produto |
| RF-075 | MUST | Conceder **Controle Total** a `ALL APPLICATION PACKAGES` e `ALL RESTRICTED APPLICATION PACKAGES`. | Decisão de produto |
| RF-076 | MUST | Conceder **Controle Total** a `CREATOR OWNER` e `OWNER RIGHTS`, com herança apropriada. | Decisão de produto |
| RF-077 | MUST | QA verificar as ACEs efetivas e a herança após instalação, reparo e atualização; a ausência de `FullControl` em qualquer identidade obrigatória deverá falhar o gate. | Planejado |
| RF-078 | MUST | Documentação de segurança registrar que a política acima permite modificação por identidades amplas de componentes potencialmente executados com privilégios elevados. | Planejado |
| RF-079 | MUST | A implementação de ACL preferir SIDs conhecidos aos nomes localizados do Windows. | Planejado |
| RF-080 | MUST | A política 3.0.0-RC não poderá ser reduzida silenciosamente para `Read`, `ReadAndExecute`, `Write` ou `Modify`. | Decisão de produto |
