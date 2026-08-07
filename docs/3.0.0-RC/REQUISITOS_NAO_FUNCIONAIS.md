# Requisitos não funcionais — 3.0.0-RC

## Segurança

| ID | Requisito |
|---|---|
| RNF-001 | Todo tráfego externo deve usar HTTPS/WSS com TLS 1.2 ou superior; TLS 1.3 preferencial. |
| RNF-002 | Nenhuma porta de entrada deve ser exigida no cliente para o controle remoto. |
| RNF-003 | Agente deve possuir identidade exclusiva, revogável e rotacionável. |
| RNF-004 | Credenciais de usuários, API keys e credenciais de agente nunca devem ser registradas em log. |
| RNF-005 | API keys devem ser armazenadas usando representação não reversível apropriada ao mecanismo do provedor de autenticação. |
| RNF-006 | RBAC/ABAC deve ser aplicado em cada endpoint e resolver, incluindo autorização por objeto. |
| RNF-007 | IDs não devem ser considerados autorização; acesso deve validar tenant/cliente/máquina. |
| RNF-008 | Operações destrutivas ou de mutação sensível exigem permissão dedicada. |
| RNF-009 | Todos os comandos devem ter TTL, idempotency key e ator auditável. |
| RNF-010 | Payload de comando deve possuir tamanho máximo e schema estrito. |
| RNF-011 | WebSocket deve validar origem quando aplicável, autenticação, tamanho de mensagem, frequência e protocolo/subprotocol. |
| RNF-012 | Webhooks devem mitigar SSRF, bloquear ranges não permitidos e validar redirects. |
| RNF-013 | Dados sensíveis devem ser criptografados em repouso conforme capacidade da plataforma. |
| RNF-014 | Segredos locais persistidos pelo agente devem preferir DPAPI/armazenamento protegido do Windows. |
| RNF-015 | Dados de banco/destino coletados devem ser minimizados e sanitizados. |
| RNF-016 | O plano central não deve receber senhas de banco do SQLBackupAndFTP em texto puro. |
| RNF-017 | Auditoria de segurança deve ser append-only do ponto de vista da aplicação. |
| RNF-018 | O design deve ser testado contra OWASP API Security Top 10 2023. |
| RNF-019 | Dependências devem possuir inventário/SBOM e scanning automatizado antes de release. |
| RNF-020 | A política ACL permissiva definida pelo produto deve ser tratada como risco aceito e não como controle de segurança. |

## Confiabilidade e consistência

| ID | Requisito |
|---|---|
| RNF-021 | Comandos não podem depender apenas de memória do MS-C; estado deve ser durável. |
| RNF-022 | Entrega de eventos pode ser at-least-once, mas consumidores devem ser idempotentes. |
| RNF-023 | Um reconnect do agente não pode executar duas vezes o mesmo comando confirmado. |
| RNF-024 | Heartbeats perdidos não devem apagar inventário conhecido; apenas mudar estado de presença. |
| RNF-025 | Comandos expirados não devem executar após reconexão. |
| RNF-026 | Falha de MS-B não deve impedir o agente de manter sessão com MS-C ou MS-A aceitar comandos duráveis, dentro da arquitetura de tolerância definida. |
| RNF-027 | Reprocessamento de projeção do MS-B deve ser possível a partir de eventos/auditoria durável. |
| RNF-028 | Webhooks devem possuir retry persistente e dead-letter. |

## Desempenho e escala

| ID | Requisito |
|---|---|
| RNF-029 | Leituras REST simples: alvo P95 ≤ 300 ms em carga nominal, excluindo integrações externas. |
| RNF-030 | GraphQL de dashboard: alvo P95 ≤ 1 s para queries aprovadas. |
| RNF-031 | Comando para agente online: alvo de despacho P95 ≤ 5 s. |
| RNF-032 | Atualização de presença no painel: alvo ≤ 5 s após heartbeat/evento recebido. |
| RNF-033 | Arquitetura deve ser testável inicialmente com 5.000 conexões simultâneas de agentes sem redesign de protocolo. |
| RNF-034 | MS-C deve aplicar backpressure e limites por conexão. |
| RNF-035 | Paginação obrigatória para listas potencialmente não limitadas. |
| RNF-036 | GraphQL deve possuir limite de complexidade, profundidade e custo por identidade. |

## Disponibilidade e operação offline

| ID | Requisito |
|---|---|
| RNF-037 | Agente deve continuar executando a automação pós-boot local mesmo quando o plano central estiver indisponível. |
| RNF-038 | A indisponibilidade da nuvem/central não pode bloquear backups locais previamente configurados. |
| RNF-039 | Eventos offline devem usar fila local limitada por tamanho/idade. |
| RNF-040 | Reconexão deve usar jitter para evitar thundering herd após queda central. |

## Observabilidade

| ID | Requisito |
|---|---|
| RNF-041 | Todos os serviços devem emitir logs estruturados com `traceId`, `requestId/eventId`, sem segredos. |
| RNF-042 | Métricas mínimas: conexões ativas, heartbeats, comandos por estado, latência, erros, retries, webhooks e filas. |
| RNF-043 | Tracing distribuído deve correlacionar REST → comando → WebSocket → resultado → webhook. |
| RNF-044 | Alertas devem existir para crescimento de fila, taxa de falha, agentes offline anormais e erros de autenticação. |

## Compatibilidade e manutenção

| ID | Requisito |
|---|---|
| RNF-045 | Protocolo agente-servidor deve ser versionado explicitamente. |
| RNF-046 | Servidor deve suportar janela de compatibilidade de pelo menos uma versão anterior do protocolo durante rollout. |
| RNF-047 | Feature/capability negotiation deve impedir o servidor de enviar comando não suportado. |
| RNF-048 | Contratos REST devem ser documentados em OpenAPI quando a implementação começar. |
| RNF-049 | Contrato GraphQL deve ser versionado por política de depreciação e campos, não por quebra silenciosa. |
| RNF-050 | Mensagens WebSocket devem possuir `protocolVersion` e schema testado. |

## Privacidade e LGPD

| ID | Requisito |
|---|---|
| RNF-051 | Coletar somente dados necessários a suporte, operação e auditoria. |
| RNF-052 | Classificar quais campos podem conter dado pessoal, credencial ou nome de cliente. |
| RNF-053 | Definir retenção configurável para logs, execuções e auditoria. |
| RNF-054 | Exportação e exclusão de dados devem respeitar requisitos internos e legais aplicáveis. |
| RNF-055 | Diagnósticos devem passar por redaction antes do upload ao plano central. |

## Qualidade e release

| ID | Requisito |
|---|---|
| RNF-056 | MS-A, MS-B e MS-C devem subir e ser testados separadamente. |
| RNF-057 | Cada serviço deve possuir testes unitários, integração, contrato e segurança. |
| RNF-058 | Agent protocol deve possuir simulador/fuzzer de conexão e comandos. |
| RNF-059 | CI deve impedir merge se contratos, lint, testes, SAST ou validações críticas falharem. |
| RNF-060 | A 3.0.0-RC só poderá ser promovida após homologação real com múltiplas versões do SQLBackupAndFTP e ambientes offline/online. |
