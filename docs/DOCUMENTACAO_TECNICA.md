# Documentação técnica 2.3.5 RC

## Fluxo principal

```text
SQLBackupAndFTP-AutoRunner.exe, PE32+ x64, asInvoker
  -> Windows PowerShell 5.1, STA, janela oculta
     -> scripts\Manager.ps1
        -> modules\AutoRunner.Core.psm1
        -> ProgramData\SQLBackupAndFTPAuto
        -> Agendador de Tarefas, SYSTEM
        -> SqlBak.Job.Cli.exe
```

A 2.3.5 RC não gera nem executa um host .NET na primeira abertura. Isso remove dependências de `csc.exe`, seleção de CLR, cache de host e arquivos `.exe.config` produzidos localmente.

## Setup

O Setup é um PE x64 elevado com um ZIP anexado. Ele:

1. cria um diretório privado aleatório sob `Program Files`, com ACL exclusiva para `SYSTEM` e Administradores;
2. extrai o ZIP interno;
3. apaga o ZIP temporário antes da validação de completude;
4. valida `SHA256SUMS.txt`;
5. recusa traversal, duplicidade, arquivo ausente, arquivo injetado e hash divergente;
6. executa `Setup-Wizard.ps1` em PowerShell 5.1 STA;
7. limpa a área temporária.

Os switches `/repair`, `/uninstall`, `/silent`, `/desktop`, `/nolaunch`, `/purgedata`, `/deferred` e `/notutorial` são reconhecidos como argumentos completos.

## Atualização

A nova instalação é copiada para:

```text
.<nome>.stage-<GUID>
```

A versão anterior é movida para:

```text
.<nome>.rollback-<GUID>
```

Os dois diretórios ficam ao lado da instalação definitiva, garantindo o mesmo volume. A promoção usa `System.IO.Directory.Move`. Antes da troca, a árvore antiga é inspecionada sem seguir reparse points e processos que referenciam a pasta pelo executável ou pela linha de comando são encerrados.

Uma exceção restaura a versão antiga. Na próxima execução, stages obsoletos são removidos e um rollback único é restaurado quando a pasta principal estiver ausente. Ambiguidade com múltiplos rollbacks falha fechada.

## Auto-bloqueio e scratch privilegiado

Quando o Setup preservado dentro da instalação é usado para reparar ou desinstalar, o wizard elevado externaliza o instalador para um diretório privado de nome GUID sob `Program Files`, valida estrutura e SHA-256, relança com `/deferred` e encerra a instância original antes de mover a pasta. A limpeza aceita apenas um filho imediato de `Program Files` com prefixo conhecido, sufixo GUID exato, inspeção bem-sucedida e ausência de reparse points.

A interface principal não cria uma cópia elevada em `LOCALAPPDATA` nem usa `%TEMP%` do usuário como fronteira de confiança. Ela valida o Setup instalado e solicita elevação; a externalização ocorre somente após a elevação. O staging/rollback da automação e a autocópia do desinstalador seguem o mesmo padrão. Solicitações JSON que atravessam o UAC são vinculadas por SHA-256 à linha de comando e analisadas a partir do mesmo buffer validado.

## Identidade visual hospedada

A interface continua sendo PowerShell/WinForms, mas não depende da identidade visual do `powershell.exe`. O HWND recebe, via `IPropertyStore`, `RelaunchCommand`, `RelaunchDisplayNameResource`, `RelaunchIconResource` e depois `AppUserModelID`, apontando para o launcher nativo. O formulário também recebe o ICO incorporado ao pacote.

## Concorrência

- mutex global para instalação, reparo e desinstalação;
- mutex local por SID para a interface;
- mutex do runner com recuperação de abandono;
- tarefa com política `IgnoreNew`.

## Diretórios

- aplicação: `C:\Program Files\Alpha Software\SQLBackupAndFTP AutoRunner`;
- operação: `C:\ProgramData\SQLBackupAndFTPAuto`;
- preferências: `HKCU\Software\Alpha Software\SQLBackupAndFTP AutoRunner`;
- registro da aplicação: `HKLM\Software\Alpha Software\SQLBackupAndFTP AutoRunner`.

## Segurança

Arquivos executados como `SYSTEM` são validados por hash e por ACL. Caminhos da CLI e seus ancestrais são recusados quando graváveis por identidades amplas. Manifesto, configuração e estado são escritos de forma atômica. A remoção não segue links e não opera fora das raízes registradas.

## Códigos relevantes do runner

- `0`: execução concluída ou condição normal sem disparo;
- `10`: falha consolidada;
- `11`: falha da CLI;
- `12`: todos os jobs ignorados pelo intervalo;
- `13`: outra execução manual já ativa;
- `14`: job não executado após parada configurada;
- `23`: CLI em caminho inseguro.
