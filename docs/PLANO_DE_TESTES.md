# Plano de testes 2.2.1

## Automatizados e portáveis

- análise lexical de PowerShell;
- codificação, BOM, NUL e espaços finais;
- revisão estática, profunda e adversarial independentes;
- modelo comportamental;
- fuzzing da máquina de estados;
- regressões específicas da 2.2.1;
- compilação nativa com avisos tratados como erro;
- analisador estático Clang;
- reprodutibilidade byte a byte dos binários e dos artefatos;
- validação PE32+ x64 GUI e imports mínimos;
- verificação do ZIP e do Setup autoextraível;
- mutações de trailer, tamanho, payload, traversal, duplicidade, link e arquivo não declarado;
- auditoria do XML WiX gerado estaticamente.

## Nativos em Windows

Executar `scripts\Invoke-QA.ps1 -Integration` como administrador para:

- parser AST oficial do PowerShell;
- fake CLI e runner real;
- construção e fechamento da interface Windows Forms;
- ACL NTFS;
- junction ancestral;
- registro, execução e remoção de tarefa real;
- configuração e estado reais.

## Homologação com SQLBackupAndFTP

1. instalar uma versão suportada do SQLBackupAndFTP;
2. criar job para banco de teste;
3. instalar o AutoRunner pelo Setup EXE;
4. validar detecção por Registro, serviço, pasta padrão e seleção manual;
5. configurar o job;
6. testar chamada manual;
7. verificar histórico e arquivo no destino;
8. reiniciar o Windows e verificar o gatilho;
9. testar intervalo mínimo por job;
10. simular SQL Server e destino temporariamente indisponíveis;
11. testar falha parcial com mais de um job;
12. reparar automação;
13. reparar aplicativo;
14. atualizar sobre uma instalação existente;
15. remover somente a automação;
16. desinstalar o aplicativo;
17. confirmar preservação dos jobs originais;
18. restaurar o backup em ambiente de teste.

## MSI

Antes de distribuir um MSI, é obrigatório compilar com WiX v4 em Windows, executar validação ICE aplicável, instalar/reparar/atualizar/remover com `msiexec`, confirmar limpeza e preservação durante upgrade e testar instalação silenciosa.

## Gate de release

A release para clientes só deve ser declarada homologada após os testes nativos e um backup/restauração reais. Testes portáveis aprovados não substituem Windows, Agendador, NTFS ou SQLBackupAndFTP reais.
