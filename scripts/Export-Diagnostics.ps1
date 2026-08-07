#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$SupportDir = (Join-Path $env:ProgramData 'SQLBackupAndFTPAuto'),
    [string]$DestinationDirectory = ([Environment]::GetFolderPath('Desktop')),
    [string]$TaskName = 'SQLBackupAndFTP AutoRunner',
    [string]$TaskPath = '\SQLBackupAndFTPAuto\'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$module=Join-Path $root 'modules\AutoRunner.Core.psm1'
if(-not(Test-Path -LiteralPath $module)){$module=Join-Path $SupportDir 'modules\AutoRunner.Core.psm1'}
Import-Module $module -Force -DisableNameChecking
$zip=Export-AutoRunnerDiagnostics -SupportDir $SupportDir -DestinationDirectory $DestinationDirectory -TaskName $TaskName -TaskPath $TaskPath
Write-Output $zip
