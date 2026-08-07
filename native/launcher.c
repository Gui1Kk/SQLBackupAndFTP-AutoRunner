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
typedef unsigned short WORD;
typedef unsigned char BYTE;
typedef struct _SECURITY_ATTRIBUTES SECURITY_ATTRIBUTES;
#define WINAPI __stdcall
#define INVALID_FILE_ATTRIBUTES ((DWORD)-1)
#define FILE_ATTRIBUTE_DIRECTORY 0x10
#define CREATE_NO_WINDOW 0x08000000
#define STARTF_USESHOWWINDOW 0x00000001
#define SW_HIDE 0
#define MB_OK 0x00000000
#define MB_ICONERROR 0x00000010
#define WAIT_TIMEOUT 258

__attribute__((used)) static void* memset(void* p,int v,unsigned long long n){unsigned char* b=(unsigned char*)p;while(n--)*b++=(unsigned char)v;return p;}
__attribute__((used)) void* memcpy(void* d,const void* s,unsigned long long n){unsigned char* out=(unsigned char*)d;const unsigned char* in=(const unsigned char*)s;while(n--)*out++=*in++;return d;}
typedef struct _STARTUPINFOW{DWORD cb;LPWSTR lpReserved;LPWSTR lpDesktop;LPWSTR lpTitle;DWORD dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;WORD wShowWindow,cbReserved2;BYTE* lpReserved2;HANDLE hStdInput,hStdOutput,hStdError;}STARTUPINFOW;
typedef struct _PROCESS_INFORMATION{HANDLE hProcess,hThread;DWORD dwProcessId,dwThreadId;}PROCESS_INFORMATION;
__declspec(dllimport) DWORD WINAPI GetModuleFileNameW(HINSTANCE,LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetSystemDirectoryW(LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetFileAttributesW(LPCWSTR);
__declspec(dllimport) BOOL WINAPI CreateProcessW(LPCWSTR,LPWSTR,SECURITY_ATTRIBUTES*,SECURITY_ATTRIBUTES*,BOOL,DWORD,LPVOID,LPCWSTR,STARTUPINFOW*,PROCESS_INFORMATION*);
__declspec(dllimport) DWORD WINAPI WaitForSingleObject(HANDLE,DWORD);
__declspec(dllimport) BOOL WINAPI GetExitCodeProcess(HANDLE,DWORD*);
__declspec(dllimport) BOOL WINAPI CloseHandle(HANDLE);
__declspec(dllimport) void WINAPI ExitProcess(DWORD);
__declspec(dllimport) int WINAPI MessageBoxW(void*,LPCWSTR,LPCWSTR,unsigned int);
static WCHAR g_self[32768],g_dir[32768],g_ps[32768],g_script[32768],g_cmd[32768];
static unsigned int wlen(const WCHAR*s){unsigned int n=0;while(s&&s[n])n++;return n;}
static int wcopy_s(WCHAR*d,DWORD cap,const WCHAR*s){unsigned int n=wlen(s);if(!d||!s||n>=cap)return 0;for(unsigned int i=0;i<=n;i++)d[i]=s[i];return 1;}
static int wappend_s(WCHAR*d,DWORD cap,const WCHAR*s){unsigned int a=wlen(d),b=wlen(s);if(!d||!s||a>=cap||b>=cap-a)return 0;for(unsigned int i=0;i<=b;i++)d[a+i]=s[i];return 1;}
static int last_slash(WCHAR*s){int i=(int)wlen(s)-1;for(;i>=0;i--)if(s[i]=='\\'||s[i]=='/')return i;return -1;}
static int exists_file(const WCHAR*p){DWORD a=GetFileAttributesW(p);return a!=INVALID_FILE_ATTRIBUTES&&!(a&FILE_ATTRIBUTE_DIRECTORY);}
void mainCRTStartup(void){
    DWORD selfLen=GetModuleFileNameW(0,g_self,32767);if(!selfLen||selfLen>=32767){MessageBoxW(0,L"Não foi possível determinar a pasta do AutoRunner.",L"SQLBackupAndFTP AutoRunner",MB_OK|MB_ICONERROR);ExitProcess(10);}
    if(!wcopy_s(g_dir,32768,g_self)){ExitProcess(11);}int slash=last_slash(g_dir);if(slash<0){ExitProcess(11);}g_dir[slash]=0;
    DWORD systemLen=GetSystemDirectoryW(g_ps,32767);if(!systemLen||systemLen>=32767||!wappend_s(g_ps,32768,L"\\WindowsPowerShell\\v1.0\\powershell.exe")){ExitProcess(12);}
    if(!wcopy_s(g_script,32768,g_dir)||!wappend_s(g_script,32768,L"\\scripts\\Manager.ps1")){ExitProcess(13);}
    if(!exists_file(g_ps)||!exists_file(g_script)){MessageBoxW(0,L"Arquivos da aplicação não foram encontrados. Use Reparar no instalador.",L"SQLBackupAndFTP AutoRunner",MB_OK|MB_ICONERROR);ExitProcess(13);}
    if(!wappend_s(g_cmd,32768,L"\"")||!wappend_s(g_cmd,32768,g_ps)||!wappend_s(g_cmd,32768,L"\" -NoLogo -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"")||!wappend_s(g_cmd,32768,g_script)||!wappend_s(g_cmd,32768,L"\"")){MessageBoxW(0,L"O caminho da aplicação é longo demais para iniciar com segurança.",L"SQLBackupAndFTP AutoRunner",MB_OK|MB_ICONERROR);ExitProcess(15);}
    STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};si.cb=sizeof(si);si.dwFlags=STARTF_USESHOWWINDOW;si.wShowWindow=SW_HIDE;
    if(!CreateProcessW(0,g_cmd,0,0,0,CREATE_NO_WINDOW,0,g_dir,&si,&pi)){MessageBoxW(0,L"Não foi possível iniciar o Windows PowerShell 5.1. Consulte %TEMP%\\SQLBackupAndFTPAuto.",L"SQLBackupAndFTP AutoRunner",MB_OK|MB_ICONERROR);ExitProcess(14);}
    CloseHandle(pi.hThread);
    DWORD wait=WaitForSingleObject(pi.hProcess,1800);if(wait!=WAIT_TIMEOUT){DWORD code=1;GetExitCodeProcess(pi.hProcess,&code);if(code!=0){MessageBoxW(0,L"A interface encerrou durante a inicialização. Consulte manager-startup.log em %TEMP%\\SQLBackupAndFTPAuto.",L"SQLBackupAndFTP AutoRunner",MB_OK|MB_ICONERROR);}}
    CloseHandle(pi.hProcess);ExitProcess(0);
}
