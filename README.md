# SQLBackupAndFTP AutoRunner

<p align="center"><img src="assets/AutoRunner.png" width="96" alt="SQLBackupAndFTP AutoRunner"></p>
<p align="center"><strong>Executa automaticamente jobs do SQLBackupAndFTP após o boot e está evoluindo para gerenciamento central remoto.</strong></p>

<p align="center">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-x64-0078D4">
  <img alt="Backend" src="https://img.shields.io/badge/Backend-Windows%20PowerShell%205.1-5391FE">
  <img alt="Release atual" src="https://img.shields.io/badge/release-2.3.5%20RC-1F6FEB">
  <img alt="Próxima" src="https://img.shields.io/badge/próxima-3.0.0%20RC-2496ED">
</p>

> [!IMPORTANT]
> **2.3.5 RC é a release Windows publicada mais recente.** A 3.0.0-RC está sendo desenvolvida no PR #3 e adiciona Control Plane Docker, APIs e Remote Agent. Nenhuma das duas deve ser promovida a estável sem homologação real em Windows e SQLBackupAndFTP.

## Releases

| Versão | Estado | Conteúdo |
|---|---|---|
| **2.3.5 RC** | Release Candidate atual | Setup, Portable e Source em Releases |
| 2.3.0 | Substituída | Preservada para auditoria/regressão |
| **3.0.0-RC** | Em desenvolvimento | PR #3: Control Plane + Remote Agent |

## 2.3.5 RC

A 2.3.5 corrige os problemas encontrados na 2.3.0 em abertura/ACL, ícones e taskbar, DPI/layout, atualização, desinstalação e detecção do SQLBackupAndFTP. Ela ainda precisa de teste real antes de ser tratada como estável.

O AutoRunner pode ser instalado sem SQLBackupAndFTP. A detecção não depende de uma pasta fixa e considera Registro 32/64, serviços, processos, App Paths, atalhos, caminhos conhecidos, busca limitada em volumes fixos e seleção manual. Quando o produto não é encontrado, o usuário pode abrir o download oficial mediante confirmação.

## Próxima geração: 3.0.0-RC

A linha 3 adiciona:

- **MS-A:** REST, OpenAPI, Better Auth, RBAC e API keys;
- **MS-B:** GraphQL, subscriptions e Webhooks;
- **MS-C:** WebSocket/WSS realtime;
- aplicativo central web;
- Remote Agent Windows outbound-only;
- inventário de clientes, máquinas, instalações e jobs;
- execução remota de jobs existentes;
- comandos duráveis/idempotentes;
- PostgreSQL, auditoria, outbox e retenção operacional;
- Docker Compose/Caddy para hospedagem central.

O agente não expõe porta REST no cliente. Ele inicia a conexão HTTPS/WSS para a central, permitindo operar atrás de NAT/firewall.

Criação/edição/exclusão de job permanece capability-gated enquanto o SQLBackupAndFTP não oferecer mecanismo upstream suportado. O projeto não altera diretamente `context.db` para simular essa capacidade.

## ACL 3.0.0-RC

> [!WARNING]
> Por decisão explícita de produto, a 3.0.0-RC exige **FullControl** nos recursos permanentes do produto para SYSTEM, Administradores, proprietário/instalador, Users, Authenticated Users, Everyone/Todos, ALL APPLICATION PACKAGES, ALL RESTRICTED APPLICATION PACKAGES, CREATOR OWNER e OWNER RIGHTS. O risco de segurança dessa decisão é documentado no ADR-003. Scratch temporário usado como fronteira de elevação continua restrito a SYSTEM/Administradores.

## GitHub

O desenvolvimento 3.0.0-RC está no **PR #3**, branch `feature/3.0.0-rc-control-plane`. O PR permanece Draft até a árvore Source final substituir integralmente o skeleton e os testes reais serem concluídos.

## Limite operacional

Código zero da CLI não comprova que um backup foi criado, transferido ou é restaurável. A homologação exige verificar histórico do SQLBackupAndFTP, arquivo no destino, execução pós-boot e restauração real.

## Licença

Uso interno e distribuição autorizada pela Alpha Software. Consulte `LICENSE`, `SECURITY.md` e `SUPPORT.md`.
