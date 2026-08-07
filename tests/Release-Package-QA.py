#!/usr/bin/env python3
"""Validação adversarial de um ZIP de release do AutoRunner.

Verifica estrutura, traversal, duplicidades, links, SHA256SUMS interno e hash externo.
Não autentica o publicador e não substitui assinatura digital.
"""
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


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest().upper()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest().upper()


def fail(results: list[dict[str, object]], name: str, detail: str) -> None:
    results.append({"name": name, "status": "FAIL", "detail": detail})
    print(f"[FAIL] {name}: {detail}")


def passed(results: list[dict[str, object]], name: str, detail: str) -> None:
    results.append({"name": name, "status": "PASS", "detail": detail})
    print(f"[PASS] {name}: {detail}")


def main() -> int:
    if len(sys.argv) < 2:
        print("Uso: Release-Package-QA.py <release.zip> [hash-externo.txt]", file=sys.stderr)
        return 2
    zip_path = Path(sys.argv[1]).resolve()
    external_path = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    results: list[dict[str, object]] = []
    issues: list[str] = []

    if not zip_path.is_file():
        print(f"ZIP ausente: {zip_path}", file=sys.stderr)
        return 2

    actual_zip_hash = sha256_file(zip_path)
    if external_path:
        if not external_path.is_file():
            fail(results, "Hash externo", f"arquivo ausente: {external_path}")
        else:
            text = external_path.read_text(encoding="utf-8-sig", errors="replace")
            m = re.search(r"(?i)\b([0-9a-f]{64})\b", text)
            expected = m.group(1).upper() if m else ""
            if expected == actual_zip_hash:
                passed(results, "Hash externo", actual_zip_hash)
            else:
                fail(results, "Hash externo", f"esperado={expected or '(inválido)'} atual={actual_zip_hash}")
    else:
        passed(results, "Hash externo", "não fornecido; validação de autenticidade permanece pendente")

    with zipfile.ZipFile(zip_path, "r") as zf:
        infos = zf.infolist()
        names = [i.filename for i in infos]
        folded: dict[str, list[str]] = {}
        roots: set[str] = set()
        files: dict[str, bytes] = {}

        for info in infos:
            raw = info.filename.replace("\\", "/")
            p = PurePosixPath(raw)
            if info.is_dir() or unsafe_windows_path(raw):
                issues.append(f"caminho Windows inseguro: {raw}")
            if p.parts:
                roots.add(p.parts[0])
            folded.setdefault(raw.rstrip("/").casefold(), []).append(raw)
            mode = (info.external_attr >> 16) & 0xFFFF
            if stat.S_ISLNK(mode):
                issues.append(f"link simbólico: {raw}")
            if not info.is_dir():
                files[raw] = zf.read(info)

        duplicates = [v for v in folded.values() if len(v) > 1]
        if duplicates:
            issues.append("duplicidades case-insensitive: " + "; ".join(", ".join(v) for v in duplicates))
        if len(roots) != 1:
            issues.append(f"esperada uma única raiz; encontradas: {sorted(roots)}")

        if issues:
            fail(results, "Estrutura segura do ZIP", "; ".join(issues[:20]))
        else:
            passed(results, "Estrutura segura do ZIP", f"{len(files)} arquivo(s), raiz {next(iter(roots))}")

        root = next(iter(roots)) if len(roots) == 1 else ""
        checksum_name = f"{root}/SHA256SUMS.txt" if root else "SHA256SUMS.txt"
        if checksum_name not in files:
            fail(results, "SHA256SUMS interno", f"ausente: {checksum_name}")
        else:
            declarations: dict[str, str] = {}
            malformed: list[str] = []
            for line_no, line in enumerate(files[checksum_name].decode("utf-8-sig", errors="replace").splitlines(), 1):
                if not line.strip():
                    continue
                m = re.match(r"^([0-9A-Fa-f]{64})\s+\*?(.+?)\s*$", line)
                if not m:
                    malformed.append(f"linha {line_no}")
                    continue
                rel = m.group(2).replace("\\", "/")
                if unsafe_windows_path(rel):
                    malformed.append(f"linha {line_no}: path inseguro")
                    continue
                key = rel.casefold()
                if key in declarations:
                    malformed.append(f"linha {line_no}: duplicado {rel}")
                    continue
                declarations[key] = m.group(1).upper()

            actual_rel = {
                name[len(root) + 1 :].casefold(): data
                for name, data in files.items()
                if name != checksum_name and (not root or name.startswith(root + "/"))
            }
            missing = sorted(set(declarations) - set(actual_rel))
            injected = sorted(set(actual_rel) - set(declarations))
            mismatches = sorted(
                rel for rel, data in actual_rel.items()
                if rel in declarations and sha256_bytes(data) != declarations[rel]
            )
            if malformed or missing or injected or mismatches:
                detail = []
                if malformed: detail.append("malformado=" + ", ".join(malformed[:10]))
                if missing: detail.append("ausentes=" + ", ".join(missing[:10]))
                if injected: detail.append("não declarados=" + ", ".join(injected[:10]))
                if mismatches: detail.append("hash divergente=" + ", ".join(mismatches[:10]))
                fail(results, "SHA256SUMS interno", "; ".join(detail))
            else:
                passed(results, "SHA256SUMS interno", f"{len(declarations)} arquivo(s) declarados e conferidos")

        required = {
            "sqlbackupandftp-autorunner.exe",
            "readme.md",
            "modules/autorunner.core.psm1",
            "scripts/setup-wizard.ps1",
            "scripts/manager.ps1",
            "scripts/install-sqlbackupandftp-auto.ps1",
            "scripts/run-sqlbackupandftpjob.ps1",
            "scripts/uninstall-sqlbackupandftp-auto.ps1",
        }
        rels = {
            (name[len(root) + 1 :] if root and name.startswith(root + "/") else name).casefold()
            for name in files
        }
        missing_required = sorted(required - rels)
        if missing_required:
            fail(results, "Runtime mínimo", ", ".join(missing_required))
        else:
            passed(results, "Runtime mínimo", "arquivos críticos presentes")

    out = zip_path.with_suffix(zip_path.suffix + ".qa.json")
    report = {
        "suite": "release-package-qa",
        "zip": str(zip_path),
        "sha256": actual_zip_hash,
        "results": results,
        "pass": sum(r["status"] == "PASS" for r in results),
        "fail": sum(r["status"] == "FAIL" for r in results),
        "limitations": [
            "Checksum interno não autentica o publicador.",
            "Não executa PowerShell, Windows, SQLBackupAndFTP ou backup real.",
        ],
    }
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"Relatório: {out}")
    return 1 if report["fail"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
