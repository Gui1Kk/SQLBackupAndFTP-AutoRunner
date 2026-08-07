#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ApplicationRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
    [string]$SupportDir = (Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'),
    [string]$TaskName = 'SQLBackupAndFTP AutoRunner',
    [string]$TaskPath = '\SQLBackupAndFTPAuto\',
    [switch]$PreserveData
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$module=Join-Path $ApplicationRoot 'modules\AutoRunner.Core.psm1'
if(-not(Test-Path -LiteralPath $module -PathType Leaf)){throw 'Módulo do AutoRunner ausente durante a remoção MSI.'}
Import-Module $module -Force -DisableNameChecking
if(-not(Test-AutoRunnerAdministrator)){throw 'A limpeza MSI exige privilégios administrativos.'}
Remove-AutoRunnerIntegration -TaskName $TaskName -TaskPath $TaskPath
if(-not $PreserveData -and (Test-Path -LiteralPath $SupportDir)){
    if(-not(Test-AutoRunnerSupportPath -Path $SupportDir)){throw 'Diretório de suporte inválido; limpeza MSI recusada.'}
    if(Test-AutoRunnerTreeHasReparsePoint -Path $SupportDir){throw 'Diretório de suporte contém junction ou link simbólico; limpeza MSI recusada.'}
    Remove-Item -LiteralPath $SupportDir -Recurse -Force
}
exit 0
