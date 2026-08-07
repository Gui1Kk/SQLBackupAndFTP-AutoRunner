[CmdletBinding()]param([string]$PublicBaseUrl='http://localhost',[string]$AdminEmail='admin@example.local')
$ErrorActionPreference='Stop'
function Secret([int]$Bytes=48){$b=New-Object byte[] $Bytes;[Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b);[Convert]::ToBase64String($b).TrimEnd('=').Replace('+','-').Replace('/','_')}
$ws=if($PublicBaseUrl.StartsWith('https://')){$PublicBaseUrl -replace '^https://','wss://'}else{$PublicBaseUrl -replace '^http://','ws://'}
$site=$PublicBaseUrl
$envText=@"
PUBLIC_BASE_URL=$PublicBaseUrl
PUBLIC_WS_URL=$ws/ws/agent
AUTORUNNER_SITE_ADDRESS=$site
TRUSTED_ORIGINS=$PublicBaseUrl
POSTGRES_DB=autorunner
POSTGRES_USER=autorunner
POSTGRES_PASSWORD=$(Secret 36)
BETTER_AUTH_SECRET=$(Secret 48)
AGENT_SECRET_PEPPER=$(Secret 48)
REALTIME_SIGNING_SECRET=$(Secret 48)
INTERNAL_SERVICE_SECRET=$(Secret 48)
WEBHOOK_ENCRYPTION_KEY=$(Secret 48)
BOOTSTRAP_ADMIN_EMAIL=$AdminEmail
BOOTSTRAP_ADMIN_PASSWORD=$(Secret 24)
BOOTSTRAP_ADMIN_NAME=Administrador
BOOTSTRAP_ORGANIZATION_NAME=Alpha Software
HTTP_PORT=80
HTTPS_PORT=443
COMMAND_DEFAULT_TTL_SECONDS=900
COMMAND_MAX_RUNNING_SECONDS=86400
MAX_AGENT_MESSAGE_BYTES=1048576
MAX_CLI_OUTPUT_BYTES=65536
GRAPHQL_MAX_DEPTH=10
GRAPHQL_MAX_FIELDS=250
GRAPHQL_MAX_BODY_BYTES=1048576
GRAPHQL_REQUESTS_PER_MINUTE=300
GRAPHQL_ALLOW_INTROSPECTION=false
WEBSOCKET_UPGRADES_PER_MINUTE=120
APPROVED_AGENT_VERSION=3.0.0-RC
HEARTBEAT_INTERVAL_SECONDS=30
OFFLINE_AFTER_SECONDS=90
WEBHOOK_TIMEOUT_MS=8000
WEBHOOK_MAX_ATTEMPTS=8
EVENT_RETENTION_DAYS=90
RETENTION_CLEANUP_INTERVAL_SECONDS=3600
WEBHOOK_ALLOWED_HOSTS=
WEBHOOK_ALLOW_HTTP=false
"@
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'docker\.env'
[IO.File]::WriteAllText($path,$envText,(New-Object Text.UTF8Encoding($false)))
Write-Host "Arquivo criado: $path" -ForegroundColor Green
Write-Warning 'A senha bootstrap foi gerada no .env. Leia-a e guarde-a em cofre de senhas antes do primeiro deploy.'
