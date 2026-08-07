# Arquitetura alvo — SQLBackupAndFTP AutoRunner 3.0.0-RC

## 1. Objetivo

A versão 3.0.0-RC transforma o SQLBackupAndFTP AutoRunner de um executor local pós-boot em um **agente de borda administrável remotamente**, mantendo a execução real dentro da máquina do cliente e adicionando um plano de controle central para consulta, auditoria e despacho de operações.

O objetivo é permitir que um aplicativo central, o AlphaExpress ou qualquer integração autorizada consiga visualizar clientes, computadores, instalações do SQLBackupAndFTP, jobs, execuções e falhas, além de solicitar operações remotas compatíveis com as capacidades do agente.

A arquitetura **não expõe uma API REST diretamente na máquina do cliente**. O agente inicia conexões de saída para o plano central por HTTPS/WSS. Isso evita abertura de portas de entrada em centenas ou milhares de ambientes, reduz dependência de NAT, VPN e regras de firewall e cria um ponto único de autenticação, autorização e auditoria.

## 2. Arquitetura

A solução é composta por **três microserviços independentes**, além do AutoRunner Agent instalado nas máquinas dos clientes. Os três serviços compartilham o domínio, mas sobem, são testados, versionados e podem escalar separadamente.

| Serviço | Tecnologias obrigatórias | Responsabilidade |
|---|---|---|
| **MS-A — Control API** | **REST**, **OpenAPI**, **Better Auth** | Porta de entrada administrativa. Autentica usuários e integrações, cadastra organizações/clientes/máquinas/agentes, expõe comandos e mutações, controla RBAC/ABAC, gera auditoria e publica comandos para execução. |
| **MS-B — Query & Events** | **GraphQL**, **Webhooks** | Consulta flexível e agregada da frota, jobs, execuções, falhas, métricas e auditoria. Publica webhooks assinados para AlphaExpress e sistemas terceiros. |
| **MS-C — Realtime Gateway** | **WebSocket** | Mantém conexões em tempo real com agentes e clientes de interface. Entrega comandos, recebe heartbeat, telemetria, progresso e resultados, e propaga mudanças ao painel em tempo real. |
| **AutoRunner Agent** | Windows x64, PowerShell 5.1 + launcher nativo existente | Descobre e interage localmente com SQLBackupAndFTP, executa comandos permitidos, coleta estado e envia eventos ao plano central. A conexão é sempre iniciada pelo agente para fora. |

### 2.1 Topologia lógica

```text
                         ┌──────────────────────────────┐
                         │      Usuário / Suporte      │
                         │ AlphaExpress / Integrações  │
                         └──────────────┬───────────────┘
                                        │ HTTPS
                   ┌────────────────────┴────────────────────┐
                   │                                         │
          ┌────────▼────────┐                       ┌────────▼────────┐
          │ MS-A Control API│                       │ MS-B Query/Event│
          │ REST/OpenAPI    │                       │ GraphQL/Webhooks│
          │ Better Auth     │                       │ Read model      │
          └────────┬────────┘                       └────────┬────────┘
                   │ comandos/eventos                         │ projeções
                   └────────────────┬─────────────────────────┘
                                    │
                            ┌───────▼────────┐
                            │ Event/Command  │
                            │ backbone       │
                            └───────┬────────┘
                                    │
                            ┌───────▼────────┐
                            │ MS-C Realtime  │
                            │ WebSocket/WSS  │
                            └───────┬────────┘
                                    │ conexão de saída do cliente
                     ───────────────┼──────────────────────── Internet
                                    │
                      ┌─────────────▼─────────────┐
                      │ AutoRunner Agent          │
                      │ máquina do cliente        │
                      └─────────────┬─────────────┘
                                    │ local
                 ┌──────────────────┴──────────────────┐
                 │ SQLBackupAndFTP                    │
                 │ SqlBak.Job.Cli + configuração local│
                 └─────────────────────────────────────┘
```

O “event/command backbone” é uma responsabilidade arquitetural, não uma quarta API pública. A implementação poderá usar uma fila/broker ou um mecanismo de outbox + banco, desde que preserve entrega, idempotência e ordenação documentadas.

## 3. Princípios

1. **Outbound-only no cliente.** Nenhuma porta HTTP, REST, GraphQL ou WebSocket de entrada será aberta no PC do cliente.
2. **Zero acesso direto do plano central ao SQLBackupAndFTP.** Toda ação local passa pelo agente.
3. **Capacidades negociadas.** A API não presume que todas as versões do SQLBackupAndFTP oferecem as mesmas operações.
4. **Comando assíncrono.** Operações remotas são jobs de comando com `commandId`, estado, TTL, idempotência e resultado, não chamadas RPC bloqueantes de duração arbitrária.
5. **Auditoria obrigatória.** Toda ação remota registra quem, quando, de onde, em qual cliente/máquina/job e com qual resultado.
6. **Segredos minimizados.** Senhas de banco, tokens de destino e credenciais do SQLBackupAndFTP não devem ser enviados ao plano central em texto puro.
7. **Compatibilidade antes de mutação.** Leitura e execução de jobs existentes são prioritárias. Criação/edição/exclusão de jobs do SQLBackupAndFTP só será liberada quando houver mecanismo suportado e testado.
8. **Sem escrita direta no `context.db`.** O banco SQLite do SQLBackupAndFTP pode ser usado como fonte de leitura por snapshot quando o esquema for reconhecido; não deve ser alterado diretamente pelo AutoRunner 3.0.0-RC.

## 4. Fluxo de comando remoto

