# SQLBackupAndFTP AutoRunner

<p align="center">
  <img src="assets/AutoRunner.png" width="96" alt="Ícone do SQLBackupAndFTP AutoRunner">
</p>

<p align="center">
  <strong>Executa automaticamente, após a inicialização do Windows, jobs de backup já configurados no SQLBackupAndFTP.</strong>
</p>

<p align="center">
  <img alt="Plataforma" src="https://img.shields.io/badge/Windows-x64-0078D4?logo=windows11&logoColor=white">
  <img alt="Host" src="https://img.shields.io/badge/Host-.NET%20x64-512BD4?logo=dotnet&logoColor=white">
  <img alt="Backend" src="https://img.shields.io/badge/Backend-PowerShell%205.1-5391FE?logo=powershell&logoColor=white">
  <img alt="Versão" src="https://img.shields.io/badge/versão-2.2.6-1F6FEB">
  <img alt="Licença" src="https://img.shields.io/badge/licença-proprietária-red">
</p>

> [!IMPORTANT]
> O AutoRunner funciona **somente em sistemas operacionais Windows de 64 bits**. Não há suporte para Windows x86/32 bits, ARM64 ou outros sistemas operacionais.

## Downloads

| Versão | Instalador | Portátil | Código-fonte | Situação |
|---|---|---|---|---|
| **2.2.6** | `SQLBackupAndFTP-AutoRunner-Setup-v2.2.6.exe` | `SQLBackupAndFTP-AutoRunner-v2.2.6-Portable.zip` | `SQLBackupAndFTP-AutoRunner-v2.2.6-Source.zip` | **Correção recomendada para homologação** |
| 2.2.5 | Setup x64 | Portable x64 | Source | Substituída pela 2.2.6 |
| 2.2.4 | Setup x64 | Portable x64 | Source | Substituída pela 2.2.5 |
| 2.2.3 | Setup x64 | Portable x64 | Source | Substituída pela 2.2.4 |
| 2.2.2 | Setup x64 | Portable x64 | Source | Substituída pela 2.2.3 |
| 2.2.1 | Setup x64 | Portable x64 | Source | Substituída pela 2.2.2 |
| 2.2.0 | Setup x64 | Portable x64 | Source | Substituída pela 2.2.1 |
| 2.1.0 RC | Não disponível | Pacote legado | Incluído no pacote | Legada, não recomendada |

Os arquivos `.sha256.txt` acompanham cada artefato. A versão 2.2.6 deve ser testada em Windows x64 antes de substituir a release marcada como estável.

## O que a ferramenta resolve

Alguns clientes desligam o servidor e o ligam apenas ocasionalmente. Nesses casos, um job agendado no SQLBackupAndFTP pode não executar porque o computador estava desligado no horário configurado. O AutoRunner cria uma tarefa no Agendador do Windows para chamar os jobs selecionados depois que o sistema inicia.

Ele **não altera**:

- bancos de dados;
- credenciais;
- destinos de backup;
- retenção;
- compactação;
- agendamentos internos do SQLBackupAndFTP.

## Requisitos

- Windows 10, Windows 11 ou Windows Server em edição **x64**;
- .NET Framework 4.8 x64, incluindo `csc.exe` do Framework64;
- Windows PowerShell 5.1, hospedado internamente pelo executável;
- privilégios administrativos para instalar ou alterar a automação;
- SQLBackupAndFTP instalado;
- `SqlBak.Job.Cli.exe` disponível na instalação do SQLBackupAndFTP;
- ao menos um job de backup previamente configurado no SQLBackupAndFTP.

A compatibilidade é detectada pela presença e validação da CLI, sem depender de um caminho fixo ou do idioma do Windows.

## Instalação recomendada

1. Baixe `SQLBackupAndFTP-AutoRunner-Setup-v2.2.6.exe`.
2. Execute como administrador.
3. Confirme ou selecione a instalação do SQLBackupAndFTP.
4. Escolha os atalhos desejados.
5. Abra o AutoRunner ao concluir.
6. Clique em **Instalar automação** e selecione explicitamente os jobs.
7. Execute **Testar backup agora**.
8. Confira o histórico no SQLBackupAndFTP e o arquivo no destino.

O aplicativo é instalado separadamente em:

