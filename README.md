# SQLBackupAndFTP AutoRunner

<p align="center">
  <strong>Executa automaticamente, após a inicialização do Windows, jobs de backup já configurados no SQLBackupAndFTP.</strong>
</p>

<p align="center">
  <a href="https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/latest">
    <img alt="Última versão" src="https://img.shields.io/github/v/release/Gui1Kk/SQLBackupAndFTP-AutoRunner?style=flat-square&label=vers%C3%A3o">
  </a>
  <img alt="Plataforma" src="https://img.shields.io/badge/Windows-x64-0078D4?style=flat-square&logo=windows11&logoColor=white">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1+-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="Licença" src="https://img.shields.io/badge/licen%C3%A7a-propriet%C3%A1ria-red?style=flat-square">
</p>

> [!IMPORTANT]
> O AutoRunner funciona **somente em sistemas operacionais Windows de 64 bits**. Não há suporte para Windows x86/32 bits, ARM64 ou outros sistemas operacionais.

## Download recomendado

<p align="center">
  <a href="https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.1/SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe">
    <img alt="Baixar Setup x64" src="https://img.shields.io/badge/BAIXAR-SETUP_X64-0078D4?style=for-the-badge&logo=windows11&logoColor=white">
  </a>
  <a href="https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.1/SQLBackupAndFTP-AutoRunner-v2.2.1-Portable.zip">
    <img alt="Baixar Portable x64" src="https://img.shields.io/badge/BAIXAR-PORTABLE_X64-2EA44F?style=for-the-badge">
  </a>
  <a href="https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.1/SQLBackupAndFTP-AutoRunner-v2.2.1-Source.zip">
    <img alt="Baixar código-fonte" src="https://img.shields.io/badge/BAIXAR-C%C3%93DIGO_FONTE-6E40C9?style=for-the-badge&logo=github&logoColor=white">
  </a>
</p>

### Qual arquivo escolher?

| Arquivo | Uso recomendado |
|---|---|
| **Setup x64** | Instalação normal, atalhos, reparo, atualização e desinstalação. É a opção recomendada para clientes. |
| **Portable x64** | Testes, diagnóstico ou execução sem instalar a interface do aplicativo. |
| **Código-fonte** | Auditoria, desenvolvimento, compilação e manutenção técnica. |

- [Abrir a release mais recente](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/latest)
- [Conferir os hashes SHA-256](downloads/SHA256SUMS.txt)
- [Ver todas as releases](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases)

## Histórico de downloads

| Versão | Release | Setup | Portable | Código-fonte | Situação |
|---|---|---|---|---|---|
| **2.2.1** | [Abrir](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/tag/v2.2.1) | [Baixar](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.1/SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe) | [Baixar](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.1/SQLBackupAndFTP-AutoRunner-v2.2.1-Portable.zip) | [Baixar](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.1/SQLBackupAndFTP-AutoRunner-v2.2.1-Source.zip) | **Recomendada** |
| 2.2.0 | [Abrir](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/tag/v2.2.0) | [Baixar](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.0/SQLBackupAndFTP-AutoRunner-Setup-v2.2.0.exe) | [Baixar](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.0/SQLBackupAndFTP-AutoRunner-v2.2.0-Portable.zip) | [Baixar](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.2.0/SQLBackupAndFTP-AutoRunner-v2.2.0-Source.zip) | Substituída pela 2.2.1 |
| 2.1.0 RC | [Abrir](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/tag/v2.1.0-RC) | Não disponível | [Pacote legado](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases/download/v2.1.0-RC/SQLBackupAndFTP-AutoRunner-v2.1.0-RC.zip) | Incluído no pacote | Legada, não recomendada |

> [!NOTE]
> Os links da tabela apontam diretamente para os arquivos anexados às Releases. O navegador inicia o download sem precisar abrir manualmente a página da versão.

## O que a ferramenta resolve

Alguns clientes desligam o servidor e o ligam apenas ocasionalmente. Nesses casos, um job agendado no SQLBackupAndFTP pode não executar porque o computador estava desligado no horário configurado. O AutoRunner cria uma tarefa no Agendador do Windows para chamar os jobs selecionados depois que o sistema inicia.

Ele **não altera** bancos de dados, credenciais, destinos, retenção, compactação ou agendamentos internos do SQLBackupAndFTP.

## Requisitos

- Windows 10, Windows 11 ou Windows Server em edição **x64**;
- Windows PowerShell 5.1 ou superior;
- privilégios administrativos para instalar ou alterar a automação;
- SQLBackupAndFTP instalado;
- `SqlBak.Job.Cli.exe` disponível na instalação do SQLBackupAndFTP;
- ao menos um job de backup previamente configurado.

A compatibilidade é detectada pela presença e validação da CLI, sem depender de caminho fixo ou do idioma do Windows.

## Instalação recomendada

1. Clique em **Baixar Setup x64** no início desta página.
2. Execute `SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe` como administrador.
3. Confirme ou selecione a instalação do SQLBackupAndFTP.
4. Escolha os atalhos desejados.
5. Abra o AutoRunner ao concluir.
6. Clique em **Instalar automação** e selecione explicitamente os jobs.
7. Execute **Testar backup agora**.
8. Confira o histórico no SQLBackupAndFTP e o arquivo no destino.

Aplicação:

```text
C:\Program Files\Alpha Software\SQLBackupAndFTP AutoRunner
```

Dados operacionais:

```text
C:\ProgramData\SQLBackupAndFTPAuto
```

## Detecção do SQLBackupAndFTP

A busca considera caminho salvo, Registro 32/64 bits, serviço, processos, App Paths, atalhos do Menu Iniciar, `Program Files`, busca limitada pela CLI e seleção manual. Entradas incompletas do Registro não interrompem a detecção.

## Interface e tutorial

A interface abre diretamente, sem janela de CMD. O tutorial pode ser percorrido, pulado, ocultado para a versão atual e reaberto pelo botão `?`.

A versão **2.2.1** corrige a incompatibilidade do instalador com Windows PowerShell 5.1 e o congelamento da navegação do tutorial observado na 2.2.0.

## Segurança e robustez

- tarefa executada como `SYSTEM` com instância única;
- seleção explícita de jobs;
- validação SHA-256 dos arquivos do pacote;
- recusa de traversal, links, junctions e arquivos não declarados;
- ACLs restritivas em arquivos executados como `SYSTEM`;
- mutex com recuperação após encerramento abrupto;
- continuidade dos demais jobs após falha individual;
- retentativas e intervalo mínimo por job;
- logs rotativos e escrita JSON atômica;
- reparo e desinstalação sem apagar jobs do SQLBackupAndFTP.

## Limite importante

Código zero da CLI não confirma que o backup foi criado e enviado. A confirmação real exige conferir o histórico, o arquivo no destino e realizar restaurações periódicas em ambiente de teste.

## Compilação e testes

Consulte [BUILDING.md](BUILDING.md) e [docs/PLANO_DE_TESTES.md](docs/PLANO_DE_TESTES.md).

## Estrutura

```text
build/       empacotamento, MSI e assinatura
modules/     núcleo compartilhado
native/      launchers x64 e bootstrap do Setup
scripts/     interface, instalador e runner
tests/       QA estático, regressão, modelo e fuzzing
docs/        uso, segurança, testes e documentação técnica
downloads/   inventário e hashes das versões
```

## Histórico, suporte e licença

Veja [CHANGELOG.md](CHANGELOG.md), [docs/RELEASES.md](docs/RELEASES.md), [SECURITY.md](SECURITY.md), [SUPPORT.md](SUPPORT.md) e [LICENSE](LICENSE).
