# Changelog

## 3.0.0-RC

- adiciona Control Plane com MS-A REST/OpenAPI/Better Auth, MS-B GraphQL/Webhooks e MS-C WebSocket;
- adiciona dashboard central web;
- transforma a instalação Windows em agente outbound-only opcional;
- adiciona enrollment, inventário, presença online/offline, comandos duráveis, execução remota de jobs existentes e diagnósticos;
- adiciona API keys por organização e webhooks HMAC;
- adiciona PostgreSQL como fonte de verdade, outbox transacional e LISTEN/NOTIFY para wake-up realtime;
- adiciona Docker Compose, Caddy, migrações, bootstrap de administrador e scripts Windows de deploy/backup/restore;
- adiciona OpenAPI e schema GraphQL preenchidos;
- adiciona limites de GraphQL/WebSocket, SSRF protection, auditoria, redaction e idempotência;
- aplica a política FullControl 3.0 definida pelo produto e documenta seu risco aceito;
- preserva a automação local e as correções 2.3.5;
- mantém criação/edição/exclusão de jobs como capability-gated enquanto não existir mecanismo upstream suportado.

> Release Candidate: Docker/Windows/SQLBackupAndFTP reais ainda precisam de homologação antes de produção.

## 2.3.5 RC

Candidata de estabilização após homologação real da 2.3.0:

- corrigida a ACL da aplicação: `SYSTEM` e Administradores permanecem com controle total, enquanto usuário instalador, Users, Authenticated Users, Everyone e AppContainer recebem somente leitura/execução;
- arquivos copiados são normalizados para herdar a ACL validada e escrita ampla continua bloqueada;
- atalhos usam o ícone incorporado no launcher;
- corrigido o namespace do P/Invoke de DPI/AppUserModelID que anteriormente falhava silenciosamente;
- identidade AppUserModelID é aplicada diretamente ao HWND hospedado pelo PowerShell com interface COM/HRESULT explícita;
- propriedades `RelaunchCommand`, `RelaunchDisplayNameResource` e `RelaunchIconResource` são gravadas no HWND antes do AppUserModelID para que a taskbar use launcher/ícone próprios em vez do host PowerShell;
- painel principal e Setup passam a usar layouts responsivos, docking e scroll para evitar controles cortados em DPI alto;
- diálogos recebem `AutoScaleMode=Dpi` e posicionamento compatível com o monitor ativo;
- remoção trata o falso `ExitCode -1` somente quando a pós-condição comprova que tarefa e configuração desapareceram;
- detecção do SQLBackupAndFTP passa a agregar Registro, serviços, processos, App Paths, atalhos, caminhos conhecidos, volumes locais limitados e seleção manual;
- AutoRunner pode ser instalado sem SQLBackupAndFTP e oferece download oficial somente após confirmação;
- adicionada checagem integrada de releases e atualização opt-in validada por SHA-256;
- falha de rede não adia a próxima checagem automática;
- bootstrap elevado deixa de extrair payload no TEMP do usuário e usa diretório privado aleatório sob `Program Files`;
- reparo, desinstalação diferida, staging/rollback da automação e autocópia do desinstalador usam scratch privilegiado sob `Program Files`, com ACL exclusiva de `SYSTEM`/Administradores, GUID obrigatório e limpeza após inspeção completa da árvore;
- solicitação de instalação que atravessa o UAC é vinculada por SHA-256 à linha de comando e interpretada a partir dos mesmos bytes já validados, fechando troca TOCTOU do JSON;
- updater elevado passa a baixar artefatos em `ProgramData` protegido;
- novo gate `V235-Regression-QA.py` cobre ACL, ícones, taskbar, DPI/layout, update, detecção e remoção.

> A 2.3.5 RC só pode ser promovida após `docs/HOMOLOGACAO_2_3_5_RC.md`, incluindo boot, backup e restauração reais.

## 2.3.0

Reestruturação de estabilidade e do pipeline de release:

- removido o host .NET compilado na primeira execução;
- launcher nativo passa a iniciar diretamente o Windows PowerShell 5.1 em STA;
- reparo, atualização e desinstalação são relançados fora da pasta instalada;
- eliminada a janela TOCTOU de executar cópia elevada em pasta gravável pelo usuário;
- detecção de processos inclui linhas de comando que referenciam a instalação;
- mutex global impede manutenções concorrentes;
- upgrade usa staging e rollback em diretórios irmãos, com renomeação atômica;
- resíduos de interrupções anteriores são recuperados de forma determinística;
- erros de inspeção são separados de junctions ou links reais;
- switches nativos são reconhecidos como argumentos exatos, não por substring;
- Build-Native recompila launcher, Setup e bridge MSI com warnings como erro;
- Setup, Portable e Source são produzidos do mesmo `VERSION`;
- Source recebe inventário interno e exclui binários históricos e segredos;
- adicionados QA 2.3.0, modelo transacional, fault injection e 100.000 iterações de fuzz;
- CI passa a executar build, QA de pacotes e testes nativos no Windows.

