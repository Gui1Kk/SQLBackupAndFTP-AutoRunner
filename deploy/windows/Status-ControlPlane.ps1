﻿#Requires -Version 5.1
[CmdletBinding()]param([int]$Tail=80)
$ErrorActionPreference='Stop'
$composeDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docker'))
Push-Location $composeDir
try{
    & docker compose ps
    if($LASTEXITCODE -ne 0){throw "docker compose ps falhou com código $LASTEXITCODE."}
    & docker compose logs --no-color --tail=$Tail ms-a ms-b ms-c caddy
    if($LASTEXITCODE -ne 0){throw "docker compose logs falhou com código $LASTEXITCODE."}
}
finally{Pop-Location}
