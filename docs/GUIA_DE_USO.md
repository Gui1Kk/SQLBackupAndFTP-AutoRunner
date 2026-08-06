# Guia de uso 2.2.1

## Instalação

1. Confirme que o Windows é x64.
2. Confirme que o SQLBackupAndFTP está instalado e possui ao menos um job configurado.
3. Execute o Setup como administrador.
4. Confirme a pasta detectada ou selecione a pasta que contém `SqlBak.Job.Cli.exe`.
5. Escolha os atalhos e conclua a instalação.
6. Abra o AutoRunner.

A ausência do SQLBackupAndFTP não deve interromper a instalação do AutoRunner, mas impede configurar a automação até que uma pasta válida seja localizada.

## Primeira abertura

O tutorial explica localização do SQLBackupAndFTP, instalação da automação, seleção de jobs, teste, validação, diagnóstico, reparo e remoção. Ele pode ser pulado e reaberto pelo botão `?`.

## Localizar o SQLBackupAndFTP

Quando a detecção automática não encontrar a instalação:

1. clique em **Localizar SQLBackupAndFTP**;
2. use **Procurar automaticamente**;
3. se necessário, clique em **Selecionar pasta**;
4. escolha a pasta que contém `SqlBak.Job.Cli.exe`;
5. confirme a instalação selecionada.

## Instalar a automação

1. clique em **Instalar automação**;
2. selecione somente os jobs desejados;
3. mantenha o tipo `Default` quando deve prevalecer a configuração original do job;
4. defina o atraso após o boot;
5. configure intervalo mínimo e tentativas quando necessário;
6. confirme jobs manuais, não agendados ou de baixa confiança;
7. conclua e execute a validação.

## Testar

1. clique em **Testar backup agora**;
2. aguarde a chamada terminar;
3. abra o SQLBackupAndFTP;
4. confira o histórico do job;
5. confira o arquivo no destino;
6. realize restaurações periódicas em ambiente de teste.

## Manutenção

- **Validar instalação:** verifica arquivos, configuração, manifesto, ACL e tarefa.
- **Reparar automação:** recria runtime e tarefa preservando jobs.
- **Remover automação:** remove tarefa e dados operacionais, preservando aplicativo e jobs.
- **Reparar aplicativo:** executa o Setup local.
- **Desinstalar aplicativo:** remove aplicativo e automação sem apagar os jobs originais.
- **Exportar diagnóstico:** reúne configuração, estado, logs, tarefa e eventos.

## Instalação silenciosa

```text
SQLBackupAndFTP-AutoRunner-Setup-v2.2.1.exe /silent /desktop
```

Opções: `/silent`, `/desktop`, `/nolaunch`, `/notutorial`, `/repair`, `/uninstall` e `/purgedata`.
