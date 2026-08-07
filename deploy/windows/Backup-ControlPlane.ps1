#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$Destination=(Join-Path $PSScriptRoot '..\backups'),
    [switch]$IncludeSecrets
)
$ErrorActionPreference='Stop'
$composeDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docker'))
New-Item -ItemType Directory -Path $Destination -Force|Out-Null
$stamp=Get-Date -Format yyyyMMdd_HHmmss
$backupDir=Join-Path ([IO.Path]::GetFullPath($Destination)) ("autorunner-control-plane_"+$stamp)
New-Item -ItemType Directory -Path $backupDir -Force|Out-Null
$remote='/tmp/autorunner-control-plane.dump'
$local=Join-Path $backupDir 'postgres.dump'
Push-Location $composeDir
try{
    & docker compose exec -T postgres sh -ec 'pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" --format=custom --compress=9 -f /tmp/autorunner-control-plane.dump'
    if($LASTEXITCODE -ne 0){throw "pg_dump falhou com código $LASTEXITCODE."}
    & docker compose cp ("postgres:"+$remote) $local
    if($LASTEXITCODE -ne 0 -or -not(Test-Path -LiteralPath $local -PathType Leaf)){throw 'Não foi possível copiar o dump do PostgreSQL.'}
    & docker compose exec -T postgres rm -f $remote | Out-Null
    if($IncludeSecrets){
        $envPath=Join-Path $composeDir '.env'
        if(-not(Test-Path -LiteralPath $envPath -PathType Leaf)){throw '.env não encontrado para backup de desastre.'}
        Copy-Item -LiteralPath $envPath -Destination (Join-Path $backupDir '.env') -Force
    }
    $files=@(Get-ChildItem -LiteralPath $backupDir -File)
    $manifest=@()
    foreach($file in $files){$manifest += ('{0} *{1}' -f ((Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToUpperInvariant()),$file.Name)}
    [IO.File]::WriteAllLines((Join-Path $backupDir 'SHA256SUMS.txt'),$manifest,(New-Object Text.UTF8Encoding($false)))
    Write-Host "Backup concluído: $backupDir" -ForegroundColor Green
    if(-not $IncludeSecrets){Write-Warning 'O dump foi criado sem o .env. Para recuperação completa de desastre, guarde também os segredos usando -IncludeSecrets em armazenamento protegido.'}
}
finally{try{& docker compose exec -T postgres rm -f $remote 2>$null|Out-Null}catch{};Pop-Location}
