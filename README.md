# SQLBackupAndFTP AutoRunner

<p align="center">
  <strong>Executa automaticamente, após a inicialização do Windows, jobs de backup já configurados no SQLBackupAndFTP.</strong>
</p>

<p align="center">
  <img alt="Plataforma" src="https://img.shields.io/badge/Windows-x64-0078D4?logo=windows11&logoColor=white">
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white">
  <img alt="Versão" src="https://img.shields.io/badge/versão-2.2.1-1F6FEB">
  <img alt="Licença" src="https://img.shields.io/badge/licença-proprietária-red">
</p>

> [!IMPORTANT]
> O AutoRunner funciona **somente em sistemas operacionais Windows de 64 bits**. Não há suporte para Windows x86/32 bits, ARM64 ou outros sistemas operacionais.

## Downloads

Os instaladores, pacotes portáteis e códigos-fonte compactados são distribuídos pela página de [Releases](https://github.com/Gui1Kk/SQLBackupAndFTP-AutoRunner/releases). O inventário criptográfico está em [downloads/SHA256SUMS.txt](downloads/SHA256SUMS.txt).

| Versão | Artefatos | Situação |
|---|---|---|
| **2.2.1** | Setup x64, Portable x64 e Source | Correção recomendada |
| 2.2.0 | Setup x64, Portable x64 e Source | Substituída pela 2.2.1 |
| 2.1.0 RC | Pacote legado | Não recomendada |

Consulte também [downloads/README.md](downloads/README.md) e [docs/RELEASES.md](docs/RELEASES.md).

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

1. Baixe `SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe` na página de Releases.
2. Execute como administrador.
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
