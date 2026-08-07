﻿#Requires -Version 5.1
[CmdletBinding()]param([switch]$RemoveVolumes)
$ErrorActionPreference='Stop'
$composeDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docker'))
Push-Location $composeDir
try{
    $args=@('compose','down')
    if($RemoveVolumes){
        Write-Warning 'RemoveVolumes apaga os volumes persistentes do PostgreSQL e Caddy. Use apenas após backup confirmado.'
        $args+='--volumes'
    }
    & docker @args
    if($LASTEXITCODE -ne 0){throw "docker compose down falhou com código $LASTEXITCODE."}
}
finally{Pop-Location}
