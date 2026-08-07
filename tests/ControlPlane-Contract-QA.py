#!/usr/bin/env python3
from __future__ import annotations
import json,re,sys
from pathlib import Path
import yaml
ROOT=Path(__file__).resolve().parents[1]; RESULTS=[]
def rd(p): return (ROOT/p).read_text(encoding='utf-8-sig')
def add(n,p,d): RESULTS.append({'name':n,'passed':bool(p),'detail':d}); print(f"[{'PASS' if p else 'FAIL'}] {n}: {d}")
version=rd('VERSION').strip(); channel=rd('RELEASE_CHANNEL').strip()
add('Versão 3.0.0-RC',version=='3.0.0' and channel.upper()=='RC',f'{version}-{channel}')
compose=yaml.safe_load(rd('deploy/docker/docker-compose.yml'))
services=compose.get('services',{})
add('Compose contém plano de controle completo',all(x in services for x in ('postgres','domain-migrate','auth-migrate','bootstrap-admin','ms-a','ms-b','ms-c','caddy')),', '.join(services))
exposed=[]
for name,spec in services.items():
    if name!='caddy' and spec.get('ports'): exposed.append(name)
add('Somente Caddy publica portas',not exposed,'nenhum serviço interno publicado' if not exposed else ','.join(exposed))
add('Compose usa health/dependency gates','service_healthy' in rd('deploy/docker/docker-compose.yml') and 'service_completed_successfully' in rd('deploy/docker/docker-compose.yml'),'gates presentes')
dockerignore=rd('.dockerignore')
add('Segredos Docker excluídos do contexto','deploy/docker/.env' in dockerignore and '**/.env' in dockerignore and '**/.env.*' in dockerignore and '!deploy/docker/.env.example' in dockerignore,'env/secrets fora das layers')
caddy=rd('deploy/docker/Caddyfile')
add('Caddy impõe limites de corpo','request_body' in caddy and 'max_size 1MB' in caddy and 'max_size 2MB' in caddy,'limites no edge, inclusive chunked')
add('Caddy aplica headers de segurança',all(x in caddy for x in ('X-Content-Type-Options','X-Frame-Options','Content-Security-Policy')),'headers globais presentes')
add('UI central compatível com CSP sem inline style','style=' not in rd('apps/central-web/index.html').lower() and 'style=' not in rd('apps/central-web/app.js').lower(),'sem style inline')
for svc in ('domain-migrate','auth-migrate','bootstrap-admin','ms-a','ms-b','ms-c'):
    spec=services[svc]
    hardened=spec.get('read_only') is True and 'ALL' in spec.get('cap_drop',[]) and 'no-new-privileges:true' in spec.get('security_opt',[])
    add(f'Container endurecido: {svc}',hardened,'read_only/cap_drop/NNP')
openapi=yaml.safe_load(rd('contracts/openapi.yaml'))
paths=openapi.get('paths',{})
required_paths=['/api/v1/version','/api/v1/clients','/api/v1/machines/{machineId}','/api/v1/jobs','/api/v1/commands/{commandId}','/api/v1/webhooks','/api/v1/realtime/token']
add('OpenAPI cobre recursos principais',all(x in paths for x in required_paths),f'{len(paths)} paths')
add('OpenAPI usa segurança global',bool(openapi.get('security')),'security declarada')
gql=rd('contracts/schema.graphql'); resolvers=rd('services/ms-b-query-events/src/resolvers.ts')
for typename in ('fleetSummary','organizations','clients','machines','jobs','executions','command','audit'):
    add(f'GraphQL expõe {typename}',typename in gql and typename in resolvers,'contrato + resolver')
