#!/usr/bin/env python3
"""Build deterministic Setup, Portable and Source artifacts from one tree.

The release version is read from VERSION. Runtime packages contain only the
allow-listed production payload. The source ZIP contains the auditable project
sources and build/test tooling, never historical downloads or generated output.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

MAGIC = b"ALPHASETUPZIP01!"
FIXED_DT = (2026, 1, 1, 0, 0, 0)
RUNTIME_ROOT_FILES = (
    "SQLBackupAndFTP-AutoRunner.exe",
    "README.md",
    "CHANGELOG.md",
    "VERSION",
    "RELEASE_CHANNEL",
    "LICENSE",
    "SECURITY.md",
    "SUPPORT.md",
)
RUNTIME_FILES = (
    "assets/AutoRunner.ico",
    "assets/AutoRunner.png",
    "modules/AutoRunner.Core.psm1",
    "scripts/Setup-Wizard.ps1",
    "scripts/Install-SQLBackupAndFTP-Auto.ps1",
    "scripts/Uninstall-SQLBackupAndFTP-Auto.ps1",
    "scripts/Manager.ps1",
    "scripts/Run-SQLBackupAndFTPJob.ps1",
    "scripts/Export-Diagnostics.ps1",
    "scripts/Update-AutoRunner.ps1",
    "scripts/Check-Updates.ps1",
    "agent/remote-control/AutoRunner.RemoteAgent.ps1",
    "agent/remote-control/AutoRunner.RemoteAgent.psm1",
    "agent/remote-control/README.md",
)
SOURCE_ROOT_FILES = (
    ".gitattributes",
    ".gitignore",
    ".dockerignore",
    "BUILDING.md",
    "CHANGELOG.md",
    "LICENSE",
    "README.md",
    "SECURITY.md",
    "SUPPORT.md",
    "VERSION",
    "RELEASE_CHANNEL",
    "package.json",
    "package-lock.json",
    ".npmrc",
)
SOURCE_DIRS = (".github", "agent", "apps", "assets", "build", "contracts", "deploy", "docs", "modules", "native", "scripts", "services", "tests")
SOURCE_EXCLUDED_NAMES = {
    "SQLBackupAndFTP-AutoRunner.exe",
    "setup-base.exe",
    "SQLBackupAndFTP-AutoRunner-MsiBridge.exe",
}
SOURCE_EXCLUDED_SUFFIXES = {".lib", ".obj", ".pdb", ".pyc", ".log", ".tmp", ".bak"}


def read_version(root: Path) -> str:
    value = (root / "VERSION").read_text(encoding="utf-8-sig").strip()
    parts = value.split(".")
    if len(parts) != 3 or any(not part.isdigit() for part in parts):
        raise ValueError(f"VERSION inválida: {value!r}")
    return value


def read_release_channel(root: Path) -> str:
    path = root / "RELEASE_CHANNEL"
    value = path.read_text(encoding="utf-8-sig").strip() if path.exists() else "Stable"
    if not re.fullmatch(r"(?:Stable|RC|Beta|Alpha)", value, re.I):
        raise ValueError(f"RELEASE_CHANNEL inválido: {value!r}")
    canonical = {"stable":"Stable","rc":"RC","beta":"Beta","alpha":"Alpha"}
    return canonical[value.casefold()]


def release_label(version: str, channel: str) -> str:
    return version if channel == "Stable" else f"{version}-{channel}"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest().upper()


WINDOWS_RESERVED = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", re.I)
WINDOWS_INVALID = set('<>:"|?*')

def validate_relative(name: str) -> str:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or not path.parts or re.match(r"^[A-Za-z]:", normalized) or ".." in path.parts:
        raise ValueError(f"Caminho relativo inseguro: {name!r}")
    if any(part in ("", ".") for part in path.parts):
        raise ValueError(f"Caminho relativo inválido: {name!r}")
    for part in path.parts:
        if part.endswith((".", " ")) or any(ch in WINDOWS_INVALID for ch in part):
            raise ValueError(f"Nome incompatível com Windows: {name!r}")
        if WINDOWS_RESERVED.fullmatch(part.rsplit(".", 1)[0]):
            raise ValueError(f"Nome de dispositivo Windows recusado: {name!r}")
    return path.as_posix()


def ensure_unique(entries: list[tuple[str, Path]]) -> list[tuple[str, Path]]:
    seen: set[str] = set()
    result: list[tuple[str, Path]] = []
    for rel, source in sorted(entries, key=lambda item: item[0].casefold()):
        rel = validate_relative(rel)
        key = rel.casefold()
        if key in seen:
            raise ValueError(f"Caminho duplicado por caixa: {rel}")
        seen.add(key)
        if source.is_symlink():
            raise ValueError(f"Link simbólico recusado: {source}")
        if not source.is_file():
            raise FileNotFoundError(source)
        result.append((rel, source))
    return result


def collect_runtime(root: Path) -> list[tuple[str, Path]]:
    entries: list[tuple[str, Path]] = []
    for rel in (*RUNTIME_ROOT_FILES, *RUNTIME_FILES):
        entries.append((rel, root / rel))
    for source in sorted((root / "docs").glob("*.md"), key=lambda path: path.name.casefold()):
        if source.is_file() and not source.is_symlink():
            entries.append((source.relative_to(root).as_posix(), source))
    return ensure_unique(entries)


def collect_source(root: Path) -> list[tuple[str, Path]]:
    entries: list[tuple[str, Path]] = []
    for rel in SOURCE_ROOT_FILES:
        path = root / rel
        if path.is_file():
            entries.append((rel, path))
    for directory in SOURCE_DIRS:
        base = root / directory
        if not base.is_dir():
            raise FileNotFoundError(f"Diretório-fonte obrigatório ausente: {base}")
        for source in sorted(base.rglob("*"), key=lambda path: path.as_posix().casefold()):
            if not source.is_file() or source.is_symlink():
                continue
            rel = source.relative_to(root).as_posix()
            if source.name in SOURCE_EXCLUDED_NAMES or source.suffix.casefold() in SOURCE_EXCLUDED_SUFFIXES:
                continue
            if any(part in {"__pycache__", "test-results", "qa-output", "dist"} for part in source.parts):
                continue
            entries.append((rel, source))
    return ensure_unique(entries)


def write_checksum_inventory(stage: Path, file_name: str) -> dict[str, str]:
    inventory: dict[str, str] = {}
    for source in sorted((p for p in stage.rglob("*") if p.is_file()), key=lambda p: p.relative_to(stage).as_posix().casefold()):
        rel = source.relative_to(stage).as_posix()
        if rel.casefold() == file_name.casefold():
            continue
        inventory[rel] = sha256(source)
    lines = [f"{inventory[rel]} *{rel}" for rel in sorted(inventory, key=str.casefold)]
    (stage / file_name).write_text("\r\n".join(lines) + "\r\n", encoding="utf-8", newline="")
    return inventory


def stage_entries(entries: list[tuple[str, Path]], stage: Path, checksum_name: str) -> dict[str, str]:
    for rel, source in entries:
        target = stage / Path(rel)
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
    return write_checksum_inventory(stage, checksum_name)


def make_zip(source: Path, output: Path, prefix: str = "") -> None:
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_suffix(output.suffix + ".tmp")
    temporary.unlink(missing_ok=True)
    files = sorted((path for path in source.rglob("*") if path.is_file()), key=lambda path: path.relative_to(source).as_posix().casefold())
    with zipfile.ZipFile(temporary, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9, strict_timestamps=True) as archive:
        for path in files:
            rel = path.relative_to(source).as_posix()
            member = validate_relative(f"{prefix}/{rel}" if prefix else rel)
            info = zipfile.ZipInfo(member, FIXED_DT)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 0
            info.external_attr = 0o100644 << 16
            info.flag_bits |= 0x800
            archive.writestr(info, path.read_bytes(), compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    os.replace(temporary, output)


def verify_inventory_zip(zip_path: Path, checksum_name: str, prefix: str = "") -> dict[str, object]:
    issues: list[str] = []
    seen: set[str] = set()
    with zipfile.ZipFile(zip_path) as archive:
        infos = archive.infolist()
        files = {info.filename: archive.read(info) for info in infos if not info.is_dir()}
        for info in infos:
            try:
                rel = validate_relative(info.filename)
            except ValueError as exc:
                issues.append(str(exc))
                continue
            key = rel.casefold()
            if key in seen:
                issues.append(f"Caminho ZIP duplicado: {rel}")
            seen.add(key)
        root = prefix.strip("/")
        inventory_member = f"{root}/{checksum_name}" if root else checksum_name
        if inventory_member not in files:
            issues.append(f"Inventário ausente: {inventory_member}")
            return {"valid": False, "issues": issues, "entries": len(infos)}
        declared: dict[str, str] = {}
        for raw in files[inventory_member].decode("utf-8-sig").splitlines():
            if not raw.strip():
                continue
            try:
                expected, rel = raw.split(maxsplit=1)
                rel = validate_relative(rel.lstrip("*"))
                if len(expected) != 64 or any(ch not in "0123456789ABCDEFabcdef" for ch in expected):
                    raise ValueError
            except Exception:
                issues.append(f"Linha inválida no inventário: {raw}")
                continue
            key = rel.casefold()
            if key in declared:
                issues.append(f"Declaração duplicada: {rel}")
            declared[key] = expected.upper()
            member = f"{root}/{rel}" if root else rel
            if member not in files:
                issues.append(f"Arquivo declarado ausente: {member}")
            elif hashlib.sha256(files[member]).hexdigest().upper() != expected.upper():
                issues.append(f"Hash divergente: {member}")
        actual: set[str] = set()
        for member in files:
            if member.casefold() == inventory_member.casefold():
                continue
            if root:
                if not member.startswith(root + "/"):
                    issues.append(f"Arquivo fora da raiz: {member}")
                    continue
                rel = member[len(root) + 1 :]
            else:
                rel = member
            actual.add(rel.casefold())
        injected = sorted(actual - set(declared))
        if injected:
            issues.extend(f"Arquivo não declarado: {name}" for name in injected)
    return {"valid": not issues, "issues": issues, "entries": len(infos), "declared": len(declared)}


def add_external_hash(artifact: Path) -> tuple[str, Path]:
    digest = sha256(artifact)
    hash_path = artifact.with_suffix(artifact.suffix + ".sha256.txt")
    hash_path.write_text(f"{digest} *{artifact.name}\r\n", encoding="utf-8", newline="")
    return digest, hash_path


def build(root: Path, output: Path) -> dict[str, object]:
    root = root.resolve()
    output = output.resolve()
    version = read_version(root)
    channel = read_release_channel(root)
    label = release_label(version, channel)
    setup_base = root / "native" / "setup-base.exe"
    launcher = root / "SQLBackupAndFTP-AutoRunner.exe"
    for required in (setup_base, launcher):
        if not required.is_file() or required.read_bytes()[:2] != b"MZ":
            raise FileNotFoundError(f"Binário nativo ausente ou inválido: {required}")
    output.mkdir(parents=True, exist_ok=True)
    manifest: dict[str, object] = {
        "product": "SQLBackupAndFTP AutoRunner",
        "version": version,
        "releaseChannel": channel,
        "displayVersion": version if channel == "Stable" else f"{version} {channel}",
        "tag": f"v{label}",
        "sourceCommit": os.environ.get("GITHUB_SHA", "local-uncommitted"),
        "files": {},
    }
    with tempfile.TemporaryDirectory(prefix="AlphaAutoRunnerBuild-") as temporary_name:
        temporary = Path(temporary_name)
        runtime_stage = temporary / "runtime"
        runtime_stage.mkdir()
        runtime_inventory = stage_entries(collect_runtime(root), runtime_stage, "SHA256SUMS.txt")
        payload_zip = temporary / "payload.zip"
        make_zip(runtime_stage, payload_zip)
        payload_check = verify_inventory_zip(payload_zip, "SHA256SUMS.txt")
        if not payload_check["valid"]:
            raise RuntimeError(f"Payload inválido: {payload_check['issues']}")

        setup = output / f"SQLBackupAndFTP-AutoRunner-Setup-v{label}.exe"
        setup_tmp = setup.with_suffix(setup.suffix + ".tmp")
        with setup_tmp.open("wb") as stream:
            stream.write(setup_base.read_bytes())
            payload = payload_zip.read_bytes()
            stream.write(payload)
            stream.write(MAGIC)
            stream.write(struct.pack("<Q", len(payload)))
        os.replace(setup_tmp, setup)

        portable_root_name = f"SQLBackupAndFTP-AutoRunner-v{label}"
        portable_root = temporary / portable_root_name
        shutil.copytree(runtime_stage, portable_root)
        portable = output / f"SQLBackupAndFTP-AutoRunner-v{label}-Portable.zip"
        make_zip(portable_root, portable, portable_root_name)
        portable_check = verify_inventory_zip(portable, "SHA256SUMS.txt", portable_root_name)
        if not portable_check["valid"]:
            raise RuntimeError(f"Portable inválido: {portable_check['issues']}")

        source_root_name = f"SQLBackupAndFTP-AutoRunner-v{label}-Source"
        source_root = temporary / source_root_name
        source_root.mkdir()
        source_inventory = stage_entries(collect_source(root), source_root, "SOURCE-SHA256SUMS.txt")
        source = output / f"SQLBackupAndFTP-AutoRunner-v{label}-Source.zip"
        make_zip(source_root, source, source_root_name)
        source_check = verify_inventory_zip(source, "SOURCE-SHA256SUMS.txt", source_root_name)
        if not source_check["valid"]:
            raise RuntimeError(f"Source inválido: {source_check['issues']}")

        for artifact, kind in ((setup, "setup"), (portable, "portable"), (source, "source")):
            digest, hash_file = add_external_hash(artifact)
            manifest["files"][artifact.name] = {
                "kind": kind,
                "sha256": digest,
                "size": artifact.stat().st_size,
                "hashFile": hash_file.name,
            }
        manifest["payload"] = {
            "files": len(runtime_inventory),
            "setupBaseSha256": sha256(setup_base),
            "launcherSha256": sha256(launcher),
        }
        manifest["source"] = {"files": len(source_inventory)}

    manifest_path = output / "RELEASE-MANIFEST.json"
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    inventory_lines = [f"{entry['sha256']} *{name}" for name, entry in sorted(manifest["files"].items(), key=lambda item: item[0].casefold())]
    (output / "SHA256SUMS.txt").write_text("\r\n".join(inventory_lines) + "\r\n", encoding="utf-8", newline="")
    return manifest


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--output", type=Path, default=Path("dist"))
    args = parser.parse_args()
    root = args.root.resolve()
    output = args.output if args.output.is_absolute() else root / args.output
    manifest = build(root, output)
    print(json.dumps(manifest, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
