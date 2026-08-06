# Histórico de versões

## 2.2.5

Versão corretiva recomendada para homologação. Corrige três defeitos confirmados em Windows na 2.2.4:

- o launcher Portable não iniciava porque o manifesto incorporado possuía `requestedExecutionLevel` sem o atributo `level` reconhecido pelo Side-by-Side;
- o Setup compilava `SQLBackupAndFTP-AutoRunner.SetupHost.exe` dentro do payload já validado, fazendo a segunda verificação de integridade rejeitar o próprio arquivo gerado;
- a barra lateral podia exibir logo corrompido, título recortado e sequências literais `\r\n`.

A correção mantém o payload estritamente imutável. O host temporário é gerado em uma área `runtime` separada e toda a raiz temporária privada é removida ao final. Os manifestos nativos são incorporados sem reescrita automática de UAC pelo linker.

## 2.2.4

Introduziu o host .NET Framework x64, o ícone próprio, o tutorial responsivo e o posicionamento das janelas no monitor ativo. Foi substituída pela 2.2.5 após testes reais revelarem os defeitos de manifesto, integridade do Setup e barra lateral.

## 2.2.3

Corrigiu o falso positivo de ACL que classificava `BUILTIN\Usuários: ReadAndExecute, Synchronize` como permissão de escrita. Também introduziu o painel em cartões e navegação lateral. Foi substituída pela 2.2.5 após os testes em Windows revelarem problemas de DPI, posicionamento e identidade do processo gráfico.

## 2.2.2

Corrigiu processos que permaneciam em segundo plano sem exibir o Setup ou a janela principal depois do tutorial. Introduziu `Application.Run`, detecção inicial atrasada, recuperação de foco e logs de inicialização. Foi substituída pela 2.2.3 após o falso bloqueio de ACL.

## 2.2.1

Corrigiu a sintaxe de hashtable ordenada no Windows PowerShell 5.1 e a navegação interna do tutorial. Foi substituída pela 2.2.2 após o teste em Windows revelar falhas de exibição e ciclo da interface.

## 2.2.0

Introduziu o aplicativo instalado, launcher x64 sem console, Setup autoextraível, detecção multicamada, tutorial e manutenção gráfica. Foi substituída pela 2.2.1 devido a falhas no instalador PowerShell 5.1 e na navegação do tutorial.

## 2.1.0 RC

Primeira reestruturação ampla do runner, com seleção explícita, logs, reparo, segurança e QA. Usava launchers BAT/CMD e foi substituída pela linha 2.2.x.

## Política

- versões substituídas permanecem para auditoria e histórico;
- a versão mais recente corrigida deve ser usada em novas homologações;
- uma release só recebe status estável após instalação, interface, ACL, tarefa, backup, reinicialização e restauração reais em Windows x64.
