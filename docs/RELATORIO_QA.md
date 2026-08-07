# Relatório de QA 2.3.5 RC

## Escopo

A 2.3.5 RC consolida as correções que seriam distribuídas em versões intermediárias. O trabalho partiu dos defeitos confirmados em Windows nas versões 2.2.5 e 2.2.6:

- falso diagnóstico de junction quando a inspeção falhava por outro motivo;
- acesso negado durante atualização sobre uma instalação existente;
- inicialização do Portable dependente de host .NET compilado localmente;
- código-fonte e artefatos de release sem origem única e reproduzível.

## Correções estruturais

- launcher nativo x64 chama diretamente o Windows PowerShell 5.1 em modo STA;
- removida a compilação de host .NET na máquina do cliente;
- Setup preservado em `Program Files` relança manutenção por uma cópia privada externa, criada somente após a elevação;
- processos relacionados são identificados pelo executável e pela linha de comando;
- instalação nova é montada em staging irmão da pasta final;
- versão anterior é renomeada para rollback no mesmo volume;
- promoção e restauração usam renomeação atômica;
- resíduos de transações interrompidas são recuperados de forma determinística;
- mutex global impede duas manutenções concorrentes;
- mutex por usuário impede duas interfaces interativas simultâneas;
- Setup, Portable e Source são produzidos pelo mesmo builder e recebem inventários SHA-256 completos;
- launcher, Setup base e bridge MSI são recompilados pelo mesmo build nativo;
- argumentos nativos usam comparação exata, sem ativação acidental por substring;
- pipeline de CI inclui Linux para modelos/pacotes e Windows para AST, integração e smoke tests gráficos.

## Validação executada neste ambiente

Foram executados com resultado aprovado:

- compilação nativa x64 com avisos tratados como erro;
- inspeção PE32+ GUI, manifestos, ASLR, NX e high-entropy VA;
- QA estático, profundo e adversarial;
- regressões das linhas 2.2.x e regressão específica 2.3.5 RC;
- modelo comportamental do runner;
- modelo transacional de upgrade com falhas determinísticas;
- 100.000 cenários aleatórios de upgrade;
- 100.000 cenários da máquina de estados do runner;
- ataques contra payload, hashes, arquivos injetados, traversal e duplicidade por caixa;
- validação integral dos ZIPs Portable e Source;
- duas compilações independentes dos três artefatos com igualdade byte a byte.

Os relatórios JSON e logs usados nessa conclusão acompanham o pacote de evidências de QA da release.

## Limites objetivos

Este ambiente não executa Windows PowerShell 5.1, Windows Forms, NTFS, UAC, Agendador de Tarefas ou SQLBackupAndFTP real. Portanto, ainda são obrigatórios em Windows x64:

- parser AST oficial de todos os scripts;
- smoke test da interface e do tutorial;
- instalação limpa, reparo, atualização e desinstalação;
- matriz de upgrade desde 2.2.0 até 2.2.6;
- ACL real e tarefa executada como `SYSTEM`;
- reinicialização real;
- backup confirmado no histórico e no destino;
- restauração do backup em ambiente de teste.

A 2.3.5 RC deve permanecer **candidata de homologação** até concluir esses testes. Aprovação dos modelos e pacotes não equivale a comprovação de backup real.