```text
C:\Program Files\Alpha Software\SQLBackupAndFTP AutoRunner
```

Os dados operacionais ficam em:

```text
C:\ProgramData\SQLBackupAndFTPAuto
```

## Detecção do SQLBackupAndFTP

A busca considera:

1. caminho salvo e validado;
2. Registro do Windows em 32 e 64 bits;
3. serviço do SQLBackupAndFTP;
4. processos em execução;
5. App Paths;
6. atalhos do Menu Iniciar;
7. `Program Files` e `Program Files (x86)`;
8. busca limitada por `SqlBak.Job.Cli.exe`;
9. seleção manual da pasta.

Entradas incompletas do Registro não interrompem a detecção. Uma pasta só é aceita quando contém a CLI esperada.

## Interface e tutorial

A interface abre diretamente, sem janela de CMD. O tutorial inicial pode ser:

- percorrido com **Avançar** e **Voltar**;
- pulado;
- ocultado para a versão atual;
- reaberto por **Ajuda e tutorial**.

A versão **2.2.6** corrige a atualização sobre instalações anteriores: a pasta antiga deixa de ser copiada recursivamente e passa a ser renomeada atomicamente para rollback. Falhas de enumeração deixam de ser mascaradas como junction, e a primeira compilação do host Portable passa a registrar um log com código de erro. O PowerShell continua sendo o backend, hospedado ou oculto nos bastidores. Falhas precoces ficam registradas em `%TEMP%\SQLBackupAndFTPAuto`.

## Segurança e robustez

- tarefa executada como `SYSTEM` com política de instância única;
- seleção explícita de jobs;
- confirmação para jobs manuais ou de baixa confiança;
- validação SHA-256 dos arquivos do pacote;
- recusa de arquivos não declarados, traversal, links e junctions;
- ACLs restritivas em arquivos executados como `SYSTEM`;
- mutex com recuperação após encerramento abrupto;
- continuidade dos demais jobs após falha individual;
- retentativas controladas e intervalo mínimo por job;
- logs rotativos, estado individual e escrita JSON atômica;
- reparo e desinstalação sem apagar os jobs do SQLBackupAndFTP.

## Limite importante

Código zero da CLI não confirma que o backup foi criado e enviado. A confirmação real exige verificar:

- o histórico do job no SQLBackupAndFTP;
- o arquivo no destino;
- uma restauração periódica em ambiente de teste.

O AutoRunner executa os jobs selecionados em cada inicialização elegível. Ele não determina qual horário interno foi perdido.

## Compilação e testes

Consulte [BUILDING.md](BUILDING.md) para gerar Setup, Portable e MSI. O plano completo de testes está em [docs/PLANO_DE_TESTES.md](docs/PLANO_DE_TESTES.md).

Comandos de QA multiplataforma:

```bash
python tests/Static-QA.py
python tests/Deep-Review.py
python tests/Adversarial-Review.py
python tests/V22-Regression-QA.py
python tests/V221-Regression-QA.py
python tests/V222-Regression-QA.py
python tests/V223-Regression-QA.py
python tests/V224-Regression-QA.py
python tests/V225-Regression-QA.py
python tests/V226-Regression-QA.py
python tests/Upgrade-Transaction-Model.py
python tests/Behavioral-Model.py
python tests/State-Machine-Fuzz.py --iterations 100000 --seed 20260806
```

Testes nativos em Windows:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Invoke-QA.ps1 -Integration
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manager.ps1 -Action GuiSmoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Manager.ps1 -Action TutorialSmoke
```

## Estrutura

```text
assets/      ícone original em PNG/ICO
host/        hosts .NET x64 da aplicação e do Setup
build/       empacotamento, MSI e assinatura
modules/     núcleo compartilhado
native/      launchers x64 e bootstrap do Setup
scripts/     interface, instalador e runner
tests/       QA estático, regressão, modelo e fuzzing
docs/        uso, segurança, testes e documentação técnica
downloads/   artefatos históricos publicados
```

## Histórico

Veja [CHANGELOG.md](CHANGELOG.md) e [docs/RELEASES.md](docs/RELEASES.md).

## Suporte e licença

Uso interno e distribuição autorizada pela Alpha Software. Consulte [LICENSE](LICENSE), [SECURITY.md](SECURITY.md) e [SUPPORT.md](SUPPORT.md).
