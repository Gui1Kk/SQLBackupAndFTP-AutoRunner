#define UNICODE
#define _UNICODE

typedef unsigned long DWORD;
typedef int BOOL;
typedef unsigned short WCHAR;
typedef void* HANDLE;
typedef void* HINSTANCE;
typedef const WCHAR* LPCWSTR;
typedef WCHAR* LPWSTR;
typedef void* LPVOID;
typedef long long LONGLONG;
typedef unsigned long long ULONGLONG;
typedef long NTSTATUS;
typedef unsigned short WORD;
typedef unsigned char BYTE;
#define WINAPI __stdcall
#define INVALID_HANDLE_VALUE ((HANDLE)(LONGLONG)-1)
#define GENERIC_READ 0x80000000
#define GENERIC_WRITE 0x40000000
#define FILE_SHARE_READ 1
#define OPEN_EXISTING 3
#define CREATE_ALWAYS 2
#define FILE_ATTRIBUTE_NORMAL 0x80
#define FILE_ATTRIBUTE_DIRECTORY 0x10
#define FILE_ATTRIBUTE_REPARSE_POINT 0x400
#define INVALID_FILE_ATTRIBUTES ((DWORD)-1)
#define FILE_BEGIN 0
#define CREATE_NO_WINDOW 0x08000000
#define STARTF_USESHOWWINDOW 1
#define SW_HIDE 0
#define INFINITE 0xFFFFFFFF
#define MB_OK 0
#define MB_ICONERROR 0x10
#define SDDL_REVISION_1 1
#define BCRYPT_USE_SYSTEM_PREFERRED_RNG 0x00000002

typedef struct _SECURITY_ATTRIBUTES {
    DWORD nLength;
    LPVOID lpSecurityDescriptor;
    BOOL bInheritHandle;
} SECURITY_ATTRIBUTES;

__attribute__((used)) static void* memset(void* p,int v,unsigned long long n){unsigned char* b=(unsigned char*)p;while(n--)*b++=(unsigned char)v;return p;}
__attribute__((used)) void* memcpy(void* d,const void* s,unsigned long long n){unsigned char* out=(unsigned char*)d;const unsigned char* in=(const unsigned char*)s;while(n--)*out++=*in++;return d;}

typedef struct _LARGE_INTEGER{LONGLONG QuadPart;}LARGE_INTEGER;
typedef struct _STARTUPINFOW{DWORD cb;LPWSTR lpReserved;LPWSTR lpDesktop;LPWSTR lpTitle;DWORD dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;WORD wShowWindow,cbReserved2;BYTE* lpReserved2;HANDLE hStdInput,hStdOutput,hStdError;}STARTUPINFOW;
typedef struct _PROCESS_INFORMATION{HANDLE hProcess,hThread;DWORD dwProcessId,dwThreadId;}PROCESS_INFORMATION;

