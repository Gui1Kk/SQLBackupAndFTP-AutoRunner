# SQLBackupAndFTP AutoRunner

<p align="center">
  <img src="assets/AutoRunner.png" width="96" alt="Ícone do SQLBackupAndFTP AutoRunner">
</p>

<p align="center">
  <strong>Executa, após a inicialização do Windows, jobs de backup já configurados no SQLBackupAndFTP.</strong>
</p>

<p align="center">
  <img alt="Plataforma" src="https://img.shields.io/badge/Windows-x64-0078D4?logo=windows11&logoColor=white">
  <img alt="Backend" src="https://img.shields.io/badge/Backend-Windows%20PowerShell%205.1-5391FE?logo=powershell&logoColor=white">
  <img alt="Versão" src="https://img.shields.io/badge/versão-2.3.5%20RC-1F6FEB">
  <img alt="Licença" src="https://img.shields.io/badge/licença-proprietária-red">
</p>

> [!IMPORTANT]
> **2.3.5 RC** é a release executável atual. A promoção a estável exige homologação real em Windows x64, reinicialização, backup e restauração.

> [!NOTE]
> ## Próxima geração: 3.0.0-RC
> Está em especificação o **AutoRunner Control Plane 3.0.0-RC**, com três microserviços independentes: MS-A (REST/OpenAPI/Better Auth), MS-B (GraphQL/Webhooks) e MS-C (WebSocket). O AutoRunner local se tornará um agente outbound-only capaz de reportar inventário/jobs/execuções e receber comandos tipados. Nesta etapa não há código da API: consulte [`docs/3.0.0-RC/RFP_AUTO_RUNNER_CONTROL_PLANE.md`](docs/3.0.0-RC/RFP_AUTO_RUNNER_CONTROL_PLANE.md).

## Releases atuais

| Versão | Situação | Artefatos |
|---|---|---|
| **2.3.5 RC** | Release Candidate atual | Setup, Portable e Source disponíveis em **Releases** |
| 2.3.0 | Substituída pela 2.3.5 RC | Preservada para auditoria |
| **3.0.0-RC** | Em especificação | Ainda sem binários, implementação da API não iniciada |

A página **Releases** do GitHub é a fonte de distribuição dos artefatos. Cada release deve publicar hashes SHA-256 junto dos binários.

## O que a ferramenta resolve hoje

Quando o computador fica desligado no horário interno de um job, aquele agendamento pode não ocorrer. O AutoRunner registra uma tarefa no Agendador do Windows para chamar explicitamente os jobs selecionados depois do boot.

Ele não altera bancos, credenciais, destinos, retenção, compactação ou o agendamento interno do SQLBackupAndFTP.

## Requisitos atuais

- Windows 10, Windows 11 ou Windows Server **x64**;
- Windows PowerShell 5.1;
- privilégios administrativos para instalar, atualizar, reparar ou alterar a automação.

O aplicativo pode ser instalado sem o SQLBackupAndFTP. Nesse estado a automação permanece desabilitada e o usuário pode abrir, após confirmação, o download oficial do SQLBackupAndFTP.

A detecção do SQLBackupAndFTP não depende de uma pasta fixa. Ela considera preferência salva, Registro 32/64 bits, serviços, processos, App Paths, atalhos, caminhos padrão como candidatos de baixa prioridade, busca limitada em volumes locais e seleção manual. Uma instalação só é aceita quando a CLI esperada é validada.

## Segurança e ACL

### Linha 2.3.5 RC

A 2.3.5 RC ainda utiliza a política de ACL desenhada para impedir escrita ampla em componentes que podem participar de execução privilegiada.

### Linha 3.0.0-RC

> [!WARNING]
> **Mudança deliberada de produto:** a 3.0.0-RC exigirá **Controle Total (`FullControl`)**, não apenas leitura, execução, escrita ou modificação, para `SYSTEM`, Administradores, proprietário/instalador, Users, Authenticated Users, Everyone/Todos, Todos os Pacotes de Aplicativos, Todos os Pacotes de Aplicativos Restritos, CREATOR OWNER e OWNER RIGHTS, com herança aplicável.

O instalador, reparo e atualizador da futura 3.0.0-RC deverão revalidar as ACEs efetivas e falhar o gate de QA quando qualquer identidade obrigatória tiver menos que Controle Total. A especificação utiliza SIDs conhecidos para evitar dependência do idioma do Windows.

Essa decisão amplia deliberadamente a possibilidade de modificação local de componentes e **não é classificada como hardening**. O risco aceito e a decisão normativa estão em [`ADR-003`](docs/3.0.0-RC/adr/ADR-003-ACL-FULL-CONTROL.md).

## Control Plane 3.0.0-RC

A arquitetura planejada é:

| Serviço | Tecnologias | Responsabilidade |
|---|---|---|
| **MS-A** | REST, OpenAPI, Better Auth | Administração, autenticação, RBAC, clientes, máquinas, agentes e comandos |
| **MS-B** | GraphQL, Webhooks | Consulta flexível, histórico, auditoria e integrações externas |
| **MS-C** | WebSocket | Presença, heartbeat, canal agente-central, comandos e progresso em tempo real |

O agente do cliente **não deverá expor uma API REST inbound**. Ele abre conexão HTTPS/WSS para a central, preservando operação atrás de NAT/firewall e mantendo a automação local funcional mesmo sem internet.

A 3.0.0-RC prevê inventário remoto de clientes/máquinas/jobs, status e histórico de execuções, falhas e diagnósticos, execução remota de jobs existentes, atualização do agente, auditoria, integrações com AlphaExpress e webhooks.

Criação/edição/exclusão de job aparece no domínio como capability condicionada. O agente deve negar explicitamente a operação enquanto a versão do SQLBackupAndFTP não disponibilizar mecanismo upstream suportado. A especificação proíbe escrever diretamente no `context.db` para simular suporte inexistente.

## Documentação 3.0.0-RC

O índice completo está em [`docs/3.0.0-RC/README.md`](docs/3.0.0-RC/README.md), incluindo:

- RFP;
- arquitetura;
- requisitos funcionais e não funcionais;
- casos de uso;
- matriz de capacidades do SQLBackupAndFTP;
- modelo de dados;
- drafts REST, GraphQL e WebSocket;
- segurança e threat model;
- observabilidade e auditoria;
- roadmap;
- ADRs.

## Implementação da API

Nesta fase, **nenhuma lógica dos microserviços foi escrita**. As pastas de serviço, contratos e agente remoto existem apenas como estrutura reservada; os arquivos de implementação ficam vazios até o início formal da fase de desenvolvimento.

## Limite operacional do backup

Código zero da CLI não comprova que o backup foi criado ou enviado. Homologação real exige conferir histórico do job, arquivo no destino, execução pós-boot e restauração periódica em ambiente de teste.

## Licença

Uso interno e distribuição autorizada pela Alpha Software. Consulte `LICENSE`, `SECURITY.md` e `SUPPORT.md`.
