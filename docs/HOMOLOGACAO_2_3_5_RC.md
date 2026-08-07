# Homologação da versão 2.3.5 RC

Esta lista é um gate de release. Um item não testado não deve ser considerado aprovado.

## 1. Instalação limpa e ACL

- instalar em Windows 10, Windows 11 e Windows Server x64 quando disponíveis;
- testar conta local administradora com UAC ativo;
- confirmar que o Setup conclui sem mensagem de acesso negado;
- confirmar abertura imediatamente após instalar;
- confirmar abertura por Menu Iniciar e Área de Trabalho;
- confirmar ícone no EXE, atalho, título e taskbar;
- confirmar que o aplicativo não aparece agrupado/identificado como Windows PowerShell;
- conferir ACL de `Program Files\Alpha Software\SQLBackupAndFTP AutoRunner`:
  - SYSTEM: Full Control;
  - Administrators: Full Control;
  - usuário instalador/Users/Authenticated Users/Everyone/AppContainer aplicáveis: Read & Execute, sem escrita;
- confirmar que `Get-AutoRunnerUnsafeAclEntries` não encontra escrita ampla;
- confirmar que exclusão manual em Program Files pode pedir UAC, mas a desinstalação suportada funciona.

## 2. DPI e interface

Repetir Setup, janela principal, tutorial, localização e configuração em:

- 100%, 125%, 150%, 175% e 200%;
- 1024x768 quando suportado, 1366x768, 1920x1080 e resolução alta;
- monitor primário e secundário com escalas diferentes quando disponível.

Não aceitar botões escondidos, texto truncado sem elipse, sobreposição, linhas fora do painel, fontes borradas por DPI incorreto ou controles inacessíveis. Redimensionar/maximizar e confirmar scroll onde aplicável.

## 3. SQLBackupAndFTP presente em locais diferentes

Testar instalação:

- Program Files (x86);
- Program Files;
- caminho customizado em outro diretório;
- outro volume local fixo.

Validar detecção por Registro, serviço, processo, App Paths, atalhos e busca limitada da CLI. Confirmar que seleção manual continua disponível.

## 4. SQLBackupAndFTP ausente

- instalar o AutoRunner sem SQLBackupAndFTP;
- confirmar aviso claro e automação não configurável;
- clicar **Baixar SQLBackupAndFTP**;
- confirmar que o navegador só abre após consentimento;
- confirmar abertura de `https://sqlbackupandftp.com/home/downloadlatestversion`;
- instalar o SQLBackupAndFTP depois, reabrir o AutoRunner e detectar sem reinstalar o AutoRunner.

## 5. Automação

- selecionar explicitamente um job de teste;
- registrar tarefa como SYSTEM;
- executar teste manual;
- conferir histórico e arquivo no destino;
- reiniciar o Windows e confirmar execução pós-boot;
- testar intervalo mínimo;
- testar retentativa e falha parcial com múltiplos jobs;
- remover automação e confirmar código 0/estado final removido;
- repetir remoção quando o processo filho expuser `-1` e confirmar que a pós-condição evita falso erro apenas quando tarefa/config realmente sumiram.

## 6. Atualização

Testar atualização para 2.3.5 RC a partir de:

- 2.2.5;
- 2.2.6 RC;
- 2.3.0 RC.

Estados:

- aplicativo fechado;
- aplicativo aberto;
- powershell filho referindo a instalação;
- tarefa parada;
- tarefa em execução;
- Registro de instalação ausente/corrompido quando recuperável.

Confirmar staging, rollback, fechamento de processos, preservação dos jobs e recuperação após falha injetada.

## 7. Verificador de atualização

- sem internet: interface continua abrindo e o erro não bloqueia nova tentativa futura;
- GitHub acessível e sem versão nova: informar somente quando a checagem for manual;
- release nova RC: candidata RC oferece atualização;
- release estável da mesma versão numérica: RC reconhece estável como superior;
- escolher “Não”: lembrar depois;
- escolher “Cancelar”: ignorar aquela tag automaticamente, mas permitir checagem manual;
- adulterar Setup ou `SHA256SUMS.txt`: atualização deve abortar;
- quando a instalação atual estiver assinada, testar rejeição de certificado diferente.

## 8. Reparação e desinstalação

- reparar aplicativo com e sem automação instalada;
- reparar automação;
- desinstalar pelo Setup preservado;
- desinstalar por Aplicativos Instalados;
- confirmar remoção de atalhos/Registro/arquivos;
- confirmar preservação dos jobs do SQLBackupAndFTP;
- testar opção de preservar diagnóstico.

## 9. Backup e restauração

Uma RC só pode ser promovida depois de:

1. backup executado pelo AutoRunner;
2. resultado confirmado no histórico;
3. arquivo confirmado no destino;
4. backup restaurado em ambiente de teste.
