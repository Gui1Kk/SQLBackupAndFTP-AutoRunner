#Requires -Version 5.1
[CmdletBinding(SupportsShouldProcess=$true,ConfirmImpact='High')]
param(
    [Parameter(Mandatory=$true)][string]$BackupDirectory,
    [switch]$RestoreSecrets,
    [switch]$Force
)
$ErrorActionPreference='Stop'
$composeDir=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\docker'))
$backup=[IO.Path]::GetFullPath($BackupDirectory)
$dump=Join-Path $backup 'postgres.dump'
$sums=Join-Path $backup 'SHA256SUMS.txt'
if(-not(Test-Path -LiteralPath $dump -PathType Leaf)){throw 'postgres.dump não encontrado.'}
if(-not(Test-Path -LiteralPath $sums -PathType Leaf)){throw 'SHA256SUMS.txt não encontrado.'}
foreach($line in @(Get-Content -LiteralPath $sums)){
    if([string]::IsNullOrWhiteSpace($line)){continue}
    if($line -notmatch '^([A-Fa-f0-9]{64})\s+\*(.+)$'){throw "Linha de hash inválida: $line"}
    $file=Join-Path $backup $matches[2]
    if(-not(Test-Path -LiteralPath $file -PathType Leaf)){throw "Arquivo do backup ausente: $($matches[2])"}
    $actual=(Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash
    if($actual -ine $matches[1]){throw "Hash divergente: $($matches[2])"}
}
if(-not $Force -and -not $PSCmdlet.ShouldProcess('Banco PostgreSQL do AutoRunner Control Plane','SUBSTITUIR pelo backup')){return}
Push-Location $composeDir
try{
    if($RestoreSecrets){
        $savedEnv=Join-Path $backup '.env'
        if(-not(Test-Path -LiteralPath $savedEnv -PathType Leaf)){throw 'O backup não contém .env.'}
        Copy-Item -LiteralPath $savedEnv -Destination (Join-Path $composeDir '.env') -Force
    }
    & docker compose stop caddy ms-a ms-b ms-c
    if($LASTEXITCODE -ne 0){throw 'Falha ao parar serviços da aplicação.'}
    & docker compose cp $dump 'postgres:/tmp/autorunner-control-plane.dump'
    if($LASTEXITCODE -ne 0){throw 'Falha ao copiar dump para PostgreSQL.'}
    $restore='set -eu; dropdb -U "$POSTGRES_USER" --if-exists --force "$POSTGRES_DB"; createdb -U "$POSTGRES_USER" "$POSTGRES_DB"; pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --exit-on-error /tmp/autorunner-control-plane.dump; rm -f /tmp/autorunner-control-plane.dump'
    & docker compose exec -T postgres sh -ec $restore
    if($LASTEXITCODE -ne 0){throw "pg_restore falhou com código $LASTEXITCODE."}
    & docker compose up -d ms-a ms-b ms-c caddy
    if($LASTEXITCODE -ne 0){throw 'Banco restaurado, mas os serviços não subiram corretamente.'}
    Write-Host 'Restauração concluída. Execute Status-ControlPlane.ps1 e valide login, agentes e histórico.' -ForegroundColor Green
}
finally{Pop-Location}
