# Contracts 3.0.0-RC

- `openapi.yaml`: contrato REST público do MS-A, OpenAPI 3.1.
- `schema.graphql`: contrato do MS-B usado pelo aplicativo central e integrações de consulta.
- O protocolo WSS do MS-C está especificado em `docs/3.0.0-RC/WEBSOCKET_PROTOCOL_DRAFT.md` e validado pelo código compartilhado `services/shared/src/agent-protocol.ts`.

Better Auth também expõe sua referência OpenAPI própria em `/api/auth/reference` por meio do plugin oficial Open API.
