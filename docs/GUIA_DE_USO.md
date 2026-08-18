# Guia de uso 3.0.1

## Instalar o aplicativo

1. Execute `SQLBackupAndFTP-AutoRunner-Setup-v3.0.1.exe`.
2. Autorize o UAC.
3. Confirme a instalação e, se desejado, o atalho da Área de Trabalho.
4. O SQLBackupAndFTP pode ser detectado automaticamente ou localizado manualmente.

## Configurar a automação, modo recomendado

1. Abra o AutoRunner.
2. Clique em **Instalar automação**.
3. Marque os jobs desejados.
4. Confira a coluna **Situação**.
5. Clique em **Salvar configuração**.
6. Se houver jobs cuja classificação/agendamento não pôde ser confirmado, confira a única confirmação exibida.
7. Use **Testar backup agora** e confira o histórico e o destino.

Você não precisa configurar tipo de backup, retries, tempos ou logs para o fluxo normal.

## Configurações avançadas

Marque **Usar configurações avançadas** somente quando houver uma necessidade técnica específica. A tela então exibe tipo de backup por job, parâmetros de execução/resiliência, adição manual de job e política de logs.

Alterar esses parâmetros pode aumentar repetição de jobs ou tempo de execução. Combinações de maior risco continuam exigindo confirmação.

## Central

Use **Conectar à Central** para matricular a máquina no Control Plane. A conexão do agente é outbound HTTPS/WSS; nenhuma API de entrada é aberta na máquina do cliente.

## Teste mínimo após instalar

1. **Validar instalação**.
2. **Testar backup agora**.
3. Confirmar execução no histórico do SQLBackupAndFTP.
4. Confirmar o arquivo no destino.
5. Reiniciar o Windows.
6. Confirmar a execução automática esperada.
7. Fazer uma restauração de teste.

## Manutenção

- **Validar instalação**: configuração, hashes, ACL, tarefa e caminhos;
- **Reparar automação**: recria o runtime/tarefa preservando jobs;
- **Reparar aplicativo**: repõe os arquivos do aplicativo;
- **Desinstalar aplicativo**: remove AutoRunner/automação sem apagar jobs do SQLBackupAndFTP;
- **Exportar diagnóstico**: gera pacote com configuração, estado, logs, tarefa e eventos.