> A 2.3.0 foi substituída pela 2.3.5 RC após testes reais revelarem problemas de ACL, abertura, ícones, DPI/layout e remoção.
## 2.2.6

Correção da atualização sobre instalações anteriores e melhoria de diagnóstico do Portable:

- removida a cópia recursiva da instalação anterior, que podia transformar uma falha de enumeração em falso aviso de junction;
- a instalação antiga agora é renomeada no mesmo volume para um diretório de rollback e restaurada por movimento em caso de falha;
- processos do AutoRunner carregados a partir da pasta antiga são encerrados antes da troca;
- a inspeção de reparse points retorna relatório estruturado e diferencia link real de erro de acesso ou enumeração;
- limpeza do backup usa remoção que não segue junctions ou links simbólicos;
- o Portable registra a saída do compilador em `%TEMP%\SQLBackupAndFTPAuto\portable-host-build.log`;
- mensagens do Portable passam a exibir código de falha e caminho do log;
- adicionada a suíte `V226-Regression-QA.py`.

> A 2.2.6 permanece candidata de homologação até passar em instalação, atualização, Portable, automação, reinicialização e backup reais no Windows x64.

## 2.2.5

Correção de integridade, ativação do Portable e acabamento visual do Setup:

- corrigido o manifesto incorporado do launcher x64 para declarar `requestedExecutionLevel level="asInvoker"`;
- o build nativo passa a usar `/manifestuac:no`, impedindo o linker de reescrever o atributo `level` em um namespace incompatível com o Side-by-Side do Windows;
- corrigido o erro do Visualizador de Eventos que impedia o Portable de iniciar;
- o host gráfico temporário do Setup agora é compilado fora do payload validado por `SHA256SUMS.txt`;
- preservada a regra rígida que rejeita arquivos realmente injetados ou não declarados no pacote;
- diretórios temporários separados em `payload` e `runtime`, com limpeza recursiva ao final;
- barra lateral do Setup reconstruída com layout responsivo;
- logo carregado diretamente do PNG validado, sem conversão defeituosa de ícone;
- título, versão e etapas separados em controles próprios, com elipse e dimensionamento previsível;
- removidas sequências literais `\r\n` exibidas na interface;
- construtores de `Icon`, `Point` e `Size` usam sobrecargas explícitas;
- build nativo passa a fixar o timestamp PE e habilitar `/Brepro`, permitindo comparar builds byte a byte;
- todas as import libraries são reconstruídas a partir dos arquivos `.def`, removendo dependência de `.lib` versionado;
- adicionada a suíte `V225-Regression-QA.py` para impedir regressão dos manifestos, da imutabilidade do payload e da barra lateral.

> A 2.2.5 é uma candidata de homologação. Ela precisa ser executada no mesmo Windows x64 que revelou os defeitos antes de ser promovida a estável.

## 2.2.4

Migração visual e de processo gráfico:

- tutorial reconstruído com `TableLayoutPanel` e `FlowLayoutPanel` para suportar DPI e redimensionamento;
- Setup, janela principal e tutorial posicionados na área útil do monitor ativo;
- removida a animação por `Opacity` das janelas normais;
- removidos construtores ambíguos `New-Object Drawing.Point(...)` e `New-Object Drawing.Size(...)`;
- introduzido host .NET Framework x64 com runspace STA para a interface principal;
- PowerShell mantido como backend interno, sem ser o aplicativo visível na barra de tarefas;
- novo ícone original multirresolução incorporado no launcher, Setup e atalhos;
- adicionada a suíte `V224-Regression-QA.py`.

> O teste em Windows revelou posteriormente um manifesto inválido no launcher, mutação do payload pelo host temporário e defeitos na barra lateral. Esses pontos são corrigidos na 2.2.5.

## 2.2.3

Correção de instalação e reformulação visual:

- corrigido falso positivo de ACL que classificava `ReadAndExecute` como escrita por usar `Modify` e `FullControl` em uma máscara composta;
- a verificação agora usa somente direitos atômicos de escrita e continua bloqueando `Write`, `Modify` e `FullControl`;
- preservadas as correções da 2.2.2 para `Application.Run()`, primeira pintura, foco, logs precoces e detecção rápida;
- painel principal reorganizado com navegação lateral, cartões de status, ações rápidas, manutenção e detalhes técnicos;
- Setup reorganizado em etapas, cartões e mensagens de estado diretas;
- tutorial redesenhado com barra de progresso e visual consistente;
- animação leve de abertura e estados de carregamento sem bloquear a interface;
- nova suíte de regressão específica da ACL e da interface 2.2.3.

