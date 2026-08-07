#Requires -Version 5.1
[CmdletBinding()]
param([switch]$SkipBackup)
$ErrorActionPreference='Stop'
$composeDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docker'))
if(-not $SkipBackup){& (Join-Path $PSScriptRoot 'Backup-ControlPlane.ps1');if($LASTEXITCODE -ne 0){throw 'Backup pré-atualização falhou.'}}
Push-Location $composeDir
try{
    & docker compose config --quiet;if($LASTEXITCODE -ne 0){throw 'docker compose config falhou.'}
    & docker compose build --pull;if($LASTEXITCODE -ne 0){throw 'Build das imagens falhou.'}
    & docker compose up -d --remove-orphans;if($LASTEXITCODE -ne 0){throw 'Atualização dos serviços falhou.'}
    & docker compose ps
}finally{Pop-Location}
