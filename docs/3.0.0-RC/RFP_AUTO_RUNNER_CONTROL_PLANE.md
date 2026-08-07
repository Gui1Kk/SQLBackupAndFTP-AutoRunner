# RFP — AutoRunner Control Plane 3.0.0-RC

## 1. Identificação

**Projeto:** SQLBackupAndFTP AutoRunner — Remote Control Plane  
**Versão alvo:** 3.0.0-RC  
**Estado:** especificação e preparação de repositório  
**Escopo desta etapa:** documentação completa, requisitos, arquitetura e placeholders; **sem implementação dos microserviços**.

## 2. Contexto e problema

O AutoRunner 2.3.5 RC resolve o disparo local de jobs configurados no SQLBackupAndFTP, principalmente após boot, mas cada instalação continua isolada. Para suporte centralizado, hoje é necessário acessar a máquina, abrir o aplicativo ou coletar informações manualmente.

A 3.0.0-RC propõe transformar cada instalação do AutoRunner em um agente de borda conectado a um plano de controle. A central poderá responder perguntas como:

- quais clientes e máquinas estão online;
- qual versão do AutoRunner e SQLBackupAndFTP cada máquina usa;
- quais jobs existem e quais estão agendados;
- quando um job executou e qual foi o resultado;
- quais máquinas apresentam falhas recorrentes;
- qual foi a causa conhecida/observável da falha;
- disparar um job existente remotamente;
- coletar diagnóstico;
- atualizar o agente;
- integrar operações e eventos ao AlphaExpress.

A criação/edição de jobs do SQLBackupAndFTP permanece como objetivo de domínio, mas não será tratada como garantida enquanto o produto upstream não oferecer mecanismo suportado e validado.

## 3. Arquitetura

A solução é composta por **três microserviços independentes**, cada um responsável por uma fatia do produto e por um conjunto de tecnologias. Eles compartilham o domínio, mas sobem, são testados e são avaliados separadamente.

| Serviço | Tecnologias | Responsabilidade |
|---|---|---|
| **MS-A** | **REST**, **OpenAPI**, **Better Auth** | Porta de entrada de comandos e administração: autenticação, RBAC, organizações/clientes/máquinas, enrollment, commands e integrações. |
| **MS-B** | **GraphQL**, **Webhooks** | Consulta flexível de inventário, execuções, falhas e auditoria; emissão de webhooks para AlphaExpress/terceiros. |
| **MS-C** | **WebSocket** | Canal em tempo real entre o plano central e agentes; heartbeat, presença, despacho de comandos, progresso e eventos. |

O **AutoRunner Agent** é o componente local já existente que será evoluído. Ele nunca expõe REST na rede do cliente: inicia uma conexão WSS para o MS-C.

## 4. Escopo funcional

### 4.1 Dentro do escopo obrigatório

Inventário, presença, autenticação, autorização, listagem de jobs, execução remota de jobs existentes, status assíncrono de comandos, histórico, erros sanitizados, GraphQL de consulta, webhooks assinados, auditoria, diagnóstico remoto e integração com AlphaExpress.

### 4.2 Dentro do escopo condicionado

Criação/alteração/exclusão de job é condicionada a capability. A API pode ter o conceito e os endpoints reservados, mas o agente deve negar de forma explícita se a versão do SQLBackupAndFTP não fornecer mecanismo suportado.

### 4.3 Fora do escopo inicial

- editar diretamente o banco SQLite interno do SQLBackupAndFTP;
- copiar credenciais de banco/destino para a central;
- abrir porta HTTP no cliente;
- executar shell/PowerShell arbitrário recebido pela API;
- transformar o canal remoto em RDP genérico;
- permitir upload arbitrário de executáveis;
- substituir ferramentas oficiais de restore sem uma especificação própria.

## 5. Atores

| Ator | Papel |
|---|---|
| Suporte/administrador | Administra clientes, agentes e operações. |
| Operador | Consulta e executa jobs dentro do escopo autorizado. |
| Auditor | Consulta trilha de auditoria sem executar comandos. |
| AlphaExpress | Integração M2M via API key/webhook. |
| AutoRunner Agent | Executa localmente ações tipadas e envia telemetria. |
| SQLBackupAndFTP | Sistema local controlado apenas por interfaces/mecanismos validados. |

## 6. Requisitos

A lista normativa está em `REQUISITOS_FUNCIONAIS.md` e `REQUISITOS_NAO_FUNCIONAIS.md`. IDs devem ser preservados em issues, PRs, testes e matriz de rastreabilidade.

## 7. Interfaces

- MS-A: `REST_API_DRAFT.md` e futuramente `contracts/openapi.yaml`.
- MS-B: `GRAPHQL_DRAFT.md` e futuramente `contracts/schema.graphql`.
- MS-C: `WEBSOCKET_PROTOCOL_DRAFT.md`.

## 8. Persistência e eventos

O write model pertence ao MS-A. O MS-B usa read model/projeções. O MS-C não é fonte de verdade para comandos. O transporte interno deverá usar outbox/event bus para impedir o clássico erro “commit no banco funcionou, publicar evento falhou”.

## 9. Segurança

O canal remoto terá uma postura de segurança estrita: autenticação forte do agente, RBAC/ABAC, autorização por objeto, rate limiting, idempotência, TTL, auditoria, redaction e proteção contra SSRF em webhooks.

A política de ACL local da 3.0.0-RC é deliberadamente permissiva por decisão de produto e está registrada separadamente como risco aceito. Isso não reduz os requisitos de autenticação/autorização do plano central.

## 10. Critérios de aceitação da arquitetura

1. Nenhuma porta inbound no cliente.
2. Agente continua executando automação local sem central.
3. Um comando remoto é auditável de ponta a ponta.
4. Replay não duplica execução.
5. Operador não acessa objetos fora de seu tenant/escopo.
6. Agente offline é um estado normal, não perda de dados.
7. Criação de job não é simulada quando upstream não suporta.
8. Dados sensíveis não aparecem em inventário/log por padrão.
9. GraphQL e WebSocket possuem limites de abuso.
10. AlphaExpress consegue integrar sem possuir credencial de usuário humano.
11. ACL 3.0.0-RC concede `FullControl` a todas as identidades definidas no ADR-003 e o gate falha se alguma estiver abaixo disso.

## 11. Entregáveis desta fase

- especificação RFP;
- arquitetura;
- RF/RNF;
- casos de uso;
- modelo de dados;
- drafts REST/GraphQL/WebSocket;
- matriz de capacidades SQLBackupAndFTP;
- modelo de ameaças;
- roadmap;
- ADRs;
- placeholders de implementação vazios.
