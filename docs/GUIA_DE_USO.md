# Guia de uso 2.3.5 RC

## Instalar

1. Execute o Setup 2.3.5 RC como administrador.
2. Confirme a pasta detectada do SQLBackupAndFTP.
3. Quando necessário, selecione manualmente a pasta que contém `SqlBak.Job.Cli.exe`.
4. Escolha o atalho da Área de Trabalho.
5. Conclua e abra o AutoRunner.

A ausência do SQLBackupAndFTP não precisa interromper a instalação do aplicativo, mas impede instalar a automação até que uma CLI válida seja localizada.

## Configurar automação

1. Clique em **Instalar automação**.
2. Selecione explicitamente os jobs.
3. Confirme jobs manuais ou de baixa confiança.
4. Configure atraso após boot, intervalo mínimo e retentativas.
5. Conclua e use **Validar instalação**.

## Testar

1. Clique em **Testar backup agora**.
2. Confira o histórico do job no SQLBackupAndFTP.
3. Confira o arquivo no destino.
4. Faça uma restauração de teste.

## Manutenção

- **Validar instalação:** configuração, manifesto, ACL, tarefa e caminhos;
- **Reparar automação:** recria runtime e tarefa preservando jobs;
- **Remover automação:** remove tarefa e dados operacionais sem apagar jobs originais;
- **Reparar aplicativo:** executa o Setup preservado por fluxo externo seguro;
- **Desinstalar aplicativo:** remove aplicativo e automação, preservando jobs do SQLBackupAndFTP;
- **Exportar diagnóstico:** reúne logs, estado, configuração, tarefa e eventos.

## Instalação silenciosa

```text
SQLBackupAndFTP-AutoRunner-Setup-v2.3.5-RC.exe /silent /desktop
```

Opções:

```text
/silent /desktop /nolaunch /notutorial /repair /uninstall /purgedata
```

`/deferred` é interno e não deve ser usado manualmente.

## Logs precoces

```text
%TEMP%\SQLBackupAndFTPAuto\setup-startup.log
%TEMP%\SQLBackupAndFTPAuto\manager-startup.log
%TEMP%\SQLBackupAndFTPAuto\manager.log
```

## Aprovação

Uma tela de sucesso ou código zero não substitui histórico, arquivo no destino e restauração. Teste também o boot real.
