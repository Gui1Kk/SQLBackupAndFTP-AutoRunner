#define UNICODE
#define _UNICODE

typedef unsigned long DWORD;typedef int BOOL;typedef unsigned short WCHAR;typedef void* HANDLE;typedef void* HINSTANCE;typedef const WCHAR* LPCWSTR;typedef WCHAR* LPWSTR;typedef void* LPVOID;typedef unsigned short WORD;typedef unsigned char BYTE;typedef struct _SECURITY_ATTRIBUTES SECURITY_ATTRIBUTES;
#define WINAPI __stdcall
#define INVALID_FILE_ATTRIBUTES ((DWORD)-1)
#define FILE_ATTRIBUTE_DIRECTORY 0x10
#define CREATE_NO_WINDOW 0x08000000
#define STARTF_USESHOWWINDOW 1
#define SW_HIDE 0
#define INFINITE 0xFFFFFFFF

__attribute__((used)) static void* memset(void* p,int v,unsigned long long n){unsigned char* b=(unsigned char*)p;while(n--)*b++=(unsigned char)v;return p;}
__attribute__((used)) void* memcpy(void* d,const void* s,unsigned long long n){unsigned char* out=(unsigned char*)d;const unsigned char* in=(const unsigned char*)s;while(n--)*out++=*in++;return d;}
typedef struct _STARTUPINFOW{DWORD cb;LPWSTR lpReserved;LPWSTR lpDesktop;LPWSTR lpTitle;DWORD dwX,dwY,dwXSize,dwYSize,dwXCountChars,dwYCountChars,dwFillAttribute,dwFlags;WORD wShowWindow,cbReserved2;BYTE* lpReserved2;HANDLE hStdInput,hStdOutput,hStdError;}STARTUPINFOW;
typedef struct _PROCESS_INFORMATION{HANDLE hProcess,hThread;DWORD dwProcessId,dwThreadId;}PROCESS_INFORMATION;
__declspec(dllimport) DWORD WINAPI GetModuleFileNameW(HINSTANCE,LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetSystemDirectoryW(LPWSTR,DWORD);
__declspec(dllimport) DWORD WINAPI GetFileAttributesW(LPCWSTR);
__declspec(dllimport) LPWSTR WINAPI GetCommandLineW(void);
__declspec(dllimport) BOOL WINAPI CreateProcessW(LPCWSTR,LPWSTR,SECURITY_ATTRIBUTES*,SECURITY_ATTRIBUTES*,BOOL,DWORD,LPVOID,LPCWSTR,STARTUPINFOW*,PROCESS_INFORMATION*);
__declspec(dllimport) DWORD WINAPI WaitForSingleObject(HANDLE,DWORD);
__declspec(dllimport) BOOL WINAPI GetExitCodeProcess(HANDLE,DWORD*);
__declspec(dllimport) BOOL WINAPI CloseHandle(HANDLE);
__declspec(dllimport) void WINAPI ExitProcess(DWORD);
static WCHAR g_self[32768],g_dir[32768],g_ps[32768],g_script[32768],g_cmd[32768];
static unsigned int wlen(const WCHAR*s){unsigned int n=0;while(s&&s[n])n++;return n;}static WCHAR lower_ascii(WCHAR c){return(c>='A'&&c<='Z')?(WCHAR)(c+32):c;}static int weqi(const WCHAR*a,const WCHAR*b){unsigned int i=0;if(!a||!b)return 0;while(a[i]&&b[i]){if(lower_ascii(a[i])!=lower_ascii(b[i]))return 0;i++;}return a[i]==0&&b[i]==0;}static int has_exact_arg(const WCHAR*command,const WCHAR*wanted){WCHAR token[256];unsigned int t=0;int quoted=0,first=1;const WCHAR*p=command;while(p&&*p){while(*p==' '||*p=='\t')p++;if(!*p)break;t=0;quoted=0;while(*p){if(*p=='\"'){quoted=!quoted;p++;continue;}if(!quoted&&(*p==' '||*p=='\t'))break;if(t+1<256)token[t++]=*p;p++;}token[t]=0;if(!first&&weqi(token,wanted))return 1;first=0;while(*p==' '||*p=='\t')p++;}return 0;}static int wcopy_s(WCHAR*d,DWORD cap,const WCHAR*s){unsigned int n=wlen(s);if(!d||!s||n>=cap)return 0;for(unsigned int i=0;i<=n;i++)d[i]=s[i];return 1;}static int wappend_s(WCHAR*d,DWORD cap,const WCHAR*s){unsigned int a=wlen(d),b=wlen(s);if(!d||!s||a>=cap||b>=cap-a)return 0;for(unsigned int i=0;i<=b;i++)d[a+i]=s[i];return 1;}static int last_slash(WCHAR*s){int i=(int)wlen(s)-1;for(;i>=0;i--)if(s[i]=='\\'||s[i]=='/')return i;return -1;}static int exists_file(const WCHAR*p){DWORD a=GetFileAttributesW(p);return a!=INVALID_FILE_ATTRIBUTES&&!(a&FILE_ATTRIBUTE_DIRECTORY);}
void mainCRTStartup(void){
 WCHAR*self=g_self;WCHAR*dir=g_dir;WCHAR*ps=g_ps;WCHAR*script=g_script;WCHAR*cmd=g_cmd;
 DWORD selfLen=GetModuleFileNameW(0,self,32767);if(!selfLen||selfLen>=32767||!wcopy_s(dir,32768,self))ExitProcess(30);int slash=last_slash(dir);if(slash<0)ExitProcess(31);dir[slash]=0;
 DWORD systemLen=GetSystemDirectoryW(ps,32767);if(!systemLen||systemLen>=32767||!wappend_s(ps,32768,L"\\WindowsPowerShell\\v1.0\\powershell.exe"))ExitProcess(32);if(!wcopy_s(script,32768,dir)||!wappend_s(script,32768,L"\\scripts\\Msi-Cleanup.ps1"))ExitProcess(33);
 if(!exists_file(ps)||!exists_file(script))ExitProcess(33);
 if(!wappend_s(cmd,32768,L"\"")||!wappend_s(cmd,32768,ps)||!wappend_s(cmd,32768,L"\" -NoProfile -STA -NonInteractive -ExecutionPolicy Bypass -WindowStyle Hidden -File \"")||!wappend_s(cmd,32768,script)||!wappend_s(cmd,32768,L"\" -ApplicationRoot \"")||!wappend_s(cmd,32768,dir)||!wappend_s(cmd,32768,L"\""))ExitProcess(35);if(has_exact_arg(GetCommandLineW(),L"PRESERVEDATA=1")&&!wappend_s(cmd,32768,L" -PreserveData"))ExitProcess(35);
 STARTUPINFOW si={0};PROCESS_INFORMATION pi={0};si.cb=sizeof(si);si.dwFlags=STARTF_USESHOWWINDOW;si.wShowWindow=SW_HIDE;if(!CreateProcessW(0,cmd,0,0,0,CREATE_NO_WINDOW,0,dir,&si,&pi))ExitProcess(34);WaitForSingleObject(pi.hProcess,INFINITE);DWORD code=1;GetExitCodeProcess(pi.hProcess,&code);CloseHandle(pi.hThread);CloseHandle(pi.hProcess);ExitProcess(code);
}
