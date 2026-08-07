# Deploy do Control Plane 3.0.0-RC em VM Windows + Docker Desktop

## Objetivo

Subir o Control Plane completo em uma VM Windows 11 x64 usando Docker Desktop com backend WSL 2 e containers Linux. A VM hospeda Caddy, MS-A, MS-B, MS-C e PostgreSQL; as máquinas dos clientes mantêm o AutoRunner no Windows e iniciam conexões HTTPS/WSS de saída para a central.

## VM recomendada

Para homologação interna:

- Windows 11 Pro ou Enterprise x64;
- 4 vCPU mínimo, 8 vCPU recomendado;
- 12 GB de RAM mínimo, 16 GB recomendado;
- 100 GB de SSD mínimo;
- IP fixo ou reserva DHCP;
- nested virtualization habilitada no hypervisor se esta máquina for uma VM;
- portas 80/TCP e 443/TCP liberadas para os operadores/agentes que precisarão alcançar a central;
- DNS interno ou público recomendado quando TLS for usado.

Não é necessário instalar Node.js, PostgreSQL ou Caddy nativamente no Windows.

## 1. Preparar WSL 2

Abra PowerShell como administrador:

```powershell
wsl --install
wsl --update
wsl --status
wsl -l -v
```

Reinicie quando solicitado. Em uma VM, se WSL 2 não conseguir criar a VM utilitária, confirme com o administrador do hypervisor que nested virtualization foi exposta ao guest.

## 2. Instalar Docker Desktop

Instale Docker Desktop e use **Linux containers** com o engine WSL 2. Depois valide:

```powershell
docker version
docker compose version
docker run --rm hello-world
```

O usuário operacional deve conseguir executar `docker` sem abrir o Docker Desktop como outro usuário administrativo.

## 3. Extrair o Control Plane

Exemplo:

```powershell
New-Item -ItemType Directory -Force C:\AutoRunner-ControlPlane | Out-Null
Expand-Archive .\SQLBackupAndFTP-AutoRunner-v3.0.0-RC-ControlPlane.zip C:\AutoRunner-ControlPlane -Force
Set-Location C:\AutoRunner-ControlPlane
```

## 4. Criar configuração segura

O pacote contém `deploy\docker\.env.example` e o helper:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\New-ControlPlaneEnv.ps1
```

O script cria `deploy\docker\.env` com segredos aleatórios. Edite os campos operacionais:

```text
PUBLIC_BASE_URL
PUBLIC_WS_URL
AUTORUNNER_SITE_ADDRESS
TRUSTED_ORIGINS
BOOTSTRAP_ADMIN_EMAIL
BOOTSTRAP_ADMIN_PASSWORD
BOOTSTRAP_ORGANIZATION_NAME
```

### Teste LAN sem TLS

Somente para homologação isolada:

```text
PUBLIC_BASE_URL=http://10.0.0.50
PUBLIC_WS_URL=ws://10.0.0.50/ws/agent
AUTORUNNER_SITE_ADDRESS=http://10.0.0.50
TRUSTED_ORIGINS=http://10.0.0.50
```

Ao matricular o agente nesse cenário, marque explicitamente a opção de transporte inseguro. Não use HTTP/WS em produção.

### TLS com DNS

Recomendado:

```text
PUBLIC_BASE_URL=https://autorunner.empresa.com.br
PUBLIC_WS_URL=wss://autorunner.empresa.com.br/ws/agent
AUTORUNNER_SITE_ADDRESS=https://autorunner.empresa.com.br
TRUSTED_ORIGINS=https://autorunner.empresa.com.br
```

Aponte o DNS para a VM e garanta que Caddy consiga obter/renovar certificado quando o endereço for público. Para PKI interna, adapte o Caddyfile/certificados conforme a infraestrutura da empresa.

## 5. Subir a central

Da raiz do pacote:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\Start-ControlPlane.ps1
```

Ou diretamente:

```powershell
docker compose --env-file .\deploy\docker\.env -f .\deploy\docker\docker-compose.yml up -d --build
```

O Compose executa em ordem:

1. PostgreSQL;
2. migração de domínio;
3. migração Better Auth;
4. bootstrap do administrador inicial;
5. MS-A;
6. MS-B;
7. MS-C;
8. Caddy.

Os serviços dependentes aguardam healthcheck/saída bem-sucedida das etapas anteriores.

## 6. Validar

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\Status-ControlPlane.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\Diagnose-ControlPlane.ps1
```

Validações manuais:

```powershell
curl.exe http://SEU_HOST/health/ready
curl.exe http://SEU_HOST/api/v1/version
```

Abra no navegador:

```text
http(s)://SEU_HOST/
http(s)://SEU_HOST/docs
```

Entre com o usuário bootstrap definido no `.env`.

## 7. Matricular um AutoRunner de teste

Na Central:

1. crie cliente/site/máquina conforme necessário;
2. gere um token de enrollment;
3. na máquina Windows do cliente, abra o AutoRunner;
4. clique **Conectar à Central**;
5. informe a URL e o token de enrollment;
6. para HTTP de laboratório, marque transporte inseguro explicitamente;
7. confirme que o agente aparece online e publica inventário/jobs.

O token de enrollment é de uso controlado. A identidade permanente do agente usa segredo próprio protegido localmente por DPAPI `LocalMachine`.

## 8. Backup do Control Plane

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\Backup-ControlPlane.ps1
```

O backup usa `pg_dump`, copia o dump para fora do volume Docker e grava SHA-256. Guarde também o `.env` em cofre seguro, ou use a opção do script que o inclui intencionalmente.

## 9. Restore

Teste restore antes de chamar a central de produção:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\Restore-ControlPlane.ps1 -BackupDirectory C:\CAMINHO\autorunner-control-plane_YYYYMMDD_HHMMSS
```

O restore valida hashes, interrompe os serviços de aplicação, recria a base, usa `pg_restore` e sobe os serviços novamente.

## 10. Atualização da central

Faça backup primeiro e depois:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\deploy\windows\Update-ControlPlane.ps1
```

Para uma RC, prefira testar a atualização em snapshot/clone da VM antes de aplicá-la ao ambiente principal.

## Portas

Externamente o Compose publica apenas:

- `80/TCP`: HTTP e redirecionamento quando aplicável;
- `443/TCP`: HTTPS/WSS;
- `443/UDP`: HTTP/3 do Caddy quando disponível.

PostgreSQL e os três microserviços não publicam portas no host.

## Dados persistentes

Persistem em named volumes Docker:

- `postgres-data`;
- `caddy-data`;
- `caddy-config`.

Não coloque o diretório de dados do PostgreSQL em bind mount NTFS para esta implantação. Named volumes mantêm o caminho de I/O no filesystem Linux do Docker/WSL.

## Gate antes de produção

A 3.0.0-RC só deve avançar depois de testar pelo menos:

- restart da VM;
- restart do Docker Desktop;
- restart do PostgreSQL;
- agente offline durante comando e reconexão;
- execução remota real de job;
- falha de job real e diagnóstico;
- backup e restore do Control Plane;
- revogação de agente;
- rotação/revogação de API key;
- HTTPS/WSS com certificado válido;
- recuperação após perda de rede;
- atualização de uma instalação AutoRunner anterior.
