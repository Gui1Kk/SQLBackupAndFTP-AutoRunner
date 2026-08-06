# Documentação técnica 2.2.1

## Arquitetura

```text
Setup EXE gráfico e autoextraível
  -> Program Files\Alpha Software\SQLBackupAndFTP AutoRunner
       -> launcher nativo GUI
       -> Manager.ps1
       -> AutoRunner.Core.psm1
       -> Setup local para reparo/desinstalação
  -> ProgramData\SQLBackupAndFTPAuto
       -> config.json / state.json / manifest.json
       -> runner e módulo validados
       -> logs e estado por job
  -> Agendador de Tarefas, SYSTEM, gatilho de boot
  -> SqlBak.Job.Cli.exe localizado dinamicamente
```

## Detector do SQLBackupAndFTP

`Find-SqlBackupAndFTPInstallations` agrega candidatos de múltiplas fontes, atribui pontuação e valida cada diretório. Entradas de Registro usam acesso tolerante a propriedades opcionais, impedindo que campos ausentes como `DisplayName` interrompam a detecção sob `Set-StrictMode`.

A busca profunda usa limites de profundidade e quantidade, ignora reparse points e não varre o volume inteiro. Instalações fora das fontes automáticas podem ser selecionadas manualmente quando contêm `SqlBak.Job.Cli.exe`.

## Launcher

`SQLBackupAndFTP-AutoRunner.exe` é um PE32+ GUI x64 que inicia `scripts\Manager.ps1` pelo Windows PowerShell com janela oculta. Caminhos ou comandos acima do limite seguro encerram com erro controlado.

## Setup EXE

O bootstrapper solicita elevação, cria diretório temporário privado, valida o payload e `SHA256SUMS.txt`, rejeita arquivos injetados, executa `Setup-Wizard.ps1` sem console e limpa a área temporária.

## Automação

A tarefa executa como `SYSTEM`, usa política de instância única, possui atraso configurável e chama o runner por caminho absoluto.

O runner valida módulo, configuração, manifesto e CLI; trata mutex abandonado; aplica intervalo mínimo por job; consolida falhas; grava estado atômico e logs rotativos.

## Pastas e Registro

- aplicação: `Program Files\Alpha Software\SQLBackupAndFTP AutoRunner`;
- operação: `ProgramData\SQLBackupAndFTPAuto`;
- preferência e tutorial: `HKCU\Software\Alpha Software\SQLBackupAndFTP AutoRunner`;
- instalação: `HKLM\Software\Alpha Software\SQLBackupAndFTP AutoRunner`.

## Códigos relevantes do runner

- `0`: execução concluída ou condição normal sem disparo;
- `10`: falha consolidada;
- `11`: falha de CLI;
- `12`: todos ignorados pelo intervalo;
- `13`: outra execução manual já ativa;
- `14`: job não executado após parada configurada;
- `23`: CLI em caminho inseguro.
