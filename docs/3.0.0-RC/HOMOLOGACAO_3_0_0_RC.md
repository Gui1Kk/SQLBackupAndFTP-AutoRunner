# Homologação 3.0.0-RC

## A. Base Windows herdada

- instalação limpa;
- upgrade sobre 2.3.0 problemática;
- upgrade sobre 2.3.5 RC;
- abrir GUI sem ícone do PowerShell;
- atalhos/ícones corretos;
- DPI 100/125/150/175/200%;
- instalar/remover automação;
- uninstall do aplicativo;
- reinicialização do Windows;
- validar a política FullControl 3.0 para todos os SIDs normativos;
- confirmar que scratch temporário privilegiado continua restrito.

## B. Control Plane

- `docker compose up -d --build` em VM Windows/WSL2;
- todas as healthchecks verdes;
- login bootstrap;
- criação de organização/cliente;
- token de enrollment;
- agente aparece online;
- inventário/jobs sincronizados;
- restart de MS-C sem duplicar backup;
- restart de PostgreSQL;
- agente offline e comando pendente;
- reconexão e despacho posterior;
- cancelamento;
- expiração;
- timeout de comando running;
- revogação fecha socket e impede heartbeat;
- reenrollment cria nova identidade preservando histórico.

## C. Backup real

- executar job Full remotamente;
- executar Diff/TranLog somente em job compatível;
- conferir histórico SQLBackupAndFTP;
- conferir arquivo/destino;
- provocar falha real e validar summary/exit code;
- restaurar backup em ambiente de teste.

## D. Segurança/API

- API sem autenticação retorna 401/403;
- API key com escopo mínimo;
- API key sem permissão é recusada;
- revogação de API key;
- Origin não confiável no WebSocket UI;
- token de realtime inválido/expirado;
- webhook HMAC válido;
- webhook privado bloqueado salvo allowlist explícita;
- rate limits;
- GraphQL depth/field/body limits;
- introspection desabilitada em produção.

## E. Continuidade

- backup do Control Plane;
- apagar/recriar stack em ambiente de teste;
- restore;
- validar organizações, agentes, jobs, execuções, auditoria e webhooks;
- snapshot da VM e recuperação.
