#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
function Invoke-Check([string]$Name,[scriptblock]$Block){
    try{& $Block;Write-Host ('[OK] '+$Name) -ForegroundColor Green;return $true}catch{Write-Host ('[FALHA] '+$Name+': '+$_.Exception.Message) -ForegroundColor Red;return $false}
}
$ok=$true
$ok=(Invoke-Check 'Docker CLI' {& docker version --format '{{.Server.Version}}' | Out-Null;if($LASTEXITCODE -ne 0){throw 'Docker Engine não respondeu.'}}) -and $ok
$ok=(Invoke-Check 'Docker Compose v2' {$v=& docker compose version --short;if($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($v)){throw 'docker compose indisponível.'}}) -and $ok
$ok=(Invoke-Check 'Linux containers' {$os=& docker info --format '{{.OSType}}';if($LASTEXITCODE -ne 0 -or $os.Trim() -ne 'linux'){throw "OSType atual: $os. Selecione Linux containers."}}) -and $ok
$ok=(Invoke-Check 'WSL 2 operacional' {$text=& wsl.exe -l -v 2>&1;if($LASTEXITCODE -ne 0){throw ($text -join ' ')}}) -and $ok
$ok=(Invoke-Check 'Portas 80/443 disponíveis ou conscientemente ocupadas' {
    $listeners=@(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue|Where-Object{$_.LocalPort -in 80,443})
    if($listeners.Count -gt 0){$owners=@($listeners|ForEach-Object{try{(Get-Process -Id $_.OwningProcess -ErrorAction Stop).ProcessName}catch{'PID '+$_.OwningProcess}}|Sort-Object -Unique);throw ('80/443 já em uso por: '+($owners -join ', '))}
}) -and $ok
if(-not $ok){exit 1}
Write-Host 'Pré-requisitos básicos aprovados.' -ForegroundColor Cyan
