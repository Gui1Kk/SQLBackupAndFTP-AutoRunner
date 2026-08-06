# Changelog

## 2.2.1

Correção emergencial da instalação e do tutorial:

- corrigida incompatibilidade de sintaxe do Windows PowerShell 5.1 ao enumerar hashtables `[ordered]` no registro da aplicação;
- corrigida navegação do tutorial que podia congelar após avançar páginas;
- estado do tutorial movido para objeto compartilhado pelo formulário;
- falhas do tutorial passam a ser registradas em `manager.log` sem encerrar silenciosamente a interface;
- incluído smoke test de avançar, voltar e concluir todas as páginas;
- ampliados os testes de regressão.

## 2.2.0

- corrigida falha de detecção causada por entradas do Registro sem `DisplayName`;
- novo launcher nativo x64 sem console;
- novo instalador gráfico autoextraível com elevação UAC;
- instalação independente em `Program Files\Alpha Software`;
- atalhos, reparo, atualização, rollback e desinstalação;
- detecção por caminho salvo, Registro, serviço, processo, App Paths, atalhos e pastas padrão;
- seleção manual da pasta com validação de `SqlBak.Job.Cli.exe`;
- tutorial inicial e botão permanente de ajuda;
- ACLs restritivas, validação SHA-256 e proteção contra traversal, links e junctions.

## 2.1.0 RC

- seleção explícita de jobs;
- logs e estado por job;
- reparo e remoção da automação;
- validações de segurança e QA;
- pacote legado baseado em scripts auxiliares.
