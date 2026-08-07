# Operação do AutoRunner Control Plane 3.0.0-RC

## Componentes

| Componente | Função |
|---|---|
| Caddy | ponto único de entrada HTTP/HTTPS/WSS e aplicação web estática |
| MS-A | REST, autenticação, RBAC, comandos administrativos e OpenAPI |
| MS-B | GraphQL, subscriptions SSE e entrega de webhooks |
| MS-C | gateway WebSocket para agentes e atualização em tempo real da UI |
| PostgreSQL | fonte de verdade, auditoria, comandos, read models e outbox |
| Remote Agent | agente Windows outbound-only junto ao AutoRunner |

## Modelo de comando

Operações remotas são assíncronas. A API cria um comando durável e retorna `202 Accepted`. MS-C tenta despachá-lo a um agente online. A máquina do cliente reconhece, executa e reporta progresso/resultado. Comandos podem terminar como `succeeded`, `failed`, `cancelled`, `expired` ou `rejected`.

Para reduzir execução duplicada:

- `Idempotency-Key` é usado nas operações de criação de comando;
- comandos têm ID estável;
- o agente mantém cache local de conclusões recentes;
- comandos já aceitos/running não são executados novamente ao reconectar;
- o servidor pode redespachar mensagens não confirmadas sem perder o comando.

A garantia operacional é **at-least-once delivery com execução idempotente no agente**, não exactly-once distribuído.

## Inventário

O agente reporta:

- identidade da máquina;
- versão do AutoRunner;
- instalação localizada do SQLBackupAndFTP;
- capacidades suportadas;
- jobs encontrados;
- estado de conectividade.

Inventário parcial não desativa jobs não vistos. Somente um snapshot marcado como completo pode reconciliar ausências.

## Segurança de transporte

Produção exige HTTPS/WSS. HTTP/WS existe apenas como opção consciente para laboratório isolado. O cliente nunca publica uma porta própria para receber comandos.

## Autenticação humana e integrações

- operadores usam Better Auth com sessão;
- integrações usam API keys vinculadas à organização e permissões explícitas;
- tokens de realtime são curtos e assinados;
- agentes usam segredo individual após enrollment;
- token de enrollment não é a credencial permanente do agente.

## Auditoria

Operações de escrita e transições relevantes devem deixar evento de auditoria com ator, organização, recurso, ação, horário e resultado. Segredos, tokens, connection strings e output sensível são redigidos antes de log/auditoria.

## Webhooks

Webhooks possuem HMAC, timeout, retry exponencial, dead-letter e proteção SSRF. O servidor resolve o DNS antes do envio e fixa o IP selecionado na conexão, reduzindo DNS rebinding. Redirect não é seguido automaticamente.

## Limites SQLBackupAndFTP

A 3.0.0-RC suporta com segurança a execução de jobs existentes por meio da CLI pública já utilizada pelo AutoRunner. Criar/editar/excluir job remotamente permanece `capability-gated`: enquanto o fornecedor não expuser mecanismo oficial confiável, a API retorna capacidade indisponível em vez de escrever diretamente no banco interno do produto.


## Retenção operacional

O MS-B executa limpeza incremental dos eventos operacionais já materializados e das entregas de webhook em estado terminal. O padrão é `EVENT_RETENTION_DAYS=90`, com varredura a cada `RETENTION_CLEANUP_INTERVAL_SECONDS=3600`. Eventos com webhook ainda pendente ou em retry não são removidos. Diagnósticos expirados em estado terminal também são eliminados. Eventos de auditoria (`ar_audit_events`) não participam dessa limpeza automática na RC.