msb=rd('services/ms-b-query-events/src/server.ts')
for label,tokens in {
 'GraphQL limita profundidade/campos':['graphqlMaxDepth','graphqlMaxFields'],
 'GraphQL limita corpo e taxa':['graphqlMaxBodyBytes','graphqlRequestsPerMinute'],
 'Introspection controlável':['graphqlAllowIntrospection'],
}.items(): add(label,all(t in msb for t in tokens),', '.join(tokens))
msa=rd('services/ms-a-rest/src/server.ts')+rd('services/ms-a-rest/src/routes.ts')+rd('services/ms-a-rest/src/auth.ts')
add('Admin Better Auth sensível passa pelo RBAC do produto','/api-key/' in msa and '/organization/' in msa and '403' in msa,'rotas cruas sensíveis bloqueadas')
add('API keys de organização suportadas','apiKey' in msa and 'permissions' in msa,'plugin/escopo presentes')
authz=rd('services/shared/src/authz.ts')
add('Autenticação aceita headers Fastify e Fetch',all(x in authz for x in ('headerValue','betterAuthHeaders','typeof headers.get')), 'REST e GraphQL compartilham autenticação sem assumir IncomingHttpHeaders')
swagger=rd('services/ms-a-rest/src/server.ts')
add('Swagger serve contrato OpenAPI canônico em modo static','contracts/openapi.yaml' in swagger and "mode:'static'" in swagger.replace(' ',''),'contrato YAML único')
msc=rd('services/ms-c-realtime/src/agent-gateway.ts')+rd('services/ms-c-realtime/src/ui-gateway.ts')+rd('services/ms-c-realtime/src/server.ts')
for label,tokens in {
 'Comandos usam entrega durável/redispatch':['dispatch_attempts','last_dispatch_at','dispatched'],
 'WebSocket UI usa token apenas em subprotocol':['sec-websocket-protocol'],
 'WebSocket valida Origin':['trustedOrigins'],
 'Compressão WS desabilitada':['perMessageDeflate:false'],
 'Upgrade WS tem rate limit':['websocketUpgradesPerMinute'],
 'Revogação fecha conexão':['revoked','close'],
}.items(): add(label,all(t in msc for t in tokens),', '.join(tokens))
agent=rd('agent/remote-control/AutoRunner.RemoteAgent.psm1')
for label,tokens in {
 'Agente é outbound-only':['ClientWebSocket'],
 'Segredo do agente usa DPAPI LocalMachine':['ProtectedData','LocalMachine'],
 'Dedupe local de comandos':['CommandCache','CommandId'],
 'Backup type é allow-list':['Default','Full','FullCopy','Diff','TranLog','TranLogCopy'],
 'Limite de mensagem do agente':['1024 * 1024'],
}.items(): add(label,all(t.lower() in agent.lower() for t in tokens) and not (label=='Agente é outbound-only' and ('HttpListener' in agent or 'TcpListener' in agent)),', '.join(tokens))
core=rd('modules/AutoRunner.Core.psm1')
required_sids=['S-1-5-18','S-1-5-32-544','S-1-5-32-545','S-1-5-11','S-1-1-0','S-1-15-2-1','S-1-15-2-2','S-1-3-0','S-1-3-4']
add('ACL 3.0 exige FullControl para identidades normativas',all(x in core for x in required_sids) and 'Set-AutoRunnerProductFullControlAcl' in core and 'Test-AutoRunnerProductFullControlAcl' in core,'SIDs + aplicação + gate')
add('Scratch privilegiado continua separado da ACL do produto','Set-AutoRunnerPrivateDirectoryAcl' in core or 'Private' in rd('scripts/Setup-Wizard.ps1'),'fronteira transitória separada')
configtxt=rd('services/shared/src/config.ts')
add('Retenção operacional configurável',all(x in configtxt for x in ('EVENT_RETENTION_DAYS','RETENTION_CLEANUP_INTERVAL_SECONDS')) and 'cleanupRetainedOperationalData' in rd('services/ms-b-query-events/src/webhooks.ts'),'outbox/webhook/diagnóstico com cleanup incremental')
add('Gerador .env inclui retenção',all(x in rd('deploy/windows/New-ControlPlaneEnv.ps1') for x in ('EVENT_RETENTION_DAYS=90','RETENTION_CLEANUP_INTERVAL_SECONDS=3600')),'defaults operacionais persistidos no .env gerado')
wh=rd('services/ms-b-query-events/src/webhooks.ts')
for label,tokens in {
 'Webhook assina HMAC':['hmac','signature'],
 'Webhook não segue redirect automaticamente':['transport.request'],
 'Webhook faz resolução DNS e pinning':['lookup','address'],
 'Webhook limita timeout/tamanho':['webhookTimeoutMs','max'],
}.items(): add(label,all(t.lower() in wh.lower() for t in tokens),', '.join(tokens))
sql=rd('deploy/postgres/init/001_control_plane.sql')
add('Histórico de identidade preserva agentes revogados','uq_ar_agents_active_install_id' in sql and 'WHERE revoked_at IS NULL' in sql,'unicidade somente para identidade ativa')
add('Outbox transacional presente','CREATE TABLE IF NOT EXISTS ar_outbox' in sql and 'pg_notify' in rd('services/shared/src/events.ts'),'DB + wake-up')
# No direct manipulation of vendor DB in new services/agent
newcode='\n'.join(rd(p.relative_to(ROOT)) for p in [*ROOT.glob('services/**/*.ts'),*ROOT.glob('agent/remote-control/*.ps*')])
add('Sem escrita direta no context.db do SQLBackupAndFTP','context.db' not in newcode.lower() or not re.search(r'(?i)(insert|update|delete).*context\.db',newcode),'nenhuma mutação do DB interno do fornecedor')
for rel in ['deploy/windows/Backup-ControlPlane.ps1','deploy/windows/Restore-ControlPlane.ps1']:
    txt=rd(rel)
    add(f'Operação de dados presente: {Path(rel).name}',('pg_dump' in txt if 'Backup' in rel else 'pg_restore' in txt) and 'SHA256' in txt,'dump/restore + hash')
# No empty implementation files anymore
impl=[*ROOT.glob('services/**/*.ts'),*ROOT.glob('agent/remote-control/*.ps1'),*ROOT.glob('agent/remote-control/*.psm1'),ROOT/'contracts/openapi.yaml',ROOT/'contracts/schema.graphql']
empty=[str(x.relative_to(ROOT)) for x in impl if x.stat().st_size==0]
add('Implementação 3.0 não contém placeholders vazios',not empty,'nenhum' if not empty else ', '.join(empty))
report={'tool':'ControlPlane-Contract-QA.py','passed':sum(r['passed'] for r in RESULTS),'failed':sum(not r['passed'] for r in RESULTS),'results':RESULTS}
(ROOT/'test-results').mkdir(exist_ok=True)
(ROOT/'test-results/control-plane-contract.json').write_text(json.dumps(report,ensure_ascii=False,indent=2),encoding='utf-8')
sys.exit(1 if report['failed'] else 0)
