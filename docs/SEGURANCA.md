# Segurança

## Modelo de ameaça

A tarefa executa como `SYSTEM`. Qualquer arquivo carregado por ela precisa estar protegido contra escrita por usuários comuns. O instalador também precisa impedir que um pacote temporário ou uma cópia de manutenção seja substituído entre validação e execução.

## Controles

- aplicação em pasta própria de `Program Files`;
- runtime e scripts protegidos por ACL;
- usuários comuns recebem somente leitura operacional de configuração, estado e logs;
- nenhum usuário comum recebe escrita em scripts, módulo, manifesto ou CLI;
- validação de permissões nos diretórios ancestrais da CLI;
- manifesto SHA-256 obrigatório;
- módulo validado antes de `Import-Module` no runner;
- recusa de arquivos não declarados, path traversal, duplicidade e reparse points;
- JSON atômico com arquivo de recuperação;
- staging, backup, integração e desinstalação diferida em diretórios privados;
- ACL temporária sem herança e limitada a `SYSTEM` e Administradores;
- RNG criptográfico `BCryptGenRandom`; falha do RNG cancela o Setup;
- buffers nativos limitados e cancelamento em linha de comando longa;
- Setup preservado somente quando contém MZ, trailer correto e payload coerente;
- reparo mantém a pasta registrada e exige desinstalação para mudança de local;
- rollback restaura arquivos, Registro, atalhos, preferências e ACL conforme o estágio alcançado;
- desinstalação remove a aplicação antes de apagar sua referência no Registro;
- nenhuma credencial é armazenada pelo AutoRunner.

## Limites

`SHA256SUMS.txt` detecta corrupção, mas não autentica o publicador se um invasor puder substituir pacote e checksums. A distribuição oficial deve incluir:

- hash externo publicado por canal confiável;
- assinatura Authenticode quando a Alpha possuir certificado de código com chave privada.

O AutoRunner não valida semanticamente o conteúdo do backup. Histórico, arquivo no destino e testes periódicos de restauração continuam obrigatórios.
