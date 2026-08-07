#!/usr/bin/env python3
"""Regression gate preserving the architectural invariants introduced in 2.3.0."""
from __future__ import annotations

import json
import re
import struct
import sys
import xml.etree.ElementTree as ET
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
RESULTS: list[dict[str, object]] = []


def read(rel: str) -> str:
    return (ROOT / rel).read_text(encoding="utf-8-sig")


def add(name: str, passed: bool, detail: str) -> None:
    RESULTS.append({"name": name, "passed": bool(passed), "detail": detail})
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")


def pe_info(path: Path) -> dict[str, int]:
    data = path.read_bytes()
    if data[:2] != b"MZ":
        raise ValueError("MZ ausente")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe : pe + 4] != b"PE\0\0":
        raise ValueError("PE ausente")
    coff = pe + 4
    machine = struct.unpack_from("<H", data, coff)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    subsystem = struct.unpack_from("<H", data, opt + 68)[0]
    dll_chars = struct.unpack_from("<H", data, opt + 70)[0]
    return {"machine": machine, "magic": magic, "subsystem": subsystem, "dll_chars": dll_chars, "size": len(data)}


def manifest_from_pe(path: Path) -> str:
    data = path.read_bytes()
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    coff = pe + 4
    nsec = struct.unpack_from("<H", data, coff + 2)[0]
    optsz = struct.unpack_from("<H", data, coff + 16)[0]
    opt = coff + 20
    magic = struct.unpack_from("<H", data, opt)[0]
    dd = opt + (112 if magic == 0x20B else 96)
    rva, _size = struct.unpack_from("<II", data, dd + 16)
    sec = opt + optsz
    sections: list[tuple[int, int, int]] = []
    for index in range(nsec):
        offset = sec + index * 40
        vsize, vaddr, rsize, raw = struct.unpack_from("<IIII", data, offset + 8)
        sections.append((vaddr, max(vsize, rsize), raw))

    def raw_offset(value: int) -> int:
        for vaddr, size, raw in sections:
            if vaddr <= value < vaddr + size:
                return raw + value - vaddr
        raise ValueError("RVA fora das seções")

    root = raw_offset(rva)

    def entries(relative: int) -> list[tuple[int, int]]:
        current = root + relative
        named, identifiers = struct.unpack_from("<HH", data, current + 12)
        return [struct.unpack_from("<II", data, current + 16 + index * 8) for index in range(named + identifiers)]

    type_entry = next((entry for entry in entries(0) if entry[0] == 24), None)
    if not type_entry:
        raise ValueError("RT_MANIFEST ausente")
    names = entries(type_entry[1] & 0x7FFFFFFF)
    languages = entries(names[0][1] & 0x7FFFFFFF)
    data_entry = root + (languages[0][1] & 0x7FFFFFFF)
    data_rva, data_size, _, _ = struct.unpack_from("<IIII", data, data_entry)
    return data[raw_offset(data_rva) : raw_offset(data_rva) + data_size].decode("utf-8-sig")


version = read("VERSION").strip()
module = read("modules/AutoRunner.Core.psm1")
setup = read("scripts/Setup-Wizard.ps1")
manager = read("scripts/Manager.ps1")
launcher = read("native/launcher.c")
setup_c = read("native/setup.c")
msi_bridge = read("native/msi-bridge.c")
native_builder = read("build/Build-Native.py")
release_builder = read("build/Build-Release.py")
workflow = read(".github/workflows/qa.yml")
all_runtime = "\n".join((module, setup, manager, launcher, setup_c, release_builder))

