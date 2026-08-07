# ADR-001 — Conexão do agente sempre de saída

**Status:** Aceito  
**Versão alvo:** 3.0.0-RC

## Decisão

O AutoRunner Agent não hospedará endpoint REST/HTTP/WebSocket acessível pela rede do cliente. O agente iniciará uma conexão WSS para o MS-C e usará HTTPS somente para enrollment/fluxos auxiliares definidos.

## Motivos

- atravessa NAT/firewall com muito menos configuração;
- evita expor centenas de servidores diretamente;
- centraliza TLS, autenticação, rate limiting e auditoria;
- reduz dependência de IP público/fixo no cliente.

## Consequência

Comandos são assíncronos e precisam de fila/TTL porque um agente pode estar offline.
