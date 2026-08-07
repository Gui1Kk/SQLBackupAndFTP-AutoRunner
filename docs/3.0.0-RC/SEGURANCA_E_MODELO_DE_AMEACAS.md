# Segurança e modelo de ameaças — 3.0.0-RC

## 1. Mudança de superfície

A API central cria capacidade de executar ações em máquinas remotas. Isso aumenta drasticamente o impacto de autenticação quebrada, autorização por objeto, token roubado ou command replay. Segurança deixa de ser apenas propriedade do instalador e passa a ser propriedade end-to-end do plano de controle.

## 2. Ameaças prioritárias

| Ameaça | Exemplo | Controle de desenho |
|---|---|---|
| BOLA/IDOR | operador troca `machineId` e acessa outro cliente | autorização por objeto em toda rota/resolver |
| Broken authentication | API key vazada | chaves com escopo, expiração, rotação, rate limit e revogação |
| Function-level auth | viewer chama execute job | permissão `jobs:execute` dedicada |
| Replay | repetir comando de backup | command ID + idempotency key + TTL + resultado persistido |
| Agent impersonation | máquina falsa conecta como cliente | identidade de dispositivo exclusiva, prova de posse e revogação |
| Webhook SSRF | URL aponta para 169.254.169.254 | validação DNS/IP, bloqueio de ranges, redirect policy |
| GraphQL DoS | query profunda/cara | limites de profundidade, complexidade, tamanho e rate limit |
| WebSocket flood | agente envia mensagens ilimitadas | quotas, tamanho máximo, heartbeat e backpressure |
| Excessive data exposure | inventário retorna senha/token | DTO allowlist + redaction + testes |
| Supply chain | update comprometido | hashes, assinatura quando disponível, release allowlist |
| Command confusion | servidor manda payload incompatível | schema versionado + capability negotiation |
| Stale inventory | operador executa job que já mudou | timestamp, ETag/version do inventário e confirmação opcional |

## 3. Referências

A revisão deve cobrir OWASP API Security Top 10 2023, especialmente Broken Object Level Authorization, Broken Authentication, Broken Function Level Authorization, Unrestricted Resource Consumption, SSRF e Improper Inventory Management.

Para autenticação forte de agentes, mTLS é uma opção de projeto. RFC 8705 descreve autenticação OAuth 2.0 por mTLS e tokens vinculados a certificado; não é obrigatório usar OAuth no agente, mas o princípio de prova de posse é relevante.

Better Auth oferece plugin de API keys com permissões, rate limiting, expiração e ownership por organização, e plugin de Organization com roles/permissões. O desenho final deve pinçar apenas capacidades validadas na versão escolhida durante implementação.

## 4. ACL local 3.0.0-RC — risco aceito

A política exigida pelo produto concede **Controle Total** a identidades amplas na árvore instalada, incluindo Everyone/Todos, Users, Authenticated Users, todos os pacotes de aplicativos e identidades de proprietário. Isso significa que um processo que consiga modificar um script/binário posteriormente executado por uma tarefa/serviço elevado pode transformar essa permissão em elevação local de privilégio.

Consequências arquiteturais:

1. Não considerar a pasta do AutoRunner uma trust boundary.
2. Não afirmar que hashes locais impedem um atacante que tenha permissão para alterar simultaneamente payload e metadados graváveis.
3. Minimizar o que roda como `SYSTEM` e validar artefatos antes de execução sempre que possível.
4. Registrar essa decisão em release notes e homologação.
5. Tratar a segurança do canal remoto como independente da permissividade da ACL local.
6. O gate de ACL deve verificar `FullControl`, porque permissões inferiores contrariam o requisito funcional da 3.0.0-RC.

Essa seção existe para manter a documentação tecnicamente correta sem contrariar a política funcional definida para a release.