parts=tuple(int(x) for x in version.split("."))
add("Versão canônica sucessora de 2.3.0", parts >= (2,3,0) and f"$script:AutoRunnerVersion = '{version}'" in module, f"VERSION={version}")
add("Builder lê VERSION", "read_version(root)" in release_builder and 'VERSION = "2.' not in release_builder, "sem versão duplicada no builder")
add("Host gerenciado removido", all(token not in all_runtime for token in ("AutoRunner.Host", "Build-AutoRunnerManagedHost", "csc.exe", "Framework64")), "inicialização não depende de compilação .NET local")
add("Launcher usa PowerShell 5.1 STA", all(token in launcher for token in ("WindowsPowerShell\\\\v1.0\\\\powershell.exe", "-STA", "-File", "scripts\\\\Manager.ps1")), "backend direto e sem host intermediário")
add("Launcher não eleva por manifesto", 'level="asInvoker"' in read("native/launcher.manifest"), "interface abre com token do usuário")
add("Setup exige elevação", 'level="requireAdministrator"' in read("native/setup.manifest"), "instalação administrativa explícita")
add("Setup usa flags exatas", "has_exact_arg" in setup_c and "containsi(original" not in setup_c, "caminhos não ativam switches por substring")
add("Extração valida antes de gravar", "Entrada ZIP escaparia da pasta privada" in setup_c and "ZipFileExtensions]::ExtractToFile" in setup_c and setup_c.find("Entrada ZIP escaparia da pasta privada") < setup_c.find("ZipFileExtensions]::ExtractToFile"), "sem Expand-Archive antes da validação")
add("Entradas ZIP Windows perigosas recusadas", all(token in setup_c for token in ("Nome de dispositivo recusado no ZIP", "Nome Windows inválido no ZIP", "Entrada ZIP duplicada por caixa")), "ADS, nomes reservados e colisões bloqueados")
add("Setup PowerShell em STA", "-NoProfile -STA -NonInteractive" in setup_c, "WinForms em apartment state correto")
add("Manutenção sai da pasta instalada", "AlphaAutoRunner-Maintenance-" in setup and "installerInside" in setup and "'/deferred'" in setup, "reparo e desinstalação não se auto-bloqueiam")
add("Cópia externa revalidada", "originalHash" in setup and "deferredHash" in setup and "Test-SetupInstallerExecutable -Path $deferredSetup" in setup, "estrutura e SHA-256 conferidos")
add("Aplicativo delega externalização ao setup elevado", "Test-AutoRunnerExecutionPathSecurity -ExecutablePath $setup" in module and "-Verb RunAs" in module and "LocalApplicationData" not in module[module.find("function Start-AutoRunnerApplicationMaintenance"):module.find("function Get-AutoRunnerLauncherPath")], "sem cópia privilegiada em pasta gravável pelo usuário")
add("Instaladores concorrentes bloqueados", "Global\\AlphaSoftware.SQLBackupAndFTPAutoRunner.Setup" in setup and "WaitOne(0,$false)" in setup, "mutex global")
add("Processos por caminho e linha de comando", "Get-ApplicationProcessesReferencingPath" in setup and "Win32_Process" in setup and "CommandLine" in setup, "PowerShell oculto também é detectado")
add("Encerramento confirmado", "Processos ainda mantêm a instalação em uso" in setup and "for($round=0;$round -lt 4" in setup, "não prossegue com handle conhecido")
add("Transação em diretórios irmãos", all(token in setup for token in (".stage-", ".rollback-", "[IO.Directory]::Move", "Recover-ApplicationTransactionResidue")), "rename no mesmo volume")
add("Falhas de inspeção não viram junction", "InspectionSucceeded" in setup and "não pôde ser inspecionada" in setup and "HasReparsePoint" in setup, "causas separadas")
add("Inspeção ancestral preserva causa real", "Não foi possível inspecionar componentes do caminho" in module and "catch { return $true }" not in module[module.find("function Test-AutoRunnerPathHasReparsePoint"):module.find("function Get-AutoRunnerTreeInspection")], "falha é recusada sem falso diagnóstico de junction")
add("Resíduos transacionais exigem GUID", "suffix -match '^[A-Fa-f0-9]{32}$'" in setup, "prefixo semelhante não é removido")
add("Rollback restaura por movimento", "Restore-ApplicationDirectoryFromUpgradeBackup" in setup and "Restauração da instalação anterior" in setup, "sem cópia recursiva")
add("Resíduo transacional recuperável", "múltiplos backups de rollback" in setup and "Recuperação automática da instalação anterior" in setup, "fail-closed em ambiguidade")
add("Payload exige inventário", "Test-AutoRunnerPackageChecksums" in setup and "Pacote sem inventário" in setup, "arquivo injetado bloqueado")
add("Setup preservado no staging", "SQLBackupAndFTP-AutoRunner-Setup.exe" in setup and "não pôde ser preservado" in setup, "manutenção futura disponível")
add("Aplicação instalada contém VERSION", "'VERSION'" in setup and "RUNTIME_ROOT_FILES" in release_builder, "estado de versão auditável")
add("Source é artefato de primeira classe", "SOURCE-SHA256SUMS.txt" in release_builder and "-Source.zip" in release_builder and '"tests"' in release_builder, "fonte, build e testes empacotados")
source_dirs_match=re.search(r"SOURCE_DIRS\s*=\s*\((.*?)\)", release_builder, re.S)
add("Downloads históricos fora do Source", source_dirs_match is not None and '"downloads"' not in source_dirs_match.group(1), "sem binários históricos")
add("Build nativo reprodutível e endurecido", all(token in native_builder for token in ("/timestamp:0", "/Brepro", "/dynamicbase", "/nxcompat", "/highentropyva", "/W4", "/WX")), "PE determinístico, ASLR/NX e warnings como erro")
add("Sem buffers sem limite", all(token in launcher + setup_c for token in ("wcopy_s", "wappend_s")) and "static void wcopy(" not in launcher + setup_c, "capacidade explícita")
add("Gerador temporário criptográfico", "BCryptGenRandom" in setup_c and "GetTickCount" not in setup_c, "sem fallback previsível")
add("GUI por usuário é única", "AlphaSoftware.SQLBackupAndFTPAutoRunner.Manager" in manager and "WaitOne(0,$false)" in manager, "mutex interativo")
add("Bridge MSI usa propriedade exata", "has_exact_arg" in msi_bridge and "contains_ci" not in msi_bridge, "PRESERVEDATA não é ativado por substring")
add("Registro ausente não reintroduz auto-bloqueio", "Recuperação para Registro ausente/corrompido" in setup and "$maintenanceRoot" in setup, "Setup preservado do caminho padrão ainda é externalizado")
add("Desinstalação tolera Registro ausente com caminho validado", "destino sem Registro diverge do caminho de manutenção validado" in setup and "$expected=Assert-SafeApplicationPath $InstallDir" in setup, "fallback não é bloqueado por comparação com string vazia")
add("CI cobre Windows", "windows-2022" in workflow and "Invoke-QA.ps1" in workflow and ("V230-Regression-QA.py" in workflow or "V235-Regression-QA.py" in workflow), "AST, integração, GUI e regressão sucessora no Windows")
add("CI cobre pacotes", "Build-Release.py" in workflow and "Setup-Installer-QA.py" in workflow and "Source-Package-QA.py" in workflow, "artefatos são testados após build")

