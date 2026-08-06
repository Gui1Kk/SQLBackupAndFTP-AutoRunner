# Notas da versão 2.2.5

A 2.2.5 corrige três defeitos confirmados em Windows na versão 2.2.4.

## Portable

O manifesto PE do launcher agora contém `requestedExecutionLevel level="asInvoker" uiAccess="false"`. O build usa `/manifestuac:no` junto de `/manifestinput`, evitando que o linker gere o atributo inválido `ms_asmv1:level`. Isso corrige a falha de contexto de ativação registrada no Visualizador de Eventos.

## Setup e integridade

O ZIP validado é extraído para `payload`. O `SetupHost.exe`, que é criado em tempo de execução, passa a ser compilado em `runtime`, fora do payload e fora da contagem de `SHA256SUMS.txt`. A verificação continua recusando qualquer arquivo injetado no payload.

## Interface do instalador

A barra lateral usa painéis responsivos, logo PNG validado, título e versão em linhas separadas e uma linha própria para cada etapa. Sequências literais `\r\n` não são usadas em textos visíveis.

## Estado

Release Candidate para Windows x64. A promoção a estável exige instalação, abertura do Portable, tutorial, detecção, automação, reinicialização, backup e restauração reais.
