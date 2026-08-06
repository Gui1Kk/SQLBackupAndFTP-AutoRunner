# Homologação da versão 2.2.5

A 2.2.5 é uma Release Candidate destinada a validar no Windows real as correções encontradas durante os testes da 2.2.4.

## Artefatos e hashes

```text
698181548F6F05201C109D62711179EAE549368145FD974E71391C6E718F360C  SQLBackupAndFTP-AutoRunner-Setup-v2.2.5.exe
E333255945A27C87B03D844AACE68071381E839F1D403E4AD90B53CC9F7DBD07  SQLBackupAndFTP-AutoRunner-v2.2.5-Portable.zip
3D6C52F107E6F1291AD26A462403F97260DF3C70540B40DA5693EC55278B41D3  SQLBackupAndFTP-AutoRunner-v2.2.5-Source.zip
```

## Preparação

1. finalize processos antigos do AutoRunner;
2. finalize processos `powershell.exe` deixados por versões anteriores;
3. remova ou renomeie pastas temporárias antigas do AutoRunner;
4. extraia o Portable em uma pasta nova;
5. mantenha uma instalação funcional do SQLBackupAndFTP e um job de teste configurado.

## Setup

1. executar o Setup como administrador;
2. confirmar que o ícone aparece corretamente;
3. confirmar que logo, título, versão e etapas da barra lateral não estão recortados;
4. confirmar que não existem sequências literais `\r\n` na interface;
5. concluir a instalação;
6. confirmar que o Setup não acusa `SQLBackupAndFTP-AutoRunner.SetupHost.exe` como arquivo não declarado;
7. confirmar atalhos do Menu Iniciar e Área de Trabalho quando selecionados;
8. abrir o aplicativo ao concluir.

## Portable

1. executar `SQLBackupAndFTP-AutoRunner.exe` da pasta nova;
2. confirmar que não existe erro de contexto de ativação no Visualizador de Eventos;
3. confirmar que a aplicação aparece como processo próprio;
4. confirmar que o PowerShell não aparece como aplicativo separado na barra de tarefas;
5. percorrer o tutorial completo;
6. testar Voltar, Avançar, Pular e Concluir;
7. confirmar que a janela principal permanece aberta e visível.

## Interface e múltiplos monitores

1. abrir no monitor primário e no secundário;
2. mover a janela entre os monitores;
3. testar escala de 100%, 125% e 150% quando disponível;
4. redimensionar a janela;
5. verificar todos os cartões, botões, rótulos e barras laterais;
6. reabrir o tutorial pelo botão de ajuda.

## Automação real

1. detectar automaticamente o SQLBackupAndFTP;
2. testar seleção manual da pasta;
3. instalar a automação com um job de teste;
4. validar a tarefa no Agendador;
5. executar Testar backup agora;
6. conferir histórico no SQLBackupAndFTP;
7. conferir arquivo no destino;
8. reiniciar o Windows e confirmar execução pós-boot;
9. testar intervalo mínimo e retentativas;
10. reparar a automação;
11. remover somente a automação;
12. reparar e desinstalar o aplicativo;
13. confirmar que os jobs originais do SQLBackupAndFTP foram preservados;
14. restaurar o backup em ambiente de teste.

## Logs

```text
%TEMP%\SQLBackupAndFTPAuto\setup-startup.log
%TEMP%\SQLBackupAndFTPAuto\setup-host.log
%TEMP%\SQLBackupAndFTPAuto\host-startup.log
%TEMP%\SQLBackupAndFTPAuto\manager-startup.log
%TEMP%\SQLBackupAndFTPAuto\manager.log
```

## Critério de aprovação

A versão só deve ser marcada como estável depois que todas as etapas aplicáveis forem concluídas sem falhas e o backup tiver sido confirmado no histórico, no destino e por uma restauração real.
