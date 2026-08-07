# Plano de testes 2.3.5 RC

## Gates automatizados

- parser e regras estáticas;
- revisão profunda e adversarial;
- regressões históricas 2.2 e gate 2.3.5 RC;
- modelo comportamental do runner;
- modelo transacional com falha antes de cada etapa;
- 100.000 iterações de fuzz da máquina de estados;
- compilação C com `/W4 /WX`;
- PE32+ x64, GUI, manifestos e mitigadores;
- Setup autoextraível e inventário interno;
- ataques de trailer, tamanho, truncamento, payload, traversal, duplicidade e injeção;
- Portable com hash externo e inventário interno;
- Source com inventário interno, completude e exclusão de segredos;
- build duplo byte a byte.

## Windows nativo

- parser AST oficial de todos os `.ps1` e `.psm1`;
- fake CLI e runner real;
- escrita JSON, manifesto e configuração;
- ACL NTFS;
- junction ancestral;
- tarefa real do Agendador;
- interface e tutorial WinForms;
- fechamento e reabertura da interface;
- instalação, atualização, reparo e desinstalação.

## Matriz de upgrade

Testar origem 2.2.0, 2.2.1, 2.2.2, 2.2.3, 2.2.4, 2.2.5 e 2.2.6 para 2.3.5 RC com:

- aplicação fechada;
- aplicação aberta;
- PowerShell órfão;
- tarefa ativa;
- arquivo temporariamente bloqueado;
- ACL padrão e alterada;
- resíduo `.stage-*`;
- resíduo `.rollback-*`;
- interrupção antes e depois de cada renomeação.

Após qualquer falha deve existir uma versão antiga ou nova íntegra, nunca uma pasta principal vazia.

## Homologação real

1. instalar o SQLBackupAndFTP e criar um job de banco de teste;
2. instalar 2.3.5 RC limpa;
3. executar Portable em pasta nova;
4. configurar e testar o job;
5. conferir histórico e arquivo;
6. reiniciar o Windows e conferir o gatilho;
7. simular SQL Server e destino indisponíveis;
8. testar falha parcial com vários jobs;
9. reparar automação e aplicativo;
10. atualizar a partir de cada versão anterior disponível;
11. remover automação;
12. desinstalar aplicativo;
13. confirmar preservação dos jobs originais;
14. restaurar o backup em ambiente de teste.

## Gate final

A release só pode ser marcada como estável depois de CI verde e homologação em Windows x64 com backup, reinicialização e restauração reais.
