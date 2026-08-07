#!/usr/bin/env python3
"""Revisão adversarial independente, sem executar PowerShell.
Procura classes de falhas que os testes orientados a requisitos podem não detectar.
"""
from __future__ import annotations
import json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test-results" / "adversarial-review.json"
results: list[dict[str, object]] = []

def add(name: str, ok: bool, detail: str) -> None:
    results.append({"name": name, "status": "PASS" if ok else "FAIL", "detail": detail})
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")

def text(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8-sig")

ps_files = sorted([*ROOT.glob("modules/*.psm1"), *ROOT.glob("scripts/*.ps1"), *ROOT.glob("build/*.ps1")])
all_ps = "\n".join(p.read_text(encoding="utf-8-sig") for p in ps_files)

# 1. Padrões de execução dinâmica/remota.
for label, pattern in {
    "Sem Invoke-Expression": r"\b(?:Invoke-Expression|iex)\b",
    "Sem download arbitrário por APIs dinâmicas": r"\b(?:DownloadString|DownloadFile|Start-BitsTransfer|Net\.WebClient)\b",
    "Sem ScriptBlock criado de texto": r"\[ScriptBlock\]::Create|CreateScriptBlock",
    "Sem senha fixa provável": r"(?i)(password|senha)\s*[=:]\s*['\"][^'\"]{4,}['\"]",
}.items():
    hits = [f"{p.name}:{i+1}" for p in ps_files for i,l in enumerate(p.read_text(encoding='utf-8-sig').splitlines()) if re.search(pattern,l)]
    add(label, not hits, "nenhuma ocorrência" if not hits else ", ".join(hits[:20]))

# Invoke-WebRequest is intentionally allowed only in the dedicated updater.
# The updater must pin the official repository, require HTTPS, download the
# checksum inventory and exact Setup asset, verify SHA-256 before execution,
# and preserve signer continuity when the installed copy is signed.
web_hits = []
for p in ps_files:
    for i,l in enumerate(p.read_text(encoding='utf-8-sig').splitlines()):
        if re.search(r"\bInvoke-WebRequest\b", l):
            web_hits.append((p.name, i+1))
allowed_web = all(name == 'Update-AutoRunner.ps1' for name,_ in web_hits) and len(web_hits) == 2
updater_src = text('scripts/Update-AutoRunner.ps1')
updater_secure = all(x in updater_src for x in [
    "https://api.github.com/repos/",
    "releases/tags/",
    "SHA256SUMS.txt",
    "Get-FileHash -LiteralPath $setupPath -Algorithm SHA256",
    "$uri.Scheme -ne 'https'",
    "$uri.Host -ine 'github.com'",
    "Get-AuthenticodeSignature -FilePath $currentSetup",
    "Get-AuthenticodeSignature -FilePath $setupPath",
    "SignerCertificate.Thumbprint",
])
add('Download de atualização restrito e autenticado', allowed_web and updater_secure,
    'Invoke-WebRequest permitido apenas no updater com URL oficial, SHA-256 e continuidade de assinatura' if allowed_web and updater_secure else f'hits={web_hits}, invariantes={updater_secure}')

# 2. Duplicidade de parâmetros em blocos param simples. Parser balanceado de parênteses.
def param_blocks(src: str):
    for m in re.finditer(r"(?im)^\s*param\s*\(", src):
        start=m.end(); depth=1; quote=None; i=start
        while i < len(src) and depth:
            c=src[i]
            if quote:
                if c==quote and (i==0 or src[i-1] != '`'): quote=None
            elif c in "'\"": quote=c
            elif c=='(': depth+=1
            elif c==')': depth-=1
            i+=1
        if depth==0: yield src[start:i-1]

def top_level_parts(block: str):
    parts=[]; start=0; depth=0; quote=None
    for i,c in enumerate(block):
        if quote:
            if c==quote and (i==0 or block[i-1] != '`'): quote=None
        elif c in "'\"": quote=c
        elif c in '([{': depth+=1
        elif c in ')]}': depth=max(0,depth-1)
        elif c==',' and depth==0:
            parts.append(block[start:i]); start=i+1
    parts.append(block[start:])
    return parts

dup_params=[]
for p in ps_files:
    for n,block in enumerate(param_blocks(p.read_text(encoding='utf-8-sig')),1):
        names=[]
        for part in top_level_parts(block):
            declaration=part.split('=',1)[0]
            vars_found=re.findall(r"\$([A-Za-z_][A-Za-z0-9_]*)",declaration)
            if vars_found: names.append(vars_found[-1].lower())
        dups=sorted({x for x in names if names.count(x)>1})
        if dups: dup_params.append(f"{p.name} bloco {n}: {','.join(dups)}")
add("Sem parâmetros duplicados", not dup_params, "nenhum" if not dup_params else "; ".join(dup_params))

# 3. Remoções recursivas devem estar cercadas por guardas de caminho ou limitar-se a TEMP/staging.
recursive=[]
for p in ps_files:
    lines=p.read_text(encoding='utf-8-sig').splitlines()
    for i,l in enumerate(lines):
        if re.search(r"Remove-Item\b.*-Recurse",l,re.I):
            ctx="\n".join(lines[max(0,i-15):i+3])
            if not re.search(r"Test-AutoRunner(?:SupportPath|TreeHasReparsePoint|PathIsWithin)|Remove-AutoRunnerPrivilegedScratchDirectory|New-AutoRunnerPrivilegedScratchDirectory|Remove-(?:ApplicationDirectorySafe|SetupTemporaryDirectorySafe)|Assert-SafeApplicationPath|Get-AutoRunnerTreeInspection|\$env:TEMP|\$env:ProgramFiles|\$stage|\$work|\$rollback|\$snapshot|\$temp|\$sim|\$aclDir|\$base|\$full|\$parent|HKLM:|\$machineKey|\$uninstallKey",ctx,re.I):
                recursive.append(f"{p.name}:{i+1}")
add("Remoções recursivas possuem escopo/guarda", not recursive, "todas guardadas" if not recursive else ", ".join(recursive))
privileged_helper = text("modules/AutoRunner.Core.psm1")
helper_slice = privileged_helper[privileged_helper.find("function Remove-AutoRunnerPrivilegedScratchDirectory"):privileged_helper.find("function Get-AutoRunnerTreeInspection")]
add("Scratch privilegiado só é removido sob Program Files com GUID e inspeção", all(x in helper_slice for x in [
    "$parent -ine $base",
    "^[A-Fa-f0-9]{32}$",
    "Get-AutoRunnerTreeInspection -Path $full",
    "InspectionSucceeded",
    "HasReparsePoint",
    "Remove-Item -LiteralPath $full -Recurse -Force",
]), "helper valida raiz imediata, nome transacional e árvore antes de remover")

# 4. Invariantes do bootstrap e execução SYSTEM.
runner=text("scripts/Run-SQLBackupAndFTPJob.ps1")
module=text("modules/AutoRunner.Core.psm1")
installer=text("scripts/Install-SQLBackupAndFTP-Auto.ps1")
manager=text("scripts/Manager.ps1")
uninstaller=text("scripts/Uninstall-SQLBackupAndFTP-Auto.ps1")
add("Hash do módulo é verificado antes do Import-Module", runner.find("Get-FileHash") < runner.find("Import-Module"), "ordem de bootstrap correta")
add("Runner valida configuração centralmente", "Test-AutoRunnerConfiguration -Config $config -RequireSecurityHashes -RequireExistingCli" in runner, "validação fail-closed")
add("Manifesto não pode ser desligado", "$new.Security.EnforceManifest = $true" in module and "EnforceManifest deve permanecer habilitado" in module, "forçado no schema e validado")
add("CLI é revalidada no instalador e no runtime", installer.count("Test-AutoRunnerExecutionPathSecurity") >= 1 and runner.count("Test-AutoRunnerExecutionPathSecurity") >= 1, "dupla barreira")
add("ACL de ancestrais da CLI é verificada sem varredura do volume", "Get-AutoRunnerUnsafeAclEntries -Path $ancestor -CurrentOnly" in module and "$root.TrimEnd" in module, "impede substituição por diretório pai gravável")
add("Manifesto rejeita traversal sem TrimStart permissivo", "$parts -contains '..'" in module and "TrimStart('./')" not in module, "caminho malicioso não é reescrito como válido")
add("Pacote rejeita qualquer arquivo não declarado", "Cada arquivo do pacote, sem exceções silenciosas" in module, "sem exceção para .bak/logs injetados")
add("Tarefa SYSTEM usa IgnoreNew e SupportDir explícito", all(x in module for x in ["-UserId 'SYSTEM'","MultipleInstances = 'IgnoreNew'","'-SupportDir',$SupportDir"]), "ação e principal conferidos")
add("Mutex abandonado é recuperado", "AbandonedMutexException" in runner and "$hasMutex = $true" in runner, "continuidade após encerramento abrupto")
add("Estado antigo é normalizado", "ConvertTo-AutoRunnerCurrentState" in module and "Read-AutoRunnerState" in module, "campos ausentes não quebram StrictMode")
add("Estado individual não acessa sucesso anterior diretamente", "$previousJobState.LastSuccessfulRunUtc" not in runner, "acesso tolerante por helper")

# 5. Riscos de repetição.
add("Retry em código CLI é opt-in", "RetryOnCliError = $false" in module and "if(-not $retryOnCliError)" in runner, "padrão evita possível duplicidade")
add("Reinício da tarefa com intervalo zero exige confirmação", "Risco de repetição" in manager and "Confirma esta combinação de risco" in manager, "console e GUI alertam")
add("Falha de job não lança exceção global", "throw" not in runner[runner.find("for ($attempt"):runner.find("$resultItem")], "loop consolida resultado")
add("StopOnFirstFailure audita jobs não executados", "Não executado após falha anterior" in runner and "ExitCode=14" in runner, "rastreabilidade mantida")

# 6. Integridade de pacote/build.
build_release=text("build/Build-Release.py")
build_msi=text("build/Build-MSI.ps1")
setup_native=text("native/setup.c")
setup_wizard=text("scripts/Setup-Wizard.ps1")
add("Pacote usa allowlist, staging e checksum interno/externo", all(x in build_release for x in ["RUNTIME_FILES","TemporaryDirectory","SHA256SUMS.txt","sha256.txt","verify_inventory_zip"]), "cadeia de empacotamento determinística")
add("MSI usa payload de produção e regenera checksums", "Build-Release.py" in build_msi and "Payload MSI inválido após regenerar checksums" in build_msi and ".git" not in build_msi, "não copia a árvore de desenvolvimento")
add("Setup autoextraível usa RNG e ACL privada", "BCryptGenRandom" in setup_native and "D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)" in setup_native, "temporário não é gravável pelo usuário comum")
add("Remoção da aplicação usa helper canônico", setup_wizard.count("Remove-ApplicationDirectorySafe") >= 4 and "Assert-SafeApplicationPath" in setup_wizard, "rollback e desinstalação usam a mesma fronteira")
add("MSI não remove automação em major upgrade", "NOT UPGRADINGPRODUCTCODE" in build_msi, "atualização preserva configuração operacional")
add("Assinatura de release disponível", (ROOT/"build/Sign-Release.ps1").exists() and "Set-AuthenticodeSignature" in text("build/Sign-Release.ps1"), "requer certificado externo")

# 7. Desinstalação segura e preservação do produto terceiro.
add("Desinstalador verifica identidade", "config Product" in uninstaller or "Configuração" in uninstaller or "config -Name 'Product'" in uninstaller, "produto conferido")
add("Desinstalador verifica reparse antes de apagar", uninstaller.count("Test-AutoRunnerTreeHasReparsePoint") >= 2, "checagem inicial e final")
add("Desinstalador não aponta para pasta Pranas/SQLBackupAndFTP", not re.search(r"Remove-Item[^\n]*(?:Pranas|SQLBackupAndFTP(?!Auto))",uninstaller,re.I), "somente AutoRunner")

# 8. Documentação de limites honestos.
docs="\n".join(p.read_text(encoding='utf-8-sig') for p in ROOT.glob("docs/*.md")) + text("README.md")
add("Documentação não promete comprovação pelo exit 0", "não comprova" in docs.lower() or "não confirma" in docs.lower(), "limite da CLI documentado")
add("Documentação exige homologação Windows", "homologa" in docs.lower() and "windows" in docs.lower(), "gate de release documentado")
add("Documentação distingue boot de horário perdido", "não identifica" in docs.lower() or "não procura" in docs.lower(), "sem promessa incorreta")

OUT.parent.mkdir(parents=True,exist_ok=True)
OUT.write_text(json.dumps({"suite":"adversarial-review","results":results,"pass":sum(r['status']=='PASS' for r in results),"fail":sum(r['status']=='FAIL' for r in results)},ensure_ascii=False,indent=2),encoding='utf-8')
print(f"Relatório: {OUT}")
sys.exit(1 if any(r['status']=='FAIL' for r in results) else 0)
