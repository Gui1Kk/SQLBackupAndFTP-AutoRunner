#!/usr/bin/env python3
"""Validate the deterministic Source ZIP and its internal inventory."""
from __future__ import annotations

import hashlib
import json
import re
import stat
import sys
import zipfile
from pathlib import Path, PurePosixPath

WINDOWS_RESERVED = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", re.I)
WINDOWS_INVALID = set('<>:"|?*')

def unsafe_windows_path(name: str) -> bool:
    normalized = name.replace("\\", "/")
    pure = PurePosixPath(normalized)
    if pure.is_absolute() or not pure.parts or re.match(r"^[A-Za-z]:", normalized):
        return True
    if any(part in ("", ".", "..") for part in pure.parts):
        return True
    for part in pure.parts:
        if part.endswith((".", " ")) or any(ch in WINDOWS_INVALID for ch in part):
            return True
        if WINDOWS_RESERVED.fullmatch(part.rsplit(".", 1)[0]):
            return True
    return False


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: Source-Package-QA.py <source.zip> [hash externo]", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    hash_path = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    failures: list[str] = []
    results: list[dict[str, object]] = []

    def check(name: str, ok: bool, detail: str) -> None:
        results.append({"name": name, "passed": ok, "detail": detail})
        print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")
        if not ok:
            failures.append(name + ": " + detail)

    raw = path.read_bytes()
    actual_hash = digest(raw)
    if hash_path:
        text = hash_path.read_text(encoding="utf-8-sig", errors="replace")
        match = re.search(r"(?i)\b([0-9a-f]{64})\b", text)
        check("Hash externo", bool(match and match.group(1).upper() == actual_hash), actual_hash)

    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        roots = {PurePosixPath(info.filename).parts[0] for info in infos if PurePosixPath(info.filename).parts}
        check("Raiz única", len(roots) == 1, ", ".join(sorted(roots)))
        root = next(iter(roots)) if len(roots) == 1 else ""
        files: dict[str, bytes] = {}
        seen: set[str] = set()
        structure_issues: list[str] = []
        for info in infos:
            name = info.filename.replace("\\", "/")
            if info.is_dir() or unsafe_windows_path(name):
                structure_issues.append(name)
            key = name.rstrip("/").casefold()
            if key in seen:
                structure_issues.append("duplicado:" + name)
            seen.add(key)
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                structure_issues.append("link:" + name)
            if not info.is_dir():
                files[name] = archive.read(info)
        check("Estrutura segura", not structure_issues, "; ".join(structure_issues[:10]) or f"{len(files)} arquivos")

        inventory_name = f"{root}/SOURCE-SHA256SUMS.txt"
        check("Inventário interno", inventory_name in files, inventory_name)
        declarations: dict[str, str] = {}
        if inventory_name in files:
            for line in files[inventory_name].decode("utf-8-sig").splitlines():
                if not line.strip():
                    continue
                match = re.match(r"^([0-9A-Fa-f]{64})\s+\*?(.+)$", line)
                if not match:
                    failures.append("linha de inventário inválida: " + line)
                    continue
                rel = match.group(2).replace("\\", "/")
                if unsafe_windows_path(rel):
                    failures.append("caminho de inventário inseguro: " + rel)
                    continue
                declarations[rel.casefold()] = match.group(1).upper()
            actual = {
                name[len(root) + 1 :].casefold(): data
                for name, data in files.items()
                if name != inventory_name and name.startswith(root + "/")
            }
            missing = set(declarations) - set(actual)
            injected = set(actual) - set(declarations)
            mismatched = {rel for rel, data in actual.items() if rel in declarations and digest(data) != declarations[rel]}
            check("Completude do inventário", not (missing or injected or mismatched), f"missing={len(missing)} injected={len(injected)} mismatch={len(mismatched)}")

        rels = {name[len(root) + 1 :].casefold() for name in files if root and name.startswith(root + "/")}
        required = {
            "version",
            "release_channel",
            "readme.md",
            "building.md",
            "build/build-native.py",
            "build/build-release.py",
            "native/launcher.c",
            "native/setup.c",
            "modules/autorunner.core.psm1",
            "scripts/setup-wizard.ps1",
            "scripts/manager.ps1",
            "scripts/invoke-qa.ps1",
            "tests/v235-regression-qa.py",
            "tests/upgrade-transaction-model.py",
        }
        check("Fonte completa", required <= rels, ", ".join(sorted(required - rels)) or "arquivos críticos presentes")
        forbidden = [rel for rel in rels if rel.startswith(("downloads/", "dist/", "test-results/", ".git/")) or rel.endswith((".pfx", ".p12", ".lib", ".obj", ".pdb"))]
        check("Sem artefatos históricos ou segredos", not forbidden, ", ".join(forbidden[:10]) or "limpo")

    report = {"suite": "source-package-qa", "source": str(path), "sha256": actual_hash, "failed": failures, "results": results}
    out = path.with_suffix(path.suffix + ".qa.json")
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print("Relatório:", out)
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
