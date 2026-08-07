#!/usr/bin/env python3
"""Structural and adversarial validation for the self-extracting Setup EXE."""
from __future__ import annotations

import hashlib
import io
import json
import re
import struct
import sys
import tempfile
import zipfile
from pathlib import Path, PurePosixPath

WINDOWS_RESERVED = re.compile(r"^(?:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$", re.I)
WINDOWS_INVALID = set('<>:"|?*')

def unsafe_windows_member(name: str) -> bool:
    normalized = name.replace("\\", "/")
    path = PurePosixPath(normalized)
    if path.is_absolute() or normalized.startswith("/") or re.match(r"^[A-Za-z]:", normalized):
        return True
    if not path.parts or ".." in path.parts or any(part in ("", ".") for part in path.parts):
        return True
    for part in path.parts:
        if part.endswith((".", " ")) or any(ch in WINDOWS_INVALID for ch in part):
            return True
        base = part.rsplit(".", 1)[0]
        if WINDOWS_RESERVED.fullmatch(base):
            return True
    return False

MAGIC = b"ALPHASETUPZIP01!"
RESULTS: list[dict[str, object]] = []


def add(name: str, ok: bool, detail: str) -> None:
    RESULTS.append({"name": name, "passed": bool(ok), "detail": detail})
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {detail}")


def parse_bytes(data: bytes) -> tuple[bytes, bytes]:
    if len(data) < 24 or data[-24:-8] != MAGIC:
        raise ValueError("trailer magic inválido")
    size = struct.unpack("<Q", data[-8:])[0]
    if not 0 < size <= len(data) - 24:
        raise ValueError("tamanho inválido")
    start = len(data) - 24 - size
    if start < 2 or data[:2] != b"MZ":
        raise ValueError("bootstrap PE ausente")
    payload = data[start : start + size]
    if len(payload) != size:
        raise ValueError("payload truncado")
    return data[:start], payload


def parse(path: Path) -> tuple[bytes, bytes]:
    return parse_bytes(path.read_bytes())


def read_entries(payload: bytes) -> list[tuple[str, bytes]]:
    entries: list[tuple[str, bytes]] = []
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        for info in archive.infolist():
            if not info.is_dir():
                entries.append((info.filename, archive.read(info)))
    return entries


