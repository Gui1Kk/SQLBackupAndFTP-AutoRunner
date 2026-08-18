# Homologação SQLBackupAndFTP AutoRunner 3.0.1

## Objetivo

Validar em Windows real as correções encontradas durante o teste da 3.0.0-RC. A aprovação dos QAs automatizados não substitui esta lista.

## A. Instalação e ACL

- [ ] Instalação limpa conclui sem `Política FullControl ... não aplicada integralmente`.
- [ ] Upgrade de uma instalação 3.0.0-RC conclui.
- [ ] **Validar instalação** não acusa ACL.
- [ ] Arquivos/subpastas instalados passam pelo gate FullControl.
- [ ] `CREATOR OWNER` não gera falso negativo no gate.
- [ ] Reparar aplicativo reaplica a política sem falhar.
- [ ] Desinstalar e reinstalar funciona.

## B. Descoberta e salvamento de jobs

- [ ] Tela abre sem aviso `SQLite: Os tipos de argumento não correspondem`.
- [ ] Jobs são descobertos com a melhor fonte disponível.
- [ ] Selecionar um job e salvar não mostra `Os tipos de argumento não correspondem`.
- [ ] Selecionar vários jobs e salvar funciona.
- [ ] Reabrir a configuração preserva a seleção.
- [ ] Job conhecido como não-backup permanece bloqueado.
- [ ] Job desconhecido/manual exige somente a confirmação agregada.

## C. Modo simples

- [ ] **Usar configurações avançadas** inicia desmarcado em um perfil novo.
- [ ] No modo simples aparecem somente os campos necessários para escolher jobs.
- [ ] Salvar em modo simples usa `BackupType=Default`.
- [ ] **Testar backup agora** executa os jobs selecionados.
- [ ] O histórico/destino confirma o backup real.

## D. Modo avançado

- [ ] Marcar **Usar configurações avançadas** expande a tela sem cortar conteúdo.
- [ ] Tipo de backup escolhido chega à CLI.
- [ ] Atraso após boot é aplicado na tarefa.
- [ ] Intervalo mínimo é aplicado no runner.
- [ ] Retentativas e atraso entre tentativas são aplicados.
- [ ] Esperas de SQLBackupAndFTP/SQL Server são aplicadas.
- [ ] StopOnFirstFailure é aplicado.
- [ ] Limite/reinício da tarefa são aplicados.
- [ ] Rotação e retenção dos logs são aplicadas.
- [ ] Reinício da tarefa + intervalo 0 gera confirmação de risco.

## E. Layout e DPI

Testar janela normal, maximizada e redimensionada em pelo menos:

- [ ] 1280x720 @ 100%;
- [ ] 1366x768 @ 100%;
- [ ] 1920x1080 @ 100%;
- [ ] 1920x1080 @ 125%;
- [ ] 1920x1080 @ 150%;
- [ ] 2560x1440 @ 125% ou 150%, se disponível.

Em cada cenário:

- [ ] cards não se sobrepõem;
- [ ] botões não ficam achatados;
- [ ] ações rápidas continuam clicáveis;
- [ ] manutenção continua clicável;
- [ ] detalhes do ambiente permanecem acessíveis;
- [ ] tela de configuração permite alcançar **Salvar configuração**;
- [ ] modo avançado permite alcançar todos os controles por layout ou scroll.

## F. Automação real

- [ ] Instalar automação.
- [ ] Testar manualmente.
- [ ] Confirmar arquivo no destino.
- [ ] Reiniciar o Windows.
- [ ] Confirmar tarefa como SYSTEM.
- [ ] Confirmar execução no boot.
- [ ] Simular falha de um job e revisar runner.log/estado.
- [ ] Fazer restauração real do backup.

## G. Central, se usada

- [ ] Enrollment HTTPS.
- [ ] Identidade protegida por DPAPI.
- [ ] WSS conecta e presença fica online.
- [ ] Inventário/jobs aparecem.
- [ ] Execução remota de job existente funciona.
- [ ] Queda/reconexão de rede não duplica comando concluído.

## Critério

Para considerar a instalação homologada no ambiente, todos os itens aplicáveis devem passar, principalmente ACL, salvamento dos jobs, layout, boot, backup no destino e restauração.