__declspec(dllimport) DWORD WINAPI GetModuleFileNameW(HINSTANCE,LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetSystemDirectoryW(LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetEnvironmentVariableW(LPCWSTR,LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetFileAttributesW(LPCWSTR);
__declspec(dllimport) BOOL WINAPI CreateDirectoryW(LPCWSTR,SECURITY_ATTRIBUTES*);
__declspec(dllimport) BOOL WINAPI RemoveDirectoryW(LPCWSTR);
__declspec(dllimport) BOOL WINAPI DeleteFileW(LPCWSTR);
__declspec(dllimport) HANDLE WINAPI CreateFileW(LPCWSTR,DWORD,DWORD,SECURITY_ATTRIBUTES*,DWORD,DWORD,HANDLE);
__declspec(dllimport) BOOL WINAPI GetFileSizeEx(HANDLE,LARGE_INTEGER*);
__declspec(dllimport) BOOL WINAPI SetFilePointerEx(HANDLE,LARGE_INTEGER,LARGE_INTEGER*,DWORD);
__declspec(dllimport) BOOL WINAPI ReadFile(HANDLE,LPVOID,DWORD,DWORD*,LPVOID);
__declspec(dllimport) BOOL WINAPI WriteFile(HANDLE,const void*,DWORD,DWORD*,LPVOID);
__declspec(dllimport) BOOL WINAPI CloseHandle(HANDLE);
__declspec(dllimport) BOOL WINAPI CreateProcessW(LPCWSTR,LPWSTR,SECURITY_ATTRIBUTES*,SECURITY_ATTRIBUTES*,BOOL,DWORD,LPVOID,LPCWSTR,STARTUPINFOW*,PROCESS_INFORMATION*);
__declspec(dllimport) DWORD WINAPI WaitForSingleObject(HANDLE,DWORD);
__declspec(dllimport) BOOL WINAPI GetExitCodeProcess(HANDLE,DWORD*);
__declspec(dllimport) BOOL WINAPI SetEnvironmentVariableW(LPCWSTR,LPCWSTR);
__declspec(dllimport) LPWSTR WINAPI GetCommandLineW(void);
__declspec(dllimport) HANDLE WINAPI LocalFree(HANDLE);
__declspec(dllimport) void WINAPI ExitProcess(DWORD);
__declspec(dllimport) int WINAPI MessageBoxW(void*,LPCWSTR,LPCWSTR,unsigned int);
__declspec(dllimport) BOOL WINAPI ConvertStringSecurityDescriptorToSecurityDescriptorW(LPCWSTR,DWORD,LPVOID*,DWORD*);
__declspec(dllimport) NTSTATUS WINAPI BCryptGenRandom(HANDLE,BYTE*,DWORD,DWORD);

static WCHAR g_self[32768],g_temp[32768],g_dir[32768],g_zip[32768],g_ps[32768],g_cmd[32768];
static BYTE g_buffer[65536];

static unsigned int wlen(const WCHAR*s){unsigned int n=0;while(s&&s[n])n++;return n;}
static int wcopy_s(WCHAR*d,DWORD cap,const WCHAR*s){unsigned int n=wlen(s);if(!d||!s||n>=cap)return 0;for(unsigned int i=0;i<=n;i++)d[i]=s[i];return 1;}
static int wappend_s(WCHAR*d,DWORD cap,const WCHAR*s){unsigned int a=wlen(d),b=wlen(s);if(!d||!s||a>=cap||b>=cap-a)return 0;for(unsigned int i=0;i<=b;i++)d[a+i]=s[i];return 1;}
static WCHAR lower_ascii(WCHAR c){return (c>='A'&&c<='Z')?(WCHAR)(c+32):c;}
static int weqi(const WCHAR*a,const WCHAR*b){unsigned int i=0;if(!a||!b)return 0;while(a[i]&&b[i]){if(lower_ascii(a[i])!=lower_ascii(b[i]))return 0;i++;}return a[i]==0&&b[i]==0;}
/* The setup accepts only exact slash switches. Substring matching made a path such as
   C:\packages\uninstall\setup.exe accidentally select uninstall mode. */
static int has_exact_arg(const WCHAR*command,const WCHAR*wanted){
    WCHAR token[128];unsigned int t=0;int quoted=0,first=1;const WCHAR*p=command;
    while(p&&*p){
        while(*p==' '||*p=='\t')p++;
        if(!*p)break;
        t=0;quoted=0;
        while(*p){
            if(*p=='\"'){quoted=!quoted;p++;continue;}
            if(!quoted&&(*p==' '||*p=='\t'))break;
            if(t+1<128)token[t++]=*p;
            p++;
        }
        token[t]=0;
        if(!first&&weqi(token,wanted))return 1;
        first=0;
        while(*p==' '||*p=='\t')p++;
    }
    return 0;
}
static int bytes_equal(const BYTE*a,const BYTE*b,int n){for(int i=0;i<n;i++)if(a[i]!=b[i])return 0;return 1;}
static int append_hex_s(WCHAR*d,DWORD cap,const BYTE*b,DWORD n){static const WCHAR h[]=L"0123456789abcdef";unsigned int a=wlen(d);if(!d||!b||a>=cap||n>(cap-a-1)/2)return 0;d+=a;for(DWORD i=0;i<n;i++){*d++=h[(b[i]>>4)&15];*d++=h[b[i]&15];}*d=0;return 1;}
static void cleanup_temp(void){DeleteFileW(g_zip);RemoveDirectoryW(g_dir);}
static void fail(DWORD code,LPCWSTR message){cleanup_temp();if(message)MessageBoxW(0,message,L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(code);}
static void append_cmd(LPCWSTR value){if(!wappend_s(g_cmd,32768,value))fail(29,L"O comando interno do instalador excedeu o limite seguro do Windows.");}

void mainCRTStartup(void){
    WCHAR* self=g_self;WCHAR* temp=g_temp;WCHAR* dir=g_dir;WCHAR* zip=g_zip;WCHAR* ps=g_ps;WCHAR* cmd=g_cmd;
    DWORD selfLen=GetModuleFileNameW(0,self,32767);
    DWORD tempLen=GetEnvironmentVariableW(L"ProgramFiles",temp,32767);
    if(!selfLen||selfLen>=32767||!tempLen||tempLen>=32767){MessageBoxW(0,L"Falha ao preparar o instalador.",L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(20);}
    {
        DWORD attrs=GetFileAttributesW(temp);
        if(attrs==INVALID_FILE_ATTRIBUTES||!(attrs&FILE_ATTRIBUTE_DIRECTORY)||(attrs&FILE_ATTRIBUTE_REPARSE_POINT)){MessageBoxW(0,L"A pasta Program Files não passou na validação de segurança.",L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(28);}
    }

    LPVOID securityDescriptor=0;
    if(!ConvertStringSecurityDescriptorToSecurityDescriptorW(L"D:P(A;OICI;FA;;;SY)(A;OICI;FA;;;BA)",SDDL_REVISION_1,&securityDescriptor,0)){
        MessageBoxW(0,L"Não foi possível criar a ACL privada do instalador.",L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(28);
    }
    SECURITY_ATTRIBUTES securityAttributes={sizeof(SECURITY_ATTRIBUTES),securityDescriptor,0};
    BOOL created=0;
    for(DWORD attempt=0;attempt<32&&!created;attempt++){
        BYTE randomBytes[16];
        (void)attempt;
        if(BCryptGenRandom(0,randomBytes,sizeof(randomBytes),BCRYPT_USE_SYSTEM_PREFERRED_RNG)<0){LocalFree(securityDescriptor);MessageBoxW(0,L"O gerador criptográfico do Windows falhou; a instalação foi cancelada com segurança.",L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(28);}
        /* The elevated bootstrap extracts directly under Program Files, whose parent
           ACL is not writable by the filtered interactive token. A private DACL on
           the random child then closes the replace/rename window that exists when
           an elevated payload is staged below the user's TEMP directory. */
        if(!wcopy_s(dir,32768,temp)||!wappend_s(dir,32768,L"\\.AlphaAutoRunnerSetup-")||!append_hex_s(dir,32768,randomBytes,sizeof(randomBytes))){LocalFree(securityDescriptor);MessageBoxW(0,L"O caminho temporário é longo demais para uso seguro.",L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(28);}
        created=CreateDirectoryW(dir,&securityAttributes);
    }
    if(!created){LocalFree(securityDescriptor);MessageBoxW(0,L"Não foi possível criar a pasta temporária privada do instalador.",L"AutoRunner Setup",MB_OK|MB_ICONERROR);ExitProcess(28);}
    if(!wcopy_s(zip,32768,dir)||!wappend_s(zip,32768,L"\\payload.zip")){LocalFree(securityDescriptor);fail(28,L"O caminho temporário do pacote é longo demais.");}

    HANDLE in=CreateFileW(self,GENERIC_READ,FILE_SHARE_READ,0,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,0);
    if(in==INVALID_HANDLE_VALUE){LocalFree(securityDescriptor);fail(21,L"Não foi possível abrir o instalador para leitura.");}
    LARGE_INTEGER total={0};
    if(!GetFileSizeEx(in,&total)||total.QuadPart<24){CloseHandle(in);LocalFree(securityDescriptor);fail(22,L"Instalador truncado ou inválido.");}
    BYTE trailer[24];LARGE_INTEGER pos={total.QuadPart-24};
    if(!SetFilePointerEx(in,pos,0,FILE_BEGIN)){CloseHandle(in);LocalFree(securityDescriptor);fail(22,L"Não foi possível localizar o pacote interno.");}
    DWORD read=0;
    if(!ReadFile(in,trailer,24,&read,0)){CloseHandle(in);LocalFree(securityDescriptor);fail(22,L"Não foi possível ler o pacote interno.");}
    BYTE magic[16]={'A','L','P','H','A','S','E','T','U','P','Z','I','P','0','1','!'};
    if(read!=24||!bytes_equal(trailer,magic,16)){CloseHandle(in);LocalFree(securityDescriptor);fail(23,L"Pacote interno do instalador inválido.");}
    ULONGLONG size=0;for(int i=0;i<8;i++)size|=((ULONGLONG)trailer[16+i])<<(8*i);
    if(size==0||size>(ULONGLONG)(total.QuadPart-24)){CloseHandle(in);LocalFree(securityDescriptor);fail(24,L"Tamanho do pacote interno inválido.");}
    LARGE_INTEGER payloadPos={total.QuadPart-24-(LONGLONG)size};
    if(!SetFilePointerEx(in,payloadPos,0,FILE_BEGIN)){CloseHandle(in);LocalFree(securityDescriptor);fail(24,L"Posição do pacote interno inválida.");}
    HANDLE out=CreateFileW(zip,GENERIC_WRITE,0,&securityAttributes,CREATE_ALWAYS,FILE_ATTRIBUTE_NORMAL,0);
    LocalFree(securityDescriptor);
    if(out==INVALID_HANDLE_VALUE){CloseHandle(in);fail(25,L"Não foi possível criar o pacote temporário privado.");}
    ULONGLONG left=size;
    while(left){
        DWORD want=left>65536?65536:(DWORD)left,got=0,written=0;
        if(!ReadFile(in,g_buffer,want,&got,0)||got==0||!WriteFile(out,g_buffer,got,&written,0)||written!=got){CloseHandle(in);CloseHandle(out);fail(26,L"Falha ao extrair o pacote interno.");}
        left-=got;
    }
    CloseHandle(in);CloseHandle(out);

    SetEnvironmentVariableW(L"ALPHA_PAYLOAD_ZIP",zip);
    SetEnvironmentVariableW(L"ALPHA_PAYLOAD_DIR",dir);
    SetEnvironmentVariableW(L"ALPHA_SETUP_EXE",self);
    LPWSTR original=GetCommandLineW();
    if(has_exact_arg(original,L"/uninstall"))SetEnvironmentVariableW(L"ALPHA_SETUP_MODE",L"Uninstall");
    else if(has_exact_arg(original,L"/repair"))SetEnvironmentVariableW(L"ALPHA_SETUP_MODE",L"Repair");
    else SetEnvironmentVariableW(L"ALPHA_SETUP_MODE",L"Auto");
    SetEnvironmentVariableW(L"ALPHA_SETUP_SILENT",has_exact_arg(original,L"/silent")?L"1":L"0");
    SetEnvironmentVariableW(L"ALPHA_SETUP_DESKTOP",has_exact_arg(original,L"/desktop")?L"1":L"0");
    SetEnvironmentVariableW(L"ALPHA_SETUP_LAUNCH",has_exact_arg(original,L"/nolaunch")?L"0":L"1");
    SetEnvironmentVariableW(L"ALPHA_SETUP_PRESERVE",has_exact_arg(original,L"/purgedata")?L"0":L"1");
    SetEnvironmentVariableW(L"ALPHA_SETUP_DEFERRED",has_exact_arg(original,L"/deferred")?L"1":L"0");
    SetEnvironmentVariableW(L"ALPHA_SETUP_NOTUTORIAL",has_exact_arg(original,L"/notutorial")?L"1":L"0");

    DWORD systemLen=GetSystemDirectoryW(ps,32767);if(!systemLen||systemLen>=32767||!wappend_s(ps,32768,L"\\WindowsPowerShell\\v1.0\\powershell.exe"))fail(27,L"Não foi possível localizar o Windows PowerShell.");
    append_cmd(L"\"");append_cmd(ps);
    append_cmd(L"\" -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -Command \"");
    append_cmd(L"$ErrorActionPreference='Stop';$code=1;try{");
    append_cmd(L"$root=[IO.Path]::GetFullPath($env:ALPHA_PAYLOAD_DIR).TrimEnd('\\');$prefix=$root+'\\';Add-Type -AssemblyName System.IO.Compression;Add-Type -AssemblyName System.IO.Compression.FileSystem;");
    append_cmd(L"$stream=[IO.File]::Open($env:ALPHA_PAYLOAD_ZIP,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read);try{$archive=[IO.Compression.ZipArchive]::new($stream,[IO.Compression.ZipArchiveMode]::Read,$false);try{$zipSeen=@{};$extract=New-Object System.Collections.Generic.List[object];foreach($entry in @($archive.Entries)){$name=([string]$entry.FullName).Replace('/','\\');if([string]::IsNullOrWhiteSpace($name)-or[string]::IsNullOrWhiteSpace([string]$entry.Name)-or$name.EndsWith('\\')){throw ('Entrada ZIP de diretório ou vazia recusada: '+$name)};if($name -match '^[\\/]' -or $name -match '^[A-Za-z]:' ){throw ('Caminho absoluto recusado no ZIP: '+$name)};$parts=$name.Split('\\');if($parts -contains '' -or $parts -contains '.' -or $parts -contains '..'){throw ('Componente inseguro no ZIP: '+$name)};foreach($part in $parts){if($part.EndsWith('.')-or$part.EndsWith(' ')-or$part.IndexOfAny([char[]]'<>:\"|?*')-ge 0){throw ('Nome Windows inválido no ZIP: '+$name)};$base=[IO.Path]::GetFileNameWithoutExtension($part);if($base -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$'){throw ('Nome de dispositivo recusado no ZIP: '+$name)}};$key=$name.ToLowerInvariant();if($zipSeen.ContainsKey($key)){throw ('Entrada ZIP duplicada por caixa: '+$name)};$dest=[IO.Path]::GetFullPath((Join-Path $root $name));if(-not $dest.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase)){throw ('Entrada ZIP escaparia da pasta privada: '+$name)};if(Test-Path -LiteralPath $dest){throw ('Destino ZIP já existe: '+$name)};$zipSeen[$key]=$true;$extract.Add([pscustomobject]@{Entry=$entry;Destination=$dest})};foreach($item in $extract){[IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($item.Destination))|Out-Null;[IO.Compression.ZipFileExtensions]::ExtractToFile($item.Entry,$item.Destination,$false)}}finally{if($archive){$archive.Dispose()}}}finally{$stream.Dispose()};");
    append_cmd(L"Remove-Item -LiteralPath $env:ALPHA_PAYLOAD_ZIP -Force;");
    append_cmd(L"$sum=Join-Path $root 'SHA256SUMS.txt';");
    append_cmd(L"if(-not(Test-Path -LiteralPath $sum -PathType Leaf)){throw 'SHA256SUMS.txt ausente no instalador.'};$seen=@{};");
    append_cmd(L"foreach($line in @(Get-Content -LiteralPath $sum -Encoding UTF8)){if([string]::IsNullOrWhiteSpace($line)){continue};if($line -notmatch '^([A-Fa-f0-9]{64})\\s+\\*?(.+)$'){throw ('Linha de checksum inválida: '+$line)};$expected=$matches[1].ToUpperInvariant();$rel=$matches[2].Trim().Replace('/','\\');$parts=@($rel.Split('\\')|Where-Object{$_ -ne ''});if($rel -match '^[\\\\/]' -or $rel -match '^[A-Za-z]:' -or $parts -contains '..' -or [string]::IsNullOrWhiteSpace($rel)){throw ('Caminho inseguro no checksum: '+$rel)};if([IO.Path]::GetFileName($rel) -ieq 'SHA256SUMS.txt'){throw 'O checksum não pode declarar a si próprio.'};$key=$rel.ToLowerInvariant();if($seen.ContainsKey($key)){throw ('Caminho duplicado no checksum: '+$rel)};$full=[IO.Path]::GetFullPath((Join-Path $root $rel));if(-not($full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase))){throw ('Arquivo fora do pacote: '+$rel)};if(-not(Test-Path -LiteralPath $full -PathType Leaf)){throw ('Arquivo ausente no pacote: '+$rel)};if((Get-FileHash -LiteralPath $full -Algorithm SHA256).Hash -ne $expected){throw ('Hash divergente no pacote: '+$rel)};$seen[$key]=$true};");
    append_cmd(L"$files=@(Get-ChildItem -LiteralPath $root -Recurse -File -Force|Where-Object{$_.FullName -ine $sum});if($files.Count -ne $seen.Count){throw 'Quantidade de arquivos do pacote diverge do checksum.'};foreach($file in $files){$rel=$file.FullName.Substring($prefix.Length).ToLowerInvariant();if(-not $seen.ContainsKey($rel)){throw ('Arquivo não declarado no checksum: '+$rel)}};");
    append_cmd(L"$check=& (Join-Path $root 'scripts\\Setup-Wizard.ps1') -PayloadRoot $root -InstallerPath $env:ALPHA_SETUP_EXE -Mode $env:ALPHA_SETUP_MODE -Silent:($env:ALPHA_SETUP_SILENT-eq'1') -DesktopShortcut:($env:ALPHA_SETUP_DESKTOP-eq'1') -LaunchAfterInstall:($env:ALPHA_SETUP_LAUNCH-eq'1') -PreserveData:($env:ALPHA_SETUP_PRESERVE-eq'1') -Deferred:($env:ALPHA_SETUP_DEFERRED-eq'1') -DoNotShowTutorial:($env:ALPHA_SETUP_NOTUTORIAL-eq'1');$code=if($null-ne$LASTEXITCODE){$LASTEXITCODE}elseif($?){0}else{1}");
    append_cmd(L"}catch{Add-Type -AssemblyName System.Windows.Forms;[Windows.Forms.MessageBox]::Show($_.Exception.Message,'AutoRunner Setup','OK','Error')|Out-Null;$code=1}finally{Remove-Item -LiteralPath $env:ALPHA_PAYLOAD_ZIP -Force -ErrorAction SilentlyContinue;Get-ChildItem -LiteralPath $env:ALPHA_PAYLOAD_DIR -Force -ErrorAction SilentlyContinue|Remove-Item -Recurse -Force -ErrorAction SilentlyContinue;Remove-Item -LiteralPath $env:ALPHA_PAYLOAD_DIR -Force -ErrorAction SilentlyContinue};exit $code\"");

    STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};si.cb=sizeof(si);si.dwFlags=STARTF_USESHOWWINDOW;si.wShowWindow=SW_HIDE;
    if(!CreateProcessW(0,cmd,0,0,0,CREATE_NO_WINDOW,0,0,&si,&pi))fail(27,L"Não foi possível iniciar o instalador PowerShell.");
    WaitForSingleObject(pi.hProcess,INFINITE);DWORD code=1;GetExitCodeProcess(pi.hProcess,&code);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);cleanup_temp();ExitProcess(code);
}