def build_payload(entries: list[tuple[str, bytes]]) -> bytes:
    target = io.BytesIO()
    with zipfile.ZipFile(target, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name, content in entries:
            archive.writestr(name, content)
    return target.getvalue()


def validate_payload(payload: bytes) -> list[str]:
    issues: list[str] = []
    seen: set[str] = set()
    declarations: dict[str, tuple[str, str]] = {}
    files: dict[str, bytes] = {}
    try:
        with zipfile.ZipFile(io.BytesIO(payload)) as archive:
            bad_member = archive.testzip()
            if bad_member:
                issues.append(f"CRC inválido:{bad_member}")
            for info in archive.infolist():
                name = info.filename.replace("\\", "/")
                if info.is_dir() or unsafe_windows_member(name):
                    issues.append("path:" + name)
                key = name.casefold()
                if key in seen:
                    issues.append("duplicate:" + name)
                seen.add(key)
                if not info.is_dir():
                    files[name] = archive.read(info)
    except Exception as exc:
        return [f"ZIP inválido:{type(exc).__name__}:{exc}"]

    if "SHA256SUMS.txt" not in files:
        return ["checksum missing", *issues]

    try:
        checksum_text = files["SHA256SUMS.txt"].decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        return [f"checksum encoding:{exc}", *issues]

    for line in checksum_text.splitlines():
        if not line.strip():
            continue
        try:
            expected, relative = line.split(maxsplit=1)
            relative = relative.lstrip("*").replace("\\", "/")
            if (
                len(expected) != 64
                or any(ch not in "0123456789abcdefABCDEF" for ch in expected)
                or unsafe_windows_member(relative)
                or relative == "SHA256SUMS.txt"
            ):
                raise ValueError
        except Exception:
            issues.append("bad checksum line")
            continue
        key = relative.casefold()
        if key in declarations:
            issues.append("duplicate checksum:" + relative)
        declarations[key] = (expected.upper(), relative)
        if relative not in files:
            issues.append("missing:" + relative)
        elif hashlib.sha256(files[relative]).hexdigest().upper() != expected.upper():
            issues.append("mismatch:" + relative)

    for name in files:
        if name == "SHA256SUMS.txt":
            continue
        if name.casefold() not in declarations:
            issues.append("undeclared:" + name)
    return issues


def rejected_payload(payload: bytes) -> bool:
    try:
        return bool(validate_payload(payload))
    except Exception:
        return True


def main() -> int:
    if len(sys.argv) != 2:
        print("Uso: Setup-Installer-QA.py <setup.exe>", file=sys.stderr)
        return 2
    path = Path(sys.argv[1]).resolve()
    if not path.is_file():
        print(f"Instalador não encontrado: {path}", file=sys.stderr)
        return 2

    data = path.read_bytes()
    try:
        base, payload = parse_bytes(data)
        add("Trailer e payload", True, f"bootstrap={len(base)} payload={len(payload)}")
    except Exception as exc:
        add("Trailer e payload", False, str(exc))
        base = payload = b""

    if payload:
        add("Bootstrap PE", base.startswith(b"MZ") and b"PE\0\0" in base, "PE detectado" if base.startswith(b"MZ") else "cabeçalho ausente")
        # The linker may reorder UTF-16 string literals, so their byte offsets in the
        # PE do not represent execution order. Verify both markers exist in the PE,
        # then verify construction order in the reviewed bootstrap source.
        hash_marker = "Get-FileHash".encode("utf-16le")
        wizard_marker = "scripts\\Setup-Wizard.ps1".encode("utf-16le")
        undeclared_marker = "Arquivo não declarado no checksum".encode("utf-16le")
        source_path = Path(__file__).resolve().parents[1] / "native" / "setup.c"
        source = source_path.read_text(encoding="utf-8") if source_path.is_file() else ""
        validate_pos = source.find("Entrada ZIP escaparia da pasta privada")
        extract_pos = source.find("ZipFileExtensions]::ExtractToFile")
        remove_pos = source.find("Remove-Item -LiteralPath $env:ALPHA_PAYLOAD_ZIP -Force;")
        hash_source_pos = source.find("Get-FileHash")
        inventory_pos = source.find("Arquivo não declarado no checksum")
        wizard_source_pos = source.find(r"scripts\\Setup-Wizard.ps1")
        ordered = (
            min(validate_pos, extract_pos, remove_pos, hash_source_pos, inventory_pos, wizard_source_pos) >= 0
            and validate_pos < extract_pos < remove_pos < hash_source_pos < inventory_pos < wizard_source_pos
        )
        embedded = all(marker in base for marker in (hash_marker, wizard_marker, undeclared_marker))
        add(
            "Bootstrap valida hashes antes de executar scripts",
            embedded and ordered,
            f"embedded={embedded} source_order={ordered}",
        )
        issues = validate_payload(payload)
        add("Integridade interna", not issues, "sem divergências" if not issues else "; ".join(issues[:20]))
        entries = read_entries(payload)
        names = {name for name, _content in entries}
        required = {
            "SQLBackupAndFTP-AutoRunner.exe",
            "scripts/Setup-Wizard.ps1",
            "scripts/Manager.ps1",
            "modules/AutoRunner.Core.psm1",
            "SHA256SUMS.txt",
        }
        add("Runtime mínimo", required <= names, ", ".join(sorted(required - names)) or "presente")
        add(
            "Sem conteúdo de desenvolvimento",
            not any(name.startswith(("tests/", "test-results/", "native/", "build/", ".git/")) for name in names),
            "payload de produção",
        )

        try:
            parse_bytes(data[:-24] + b"BROKENMAGIC0000!" + data[-8:])
            ok = False
        except Exception:
            ok = True
        add("Ataque: magic adulterado", ok, "rejeitado" if ok else "aceito")

        try:
            parse_bytes(data[:-8] + struct.pack("<Q", len(data) * 2))
            ok = False
        except Exception:
            ok = True
        add("Ataque: tamanho adulterado", ok, "rejeitado" if ok else "aceito")

        try:
            parse_bytes(data[:-1])
            ok = False
        except Exception:
            ok = True
        add("Ataque: instalador truncado", ok, "rejeitado" if ok else "aceito")

        corrupted = bytearray(payload)
        corrupted[len(corrupted) // 2] ^= 0x5A
        add("Ataque: payload binário alterado", rejected_payload(bytes(corrupted)), "rejeitado")

        add(
            "Ataque: arquivo não declarado",
            rejected_payload(build_payload([*entries, ("injetado.txt", b"X")])),
            "rejeitado",
        )
        add(
            "Ataque: path traversal",
            rejected_payload(build_payload([*entries, ("../escape.txt", b"X")])),
            "rejeitado",
        )
        add(
            "Ataque: alternate data stream",
            rejected_payload(build_payload([*entries, ("README.md:payload", b"X")])),
            "rejeitado",
        )
        add(
            "Ataque: nome de dispositivo Windows",
            rejected_payload(build_payload([*entries, ("CON.txt", b"X")])),
            "rejeitado",
        )
        add(
            "Ataque: colisão por ponto final",
            rejected_payload(build_payload([*entries, ("README.md.", b"X")])),
            "rejeitado",
        )
        duplicate_name = next((name for name, _ in entries if name.casefold() == "readme.md"), "README.md")
        duplicate_variant = duplicate_name.swapcase()
        add(
            "Ataque: duplicidade por caixa",
            rejected_payload(build_payload([*entries, (duplicate_variant, b"duplicado")])),
            "rejeitado",
        )
        without_checksum = [(name, content) for name, content in entries if name != "SHA256SUMS.txt"]
        add("Ataque: checksum ausente", rejected_payload(build_payload(without_checksum)), "rejeitado")
        altered_entries = [
            (name, content + b"ALTERADO" if name == "README.md" else content)
            for name, content in entries
        ]
        add("Ataque: conteúdo com hash antigo", rejected_payload(build_payload(altered_entries)), "rejeitado")
        bad_checksum = [
            (name, b"0" * 64 + b" *README.md\r\n" if name == "SHA256SUMS.txt" else content)
            for name, content in entries
        ]
        add("Ataque: manifesto de hashes forjado", rejected_payload(build_payload(bad_checksum)), "rejeitado")

    output = path.with_suffix(path.suffix + ".qa.json")
    report = {
        "suite": "setup-installer-qa",
        "setup": str(path),
        "sha256": hashlib.sha256(data).hexdigest().upper(),
        "passed": sum(bool(result["passed"]) for result in RESULTS),
        "failed": sum(not bool(result["passed"]) for result in RESULTS),
        "results": RESULTS,
    }
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
    print("Relatório:", output)
    return 1 if report["failed"] else 0


if __name__ == "__main__":
    raise SystemExit(main())