for rel, expected_level in (("SQLBackupAndFTP-AutoRunner.exe", "asInvoker"), ("native/setup-base.exe", "requireAdministrator")):
    try:
        info = pe_info(ROOT / rel)
        manifest = manifest_from_pe(ROOT / rel)
        ET.fromstring(manifest)
        ok = info["machine"] == 0x8664 and info["magic"] == 0x20B and info["subsystem"] == 2 and f'level="{expected_level}"' in manifest
        add(f"PE x64 GUI e manifesto: {rel}", ok, json.dumps(info, ensure_ascii=False))
    except Exception as exc:
        add(f"PE x64 GUI e manifesto: {rel}", False, str(exc))

# Detect current-version drift in executable sources, not historical release notes.
active_files = [
    ROOT / "modules/AutoRunner.Core.psm1",
    ROOT / "scripts/Setup-Wizard.ps1",
    ROOT / "scripts/Manager.ps1",
    ROOT / "build/Build-Release.py",
]
drift: list[str] = []
for path in active_files:
    text = path.read_text(encoding="utf-8-sig")
    for match in re.finditer(r"\b2\.2\.[0-9]+\b", text):
        drift.append(f"{path.relative_to(ROOT)}:{text.count(chr(10), 0, match.start()) + 1}:{match.group(0)}")
add("Sem versão antiga no código ativo", not drift, "; ".join(drift[:10]) or "nenhuma")

report = {
    "suite": "V230-Regression-QA",
    "version": version,
    "passed": sum(bool(item["passed"]) for item in RESULTS),
    "failed": sum(not bool(item["passed"]) for item in RESULTS),
    "results": RESULTS,
}
output = ROOT / "test-results"
output.mkdir(exist_ok=True)
(output / "V230-Regression-QA.json").write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"passed": report["passed"], "failed": report["failed"]}, ensure_ascii=False))
sys.exit(1 if report["failed"] else 0)