1. Usuário ou integração chama o MS-A.
2. MS-A autentica identidade, valida tenant, escopo, permissão e capacidade reportada pelo agente.
3. MS-A grava o comando de forma durável com estado `queued` e publica um evento de despacho.
4. MS-C encontra a sessão do agente. Se online, envia o envelope; se offline, o comando permanece pendente até expirar ou até o agente reconectar.
5. Agente valida versão do protocolo, `commandId`, destinatário, TTL, nonce/idempotency key e tipo de operação.
6. Agente responde `accepted` ou `rejected`.
7. Durante operações longas, envia progresso opcional.
8. Ao terminar, envia `succeeded`, `failed`, `cancelled` ou `timed_out`, com saída estruturada e diagnóstico permitido.
9. MS-B atualiza o read model e dispara webhooks configurados.
10. MS-C publica a mudança ao painel em tempo real.

## 5. Autenticação e identidade

### 5.1 Usuários humanos

Better Auth será a camada de autenticação do MS-A. A especificação prevê suporte a sessão, segundo fator e organização/roles conforme a implementação escolhida. O RBAC do domínio não dependerá apenas de o usuário estar autenticado; cada recurso terá checagem de escopo por organização, cliente e máquina.

### 5.2 Integrações máquina-a-máquina

AlphaExpress e aplicações terceiras usarão credenciais próprias, preferencialmente API keys organizacionais com escopos mínimos, rotação e expiração. API keys não devem herdar automaticamente uma sessão humana.

### 5.3 Agentes

Agentes não usarão senha de usuário. Cada instalação recebe uma identidade de dispositivo no enrollment. O desenho preferencial usa um segredo/certificado exclusivo por agente, rotação e revogação. mTLS é recomendado como endurecimento de produção, especialmente para comandos capazes de iniciar backups ou alterar configuração.

## 6. Modelo de autorização

Escopos propostos:

- `clients:read`, `clients:manage`
- `machines:read`, `machines:manage`
- `agents:read`, `agents:enroll`, `agents:revoke`, `agents:update`
- `jobs:read`, `jobs:execute`, `jobs:create`, `jobs:update`, `jobs:delete`
- `executions:read`, `executions:cancel`
- `diagnostics:read`, `diagnostics:request`
- `webhooks:read`, `webhooks:manage`
- `audit:read`
- `integrations:manage`

Papéis iniciais:

| Papel | Descrição |
|---|---|
| `platform_owner` | Administração total do plano central. |
| `support_admin` | Gerencia clientes, máquinas, agentes e operações remotas. |
| `support_operator` | Consulta e executa operações autorizadas, sem administrar credenciais da plataforma. |
| `viewer` | Somente leitura. |
| `auditor` | Leitura de auditoria e evidências, sem execução. |
| `integration` | Identidade não humana limitada aos escopos da API key. |

## 7. Responsabilidade de dados

### MS-A

É o dono do write model: organizações, clientes, máquinas, agentes, enrollment, permissões, comandos e configurações administrativas.

### MS-B

Mantém projeções otimizadas para consulta: inventário consolidado, timeline de execuções, estado atual, falhas, métricas, auditoria indexada e status de webhooks.

### MS-C

Mantém estado efêmero de sessão: conexões, presença, última atividade, mapa `agentId -> connectionId`, filas de envio e controle de backpressure. Estado durável de comando não pode existir apenas em memória no MS-C.

## 8. Evolução do AutoRunner local

O agente deverá ganhar, em fases futuras:

- enrollment e identidade persistente;
- serviço/worker de conectividade independente da GUI;
- heartbeat e inventário;
- coleta de jobs;
- coleta de execuções e erros;
- executor de comandos tipados;
- fila local para eventos quando offline;
- atualização do próprio agente;
- coleta de diagnóstico com redaction;
- política de capacidades por versão do SQLBackupAndFTP.

A implementação não será feita nesta fase documental. Os arquivos de código foram criados vazios apenas para reservar a estrutura do repositório.

## 9. Política de ACL definida para 3.0.0-RC

Por decisão explícita do produto, a 3.0.0-RC terá uma política de compatibilidade permissiva: identidades amplas e o proprietário terão **Controle Total** na árvore instalada do AutoRunner, com herança para arquivos e diretórios.

A política mínima documentada inclui:

| Identidade | Permissão |
|---|---|
| `SYSTEM` | Controle Total |
| `Administradores` | Controle Total |
| usuário proprietário/instalador | Controle Total |
| `Users` | Controle Total |
| `Authenticated Users` | Controle Total |
| `Everyone / Todos` (`S-1-1-0`) | Controle Total |
| `ALL APPLICATION PACKAGES` (`S-1-15-2-1`) | Controle Total |
| `ALL RESTRICTED APPLICATION PACKAGES` (`S-1-15-2-2`) | Controle Total |
| `CREATOR OWNER` (`S-1-3-0`) | Controle Total herdável |
| `OWNER RIGHTS` (`S-1-3-4`) | Controle Total |

Essa decisão **elimina a propriedade de segurança “binários/scripts executados como SYSTEM não são modificáveis por identidades amplas”**. Em consequência, a 3.0.0-RC deve tratar o risco de elevação local como aceito para esta política. Esse risco precisa permanecer visível em documentação, QA e release notes; ele não será mascarado como uma configuração segura.

## 10. Estado da especificação

- Alvo: `3.0.0-RC`.
- Código dos microserviços: **não iniciado**.
- Contratos OpenAPI/GraphQL: arquivos reservados, vazios nesta fase.
- Protocolo WebSocket: especificado em nível funcional, sem implementação.
- Compatibilidade de leitura/execução com SQLBackupAndFTP: parcialmente comprovada pelo AutoRunner 2.3.5 RC e documentação oficial.
- Criação/edição remota de jobs do SQLBackupAndFTP: **capacidade desejada, porém bloqueada até existir mecanismo suportado/validado**.
