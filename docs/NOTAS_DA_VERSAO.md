# SQLBackupAndFTP AutoRunner 2.3.5 RC

## Motivo da candidata

A 2.3.5 RC substitui a 2.3.0 RC depois de testes reais em Windows mostrarem permissões de leitura/execução inadequadas, falha de abertura do aplicativo, ícones ausentes/PowerShell na taskbar, layout cortado e remoção de automação retornando `-1`.

## Correções principais

- ACL da aplicação reconstruída com `SYSTEM`/Administradores em controle total e identidades interativas/Shell em leitura e execução, sem conceder escrita ampla;
- normalização recursiva das ACLs dos arquivos copiados;
- atalho usa o ícone incorporado no launcher;
- P/Invoke de DPI/AppUserModelID corrigido para o namespace realmente chamado;
- AppUserModelID e propriedades de relançamento/ícone aplicados ao HWND do WinForms hospedado pelo PowerShell;
- Setup e painel principal migrados para layouts responsivos com scroll;
- tratamento do falso `ExitCode -1` por pós-condição da remoção;
- detecção do SQLBackupAndFTP ampliada para Registro, serviços, processos, App Paths, atalhos, volumes locais limitados e seleção manual;
- instalação permitida mesmo sem SQLBackupAndFTP, com aviso e botão de download oficial;
- verificador integrado de atualizações com confirmação do usuário e atualização validada por SHA-256;
- bootstrap elevado extrai o payload privado sob `Program Files`, não no TEMP gravável pelo usuário;
- manutenção diferida, staging/rollback da automação e autocópia do desinstalador também usam scratch privilegiado sob `Program Files`;
- o JSON de solicitação que atravessa o UAC é vinculado por SHA-256 e analisado a partir dos mesmos bytes verificados;
- updater elevado baixa artefatos em `ProgramData` protegido;
- falhas de rede não avançam o relógio da checagem automática.

## Estado

Release Candidate. Não promover a estável antes de concluir `HOMOLOGACAO_2_3_5_RC.md`, incluindo atualização a partir de versões anteriores, boot real, backup no destino e restauração.
