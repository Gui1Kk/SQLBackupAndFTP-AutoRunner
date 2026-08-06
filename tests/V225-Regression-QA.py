#!/usr/bin/env python3
"""Regression checks for 2.2.5: valid activation manifests, immutable setup payload and DPI-safe sidebar."""
from __future__ import annotations
import json, struct, sys, xml.etree.ElementTree as ET
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
RESULTS=[]
def add(name, passed, detail):
    RESULTS.append({'name':name,'passed':bool(passed),'detail':detail})
    print(f"[{'PASS' if passed else 'FAIL'}] {name}: {detail}")
def read(rel): return (ROOT/rel).read_text(encoding='utf-8-sig')

def manifest_from_pe(path: Path) -> str:
    data=path.read_bytes()
    if data[:2]!=b'MZ': raise ValueError('cabeçalho MZ ausente')
    pe=struct.unpack_from('<I',data,0x3c)[0]
    if data[pe:pe+4]!=b'PE\0\0': raise ValueError('cabeçalho PE ausente')
    coff=pe+4;nsec=struct.unpack_from('<H',data,coff+2)[0];optsz=struct.unpack_from('<H',data,coff+16)[0];opt=coff+20
    magic=struct.unpack_from('<H',data,opt)[0];dd=opt+(112 if magic==0x20b else 96)
    rva,_=struct.unpack_from('<II',data,dd+16);sec=opt+optsz;sections=[]
    for i in range(nsec):
        o=sec+i*40;vsize,vaddr,rsize,roff=struct.unpack_from('<IIII',data,o+8);sections.append((vaddr,max(vsize,rsize),roff))
    def off(x):
        for va,sz,ro in sections:
            if va<=x<va+sz:return ro+x-va
        raise ValueError('RVA fora das seções')
    root=off(rva)
    def entries(rel):
        q=root+rel;named,ids=struct.unpack_from('<HH',data,q+12)
        return [struct.unpack_from('<II',data,q+16+i*8) for i in range(named+ids)]
    type_entry=next((e for e in entries(0) if e[0]==24),None)
    if not type_entry: raise ValueError('RT_MANIFEST ausente')
    name_entries=entries(type_entry[1]&0x7fffffff);lang_entries=entries(name_entries[0][1]&0x7fffffff)
    de=root+(lang_entries[0][1]&0x7fffffff);dr,ds,_,_=struct.unpack_from('<IIII',data,de)
    return data[off(dr):off(dr)+ds].decode('utf-8-sig')

module=read('modules/AutoRunner.Core.psm1');builder=read('build/Build-Release.py');native_builder=read('build/Build-Native.py')
setup_c=read('native/setup.c');setup_ps=read('scripts/Setup-Wizard.ps1');manager=read('scripts/Manager.ps1')
add('Versão única 2.2.5', "$script:AutoRunnerVersion = '2.2.5'" in module and 'VERSION = "2.2.5"' in builder, 'módulo e build alinhados')
add('Linker não mescla UAC automaticamente', '"/manifestuac:no"' in native_builder and native_builder.count('"/manifestuac:no"')==1, 'flag aplicada à lista comum dos dois executáveis')
add('Build nativo reprodutível', '"/timestamp:0"' in native_builder and '"/Brepro"' in native_builder, 'timestamp PE fixo e conteúdo reprodutível')
add('Clone limpo recompila todas as import libs', 'for library in ("kernel32", "user32", "advapi32", "bcrypt")' in native_builder and 'f"/def:{library}.def"' in native_builder, 'nenhum .lib gerado precisa ser versionado')
for rel,level in [('SQLBackupAndFTP-AutoRunner.exe','asInvoker'),('native/setup-base.exe','requireAdministrator')]:
    try:
        text=manifest_from_pe(ROOT/rel);ET.fromstring(text)
        add(f'Manifesto XML válido: {rel}', True, level)
        add(f'Execution level não namespaceado: {rel}', f'level="{level}"' in text and 'ms_asmv1:level' not in text, 'atributo obrigatório preservado')
    except Exception as exc:add(f'Manifesto XML válido: {rel}',False,str(exc))
add('Payload e runtime do Setup separados', 'g_payload[32768]' in setup_c and 'ALPHA_SETUP_TEMP_ROOT' in setup_c and "Join-Path $env:ALPHA_SETUP_TEMP_ROOT 'runtime'" in setup_c, 'host compilado fora do payload verificado')
add('Setup não gera host dentro do payload', "$hostExe=Join-Path $root 'SQLBackupAndFTP-AutoRunner.SetupHost.exe'" not in setup_c, 'mutação eliminada')
add('Limpeza inclui payload e runtime', 'Remove-Item -LiteralPath $env:ALPHA_SETUP_TEMP_ROOT -Recurse -Force' in setup_c, 'raiz privada removida após o host encerrar')
add('Sidebar usa layout responsivo', '$sideLayout=New-Object Windows.Forms.TableLayoutPanel' in setup_ps and '$stepsPanel=New-Object Windows.Forms.TableLayoutPanel' in setup_ps, 'sem bloco monolítico de texto')
add('Etapas sem C-style newline literal', '\\r\\n' not in setup_ps and '\\r\\n' not in manager, 'PowerShell usa controles separados ou `r`n')
add('Logo usa PNG original', "assets\\AutoRunner.png" in setup_ps and '[Drawing.Image]::FromFile($logoPath)' in setup_ps and '[Drawing.Image]::FromFile($mainLogoPath)' in manager, 'sem Icon.ToBitmap')
add('Ícone usa construtor explícito', '[Drawing.Icon]::new($icon)' in setup_ps and '[Drawing.Icon]::new($mainIconPath)' in manager, 'overload não ambíguo')
add('Título lateral não depende de AutoSize', "$sideTitle.Dock='Fill'" in setup_ps and '$sideTitle.AutoEllipsis=$true' in setup_ps, 'texto respeita largura disponível')

result={'suite':'V225-Regression-QA','passed':sum(r['passed'] for r in RESULTS),'failed':sum(not r['passed'] for r in RESULTS),'results':RESULTS}
out=ROOT/'test-results';out.mkdir(exist_ok=True);(out/'V225-Regression-QA.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
sys.exit(1 if result['failed'] else 0)