> A 2.2.2 abriu corretamente no computador de homologação, mas falhou ao validar a ACL após aplicar `Users: RX`. A 2.2.3 corrige exatamente esse erro sem reduzir a proteção da pasta.

## 2.2.2

Correção do ciclo de vida e da abertura das interfaces em Windows real:

- substituído o `ShowDialog()` usado como loop principal por `Application.Run()` no aplicativo e no Setup;
- detecção inicial movida para timers disparados depois do evento `Shown`;
- adicionado modo rápido de detecção;
- restauração explícita da janela principal após o tutorial;
- abertura pós-instalação via `Shell.Application.ShellExecute`;
- logs precoces de inicialização e mensagens de falha visíveis.

## 2.2.1

Correção emergencial da instalação e do tutorial:

- corrigida incompatibilidade de sintaxe do Windows PowerShell 5.1 ao enumerar hashtables `[ordered]` no registro da aplicação;
- corrigida navegação do tutorial que podia congelar após avançar páginas;
- o estado do tutorial agora fica em um objeto compartilhado pelo formulário, sem depender de escopo de callbacks;
- tutorial inicial é aberto por temporizador após a interface principal estar pronta;
- falhas do tutorial são registradas em `manager.log` e não encerram silenciosamente a interface principal;
- incluído smoke test automatizado de avançar, voltar e concluir todas as páginas;
- ampliados os testes de regressão para impedir retorno dos dois defeitos.

## 2.2.0

### Correções

- corrigida a falha de detecção causada por entradas do Registro sem `DisplayName`;
- removido o falso status “SQLBackupAndFTP não detectado” provocado por exceções ocultadas;
- propriedades opcionais de Registro, serviços e processos agora usam acesso tolerante ao `Set-StrictMode`;
- imports do módulo usam `-DisableNameChecking`, eliminando o aviso amarelo de verbos não aprovados;
- corrigida a separação entre desinstalação do aplicativo e remoção da automação;
- a desinstalação remove os arquivos antes de atalhos e Registro, evitando instalação órfã quando um arquivo está bloqueado;
- a cópia temporária usada na desinstalação é revalidada antes da execução;
- corrigido o pacote autoextraível para remover o ZIP temporário antes da validação de integridade.

### Aplicativo e instalação

- novo launcher nativo x64 sem console;
- novo instalador gráfico autoextraível com elevação UAC;
- instalação independente em `Program Files\Alpha Software`;
- Menu Iniciar, atalho opcional na Área de Trabalho e registro em Aplicativos instalados;
- atualização, reparo, rollback e desinstalação;
- reparo não move silenciosamente a pasta instalada;
- instalador local preservado para manutenção posterior somente após validação estrutural;
- execução opcional e sem herdar o token elevado após a instalação;
- removidos launchers BAT e CMD.

### Detecção e interface

- detecção por caminho salvo, Registro, serviço, processo, App Paths, atalhos e pastas padrão;
- busca profunda limitada, sem varredura irrestrita do disco;
- seleção manual da pasta com validação de `SqlBak.Job.Cli.exe`;
- persistência e revalidação do caminho selecionado;
- exibição de caminho, versão, fonte da detecção e serviço;
- tutorial inicial com opção de pular e não mostrar novamente;
- botão permanente de ajuda;
- distinção entre localizar o SQLBackupAndFTP, instalar/reparar/remover automação e manter o aplicativo.

### Segurança nativa e transacional

- buffers nativos com capacidade explícita e limite de 32.768 caracteres;
- falha controlada se a linha de comando ultrapassar o limite seguro;
- RNG criptográfico do Windows sem fallback previsível;
- diretórios temporários exclusivos para extração, staging, backup, integrações e desinstalação;
- ACL temporária restrita a `SYSTEM` e Administradores;
- rollback condicionado ao ponto real de mutação;
- restauração da instalação anterior com reaplicação das ACLs;
- resíduos de desinstalação são consolidados e informados ao operador.

### Robustez mantida e ampliada

- seleção explícita dos jobs;
- jobs não agendados ou de baixa confiança exigem confirmação;
- mutex com recuperação de abandono;
- continuidade após falha individual;
- retentativas controladas;
- intervalo mínimo individual por job;
- logs rotativos, estado individual e JSON atômico;
- ACL, manifesto, hashes, validação de CLI e proteção contra reparse points;
- diagnóstico em ZIP;
- suíte de QA estático, comportamental, adversarial, regressão e fuzzing.

## 2.1.0 RC

Reestruturação inicial do runner, segurança, configuração, reparo, logs e QA. Substituída pela 2.2.0 devido à correção do detector e à nova distribuição como aplicativo instalado.
