#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$RootDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$OutputDirectory = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'dist'),
    [switch]$RunQA,
    [switch]$IntegrationQA
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$module=Join-Path $RootDirectory 'modules\AutoRunner.Core.psm1'
Import-Module $module -Force -DisableNameChecking
if(Test-AutoRunnerTreeHasReparsePoint -Path $RootDirectory){throw 'A árvore de origem contém junction ou link simbólico.'}
if($RunQA){
    $qa=Join-Path $RootDirectory 'scripts\Invoke-QA.ps1'
    & (Get-AutoRunnerWindowsPowerShellPath) -NoProfile -ExecutionPolicy Bypass -File $qa -Integration:$IntegrationQA
    if($LASTEXITCODE -ne 0){throw 'QA falhou; release não será gerada.'}
}
$python=Get-Command python.exe -ErrorAction SilentlyContinue
if(-not $python){$python=Get-Command python -ErrorAction SilentlyContinue}
if(-not $python){throw 'Python 3 não encontrado.'}
New-Item -ItemType Directory -Path $OutputDirectory -Force|Out-Null
& $python.Source (Join-Path $RootDirectory 'build\Build-Native.py') --root $RootDirectory
if($LASTEXITCODE -ne 0){throw 'Build-Native.py falhou.'}
& $python.Source (Join-Path $RootDirectory 'build\Build-Release.py') --root $RootDirectory --output $OutputDirectory
if($LASTEXITCODE -ne 0){throw 'Build-Release.py falhou.'}
$version=Get-AutoRunnerVersion
$setup=Join-Path $OutputDirectory ("SQLBackupAndFTP-AutoRunner-Setup-v$version.exe")
$portable=Join-Path $OutputDirectory ("SQLBackupAndFTP-AutoRunner-v$version-Portable.zip")
$source=Join-Path $OutputDirectory ("SQLBackupAndFTP-AutoRunner-v$version-Source.zip")
return [pscustomobject]@{
    Setup=$setup
    SetupSha256=(Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash
    Portable=$portable
    PortableSha256=(Get-FileHash -LiteralPath $portable -Algorithm SHA256).Hash
    Source=$source
    SourceSha256=(Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash
}
