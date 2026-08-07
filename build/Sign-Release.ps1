#Requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$CertificateThumbprint,
    [string]$RootDirectory = (Split-Path -Parent $PSScriptRoot),
    [string]$TimestampServer = 'http://timestamp.digicert.com'
)
Set-StrictMode -Version 2.0
$ErrorActionPreference='Stop'
$certificate=Get-Item -LiteralPath ('Cert:\CurrentUser\My\'+$CertificateThumbprint) -ErrorAction SilentlyContinue
if(-not $certificate){$certificate=Get-Item -LiteralPath ('Cert:\LocalMachine\My\'+$CertificateThumbprint) -ErrorAction SilentlyContinue}
if(-not $certificate){throw 'Certificado de assinatura não encontrado.'}
if(-not $certificate.HasPrivateKey){throw 'O certificado não possui chave privada.'}
$files=@(Get-ChildItem -LiteralPath $RootDirectory -Recurse -File|Where-Object{$_.Extension -in @('.ps1','.psm1','.psd1')})
foreach($file in $files){
    $signature=Set-AuthenticodeSignature -LiteralPath $file.FullName -Certificate $certificate -HashAlgorithm SHA256 -TimestampServer $TimestampServer
    if($signature.Status -ne 'Valid'){throw "Falha ao assinar $($file.FullName): $($signature.StatusMessage)"}
    Write-Host "Assinado: $($file.FullName)" -ForegroundColor Green
}
Write-Host "Assinatura concluída em $($files.Count) arquivo(s)." -ForegroundColor Green
