# Plano de uso e negócio

## Problema atendido

Clientes desligam o servidor e perdem o horário agendado. O AutoRunner dispara jobs selecionados quando o Windows inicia, após atraso configurável.

## Público

- pequenos e médios clientes Alpha;
- SQL Server Express ou ambientes sem SQL Agent;
- servidores ligados apenas durante o expediente;
- equipes sem administração de infraestrutura contínua.

## Regra de uso

O AutoRunner não procura qual horário foi perdido. Ele executa os jobs selecionados em cada boot, respeitando o intervalo mínimo configurado.

## Implantação padrão

- instalador EXE único;
- detecção automática do SQLBackupAndFTP;
- um job principal selecionado;
- atraso inicial de 5 minutos;
- intervalo mínimo conforme política do cliente;
- teste manual e conferência do destino;
- documentação da responsabilidade de restauração.

## Suporte

N1:
- localizar instalação;
- configurar job;
- testar;
- abrir logs e diagnóstico.

N2:
- analisar tarefa, ACL, manifesto, eventos e CLI;
- validar incompatibilidades de versão;
- revisar falhas de destino ou serviço.

## Indicadores

- instalações concluídas;
- jobs executados por boot;
- falhas parciais;
- clientes com restauração testada;
- incidentes evitados por intervalo mínimo;
- tempo médio de diagnóstico.
