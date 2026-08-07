#!/usr/bin/env python3
"""Build reproducible x64 native launchers without a Visual Studio CRT dependency."""
from __future__ import annotations
import argparse, shutil, struct, subprocess, tempfile
from pathlib import Path

def run(args:list[str],cwd:Path)->None: subprocess.run(args,cwd=cwd,check=True)
def align4(data:bytes)->bytes: return data+b"\0"*((-len(data))%4)
def res_entry(type_id:int,name_id:int,payload:bytes,lang:int=0x409,memory:int=0x1030)->bytes:
    header=struct.pack('<HHHH',0xFFFF,type_id,0xFFFF,name_id)
    header=align4(header)+struct.pack('<IHHII',0,memory,lang,0,0)
    return struct.pack('<II',len(payload),8+len(header))+header+align4(payload)
def make_icon_res(ico:Path,output:Path)->None:
    data=ico.read_bytes()
    if len(data)<6: raise ValueError('ICO header truncated')
    reserved,kind,count=struct.unpack_from('<HHH',data,0)
    if reserved!=0 or kind!=1 or not 1<=count<=256: raise ValueError('Invalid ICO file')
    if 6+count*16>len(data): raise ValueError('ICO directory truncated')
    images=[]
    for index in range(count):
        off=6+index*16
        width,height,colors,reserved_byte,planes,bpp,size,image_offset=struct.unpack_from('<BBBBHHII',data,off)
        if size<1 or image_offset>len(data) or size>len(data)-image_offset: raise ValueError('Truncated ICO image')
        images.append((width,height,colors,reserved_byte,planes,bpp,size,data[image_offset:image_offset+size]))
    result=bytearray(res_entry(0,0,b'',lang=0,memory=0))
    for resource_id,image in enumerate(images,1): result+=res_entry(3,resource_id,image[-1])
    group=struct.pack('<HHH',0,1,len(images))
    for resource_id,image in enumerate(images,1):
        width,height,colors,reserved_byte,planes,bpp,size,_=image
        group+=struct.pack('<BBBBHHIH',width,height,colors,reserved_byte,planes,bpp,size,resource_id)
    result+=res_entry(14,1,group);output.write_bytes(result)
def main()->int:
    parser=argparse.ArgumentParser();parser.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[1]);args=parser.parse_args()
    root=args.root.resolve();native=root/'native';clang=shutil.which('clang-cl');link=shutil.which('lld-link')
    if not clang or not link: raise SystemExit('clang-cl and lld-link are required')
    with tempfile.TemporaryDirectory(prefix='AutoRunnerNative-') as td:
        work=Path(td);icon_res=work/'AutoRunnerIcon.res';make_icon_res(root/'assets'/'AutoRunner.ico',icon_res)
        for library in ('kernel32','user32','advapi32','bcrypt'):
            run([link,'/lib','/Brepro',f'/def:{library}.def','/machine:x64',f'/out:{library}.lib'],native)
        targets=(
            ('launcher.c',root/'SQLBackupAndFTP-AutoRunner.exe','launcher.manifest',['kernel32.lib','user32.lib']),
            ('setup.c',native/'setup-base.exe','setup.manifest',['kernel32.lib','user32.lib','advapi32.lib','bcrypt.lib']),
            ('msi-bridge.c',native/'SQLBackupAndFTP-AutoRunner-MsiBridge.exe','launcher.manifest',['kernel32.lib']),
        )
        for source,output,manifest,libraries in targets:
            obj=work/(Path(source).stem+'.obj')
            # /GS- is intentional for this CRT-free bootstrap. All large buffers are static,
            # every append is capacity checked, and the sources are statically analyzed in CI.
            run([clang,'--target=x86_64-pc-windows-msvc','/c','/O2','/GS-','/Zl','/W4','/WX',source,'/Fo:'+str(obj)],native)
            run([link,'/entry:mainCRTStartup','/subsystem:windows','/machine:x64','/nodefaultlib','/dynamicbase','/nxcompat','/highentropyva','/timestamp:0','/Brepro','/out:'+str(output),str(obj),*libraries,str(icon_res),'/manifest:embed','/manifestuac:no','/manifestinput:'+manifest],native)
    print(root/'SQLBackupAndFTP-AutoRunner.exe');print(native/'setup-base.exe');print(native/'SQLBackupAndFTP-AutoRunner-MsiBridge.exe');return 0
if __name__=='__main__': raise SystemExit(main())
