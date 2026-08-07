# ADR-004 — Separação de identidade humana, integração e agente

**Status:** Aceito

## Decisão

- usuários humanos: Better Auth + RBAC/organização;
- integrações como AlphaExpress: API key própria com escopos;
- agentes: identidade de dispositivo/enrollment independente.

Nunca reutilizar senha de usuário humano como credencial de agente, e nunca depender de uma API key global compartilhada entre todos os clientes.
