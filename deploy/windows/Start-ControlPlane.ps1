﻿#Requires -Version 5.1
[CmdletBinding()]
param()
$ErrorActionPreference='Stop'
$composeDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docker'))
$envPath=Join-Path $composeDir '.env'
if(-not(Test-Path -LiteralPath $envPath -PathType Leaf)){throw 'Arquivo deploy/docker/.env ausente. Rode New-ControlPlaneEnv.ps1 primeiro.'}
Push-Location $composeDir
try{
    & docker compose config --quiet
    if($LASTEXITCODE -ne 0){throw "docker compose config falhou com código $LASTEXITCODE."}
    & docker compose build --pull
    if($LASTEXITCODE -ne 0){throw "Build das imagens falhou com código $LASTEXITCODE."}
    & docker compose up -d --remove-orphans
    if($LASTEXITCODE -ne 0){throw "Inicialização dos serviços falhou com código $LASTEXITCODE."}
    & docker compose ps
    if($LASTEXITCODE -ne 0){throw "Não foi possível consultar o estado do Compose. Código $LASTEXITCODE."}
    Write-Host 'Control Plane iniciado. Aguarde os healthchecks e execute Status-ControlPlane.ps1.' -ForegroundColor Green
}
finally{Pop-Location}
