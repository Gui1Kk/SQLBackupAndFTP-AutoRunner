const $=(q)=>document.querySelector(q);
const $$=(q)=>[...document.querySelectorAll(q)];
const state={me:null,summary:null,organizations:[],clients:[],machines:[],socket:null};
const esc=(v)=>String(v??'').replace(/[&<>'"]/g,(c)=>({'&':'&amp;','<':'&lt;','>':'&gt;',"'":'&#39;','"':'&quot;'}[c]));
const toast=(message,ms=3500)=>{const el=$('#toast');el.textContent=message;el.classList.remove('hidden');clearTimeout(toast.timer);toast.timer=setTimeout(()=>el.classList.add('hidden'),ms);};

async function json(url,options={}){
  const headers={accept:'application/json',...(options.headers||{})};
  if(options.body!==undefined&&!headers['content-type'])headers['content-type']='application/json';
  const response=await fetch(url,{...options,headers,credentials:'same-origin'});
  const text=await response.text();let body=null;
  try{body=text?JSON.parse(text):null;}catch{body=text;}
  if(!response.ok){const detail=body?.detail||body?.message||body?.title||text||`HTTP ${response.status}`;const error=new Error(detail);error.status=response.status;error.body=body;throw error;}
  return body;
}
async function gql(query,variables={}){const result=await json('/graphql',{method:'POST',body:JSON.stringify({query,variables})});if(result.errors?.length)throw new Error(result.errors[0].message);return result.data;}
async function session(){try{const x=await json('/api/auth/get-session',{method:'GET'});return x?.user?x:null}catch{return null;}}
function status(v){return `<span class="status ${esc(v)}">${esc(v||'n/d')}</span>`;}
function table(headers,rows){if(!rows.length)return '<div class="empty">Nenhum registro.</div>';return `<div class="table-wrap"><table><thead><tr>${headers.map((h)=>`<th>${esc(h)}</th>`).join('')}</tr></thead><tbody>${rows.join('')}</tbody></table></div>`;}
function formatDate(value){if(!value)return '-';try{return new Date(value).toLocaleString('pt-BR');}catch{return String(value);}}

async function login(event){event.preventDefault();$('#loginError').textContent='';try{await json('/api/auth/sign-in/email',{method:'POST',body:JSON.stringify({email:$('#email').value,password:$('#password').value})});await boot();}catch(error){$('#loginError').textContent=error.message;}}
async function logout(){try{await json('/api/auth/sign-out',{method:'POST',body:'{}'});}catch{}location.reload();}
function view(name){
  $$('.view').forEach((x)=>x.classList.add('hidden'));$(`#${name}View`)?.classList.remove('hidden');$$('.nav').forEach((x)=>x.classList.toggle('active',x.dataset.view===name));
  const map={dashboard:['Visão geral','Frota, backups e saúde operacional.'],clients:['Clientes','Organizações atendidas e máquinas vinculadas.'],machines:['Máquinas e jobs','Inventário recebido dos agentes.'],commands:['Comandos','Execuções remotas e seus resultados.'],enrollment:['Enrollment','Conecte uma instalação do AutoRunner ao Control Plane.'],webhooks:['Integrações','Webhooks e credenciais para outras aplicações.']};
  $('#title').textContent=map[name]?.[0]||name;$('#subtitle').textContent=map[name]?.[1]||'';
}

async function load(){
  const query=`query Dashboard{
    fleetSummary{organizations clients machines agentsOnline agentsOffline jobs failures24h pendingCommands}
    organizations{id name slug status createdAt}
    clients(first:100){edges{node{id organizationId code name status machinesTotal jobsTotal agentsOnline}}}
    machines(first:150){edges{node{id clientId displayName hostname osName osVersion architecture agent{id status version channel capabilities lastSeenAt} sqlBackup{present appVersion cliVersion installPath serviceStatus} jobs{id name isScheduled scheduleState lastNativeRunAt source confidence} lastExecution{id status startedAt summary exitCode}}}}
  }`;
  const data=await gql(query);state.summary=data.fleetSummary;state.organizations=data.organizations||[];state.clients=data.clients.edges.map((x)=>x.node);state.machines=data.machines.edges.map((x)=>x.node);render();populateSelectors();
}
function render(){
  const s=state.summary||{};
  $('#summary').innerHTML=[['Clientes',s.clients],['Máquinas',s.machines],['Agentes online',s.agentsOnline],['Jobs',s.jobs],['Falhas 24h',s.failures24h],['Comandos pendentes',s.pendingCommands],['Agentes offline',s.agentsOffline],['Organizações',s.organizations]].map(([name,value])=>`<div class="panel metric"><small>${esc(name)}</small><b>${esc(value??0)}</b></div>`).join('');
  renderClients();renderMachines();
  const rows=state.machines.slice(0,10).map((m)=>`<tr class="clickable" data-machine="${m.id}"><td>${esc(m.displayName)}</td><td>${esc(m.hostname)}</td><td>${status(m.agent?.status||'offline')}</td><td>${m.sqlBackup?.present?'Sim':'Não'}</td><td>${m.jobs.length}</td></tr>`);
  $('#dashboardMachines').innerHTML=table(['Máquina','Host','Agente','SQLBackup','Jobs'],rows);bindMachineRows();
  const failures=state.machines.filter((m)=>m.lastExecution?.status==='failed').map((m)=>`<tr class="clickable" data-machine="${m.id}"><td>${esc(m.displayName)}</td><td>${status('failed')}</td><td>${esc(m.lastExecution?.summary||'Sem resumo')}</td></tr>`);
  $('#failures').innerHTML=table(['Máquina','Status','Resumo'],failures.slice(0,20));bindMachineRows();
}
function orgName(id){return state.organizations.find((x)=>x.id===id)?.name||id;}
function clientName(id){return state.clients.find((x)=>x.id===id)?.name||id;}
function renderClients(){const rows=state.clients.map((c)=>`<tr><td>${esc(orgName(c.organizationId))}</td><td>${esc(c.code||'')}</td><td>${esc(c.name)}</td><td>${status(c.status)}</td><td>${c.machinesTotal}</td><td>${c.agentsOnline}</td><td>${c.jobsTotal}</td><td><button class="small ghost copy" data-copy="${c.id}">ID</button></td></tr>`);$('#clientsTable').innerHTML=table(['Organização','Código','Cliente','Status','Máquinas','Online','Jobs',''],rows);$$('.copy').forEach((b)=>b.onclick=()=>navigator.clipboard.writeText(b.dataset.copy).then(()=>toast('ID copiado.')));}
function renderMachines(){const rows=state.machines.map((m)=>`<tr class="clickable" data-machine="${m.id}"><td>${esc(clientName(m.clientId))}</td><td>${esc(m.displayName)}</td><td>${esc(m.hostname||'')}</td><td>${status(m.agent?.status||'offline')}</td><td>${esc(m.agent?.version||'')}</td><td>${m.sqlBackup?.present?esc(m.sqlBackup.appVersion||'Detectado'):'Não detectado'}</td><td>${m.jobs.length}</td><td>${m.lastExecution?status(m.lastExecution.status):'-'}</td></tr>`);$('#machinesTable').innerHTML=table(['Cliente','Máquina','Hostname','Agente','Versão','SQLBackup','Jobs','Último backup'],rows);bindMachineRows();}
function bindMachineRows(){$$('[data-machine]').forEach((row)=>row.onclick=()=>openMachine(row.dataset.machine));}
function populateSelectors(){
  const orgOptions=state.organizations.map((o)=>`<option value="${o.id}">${esc(o.name)}</option>`).join('');
  $('#enrollOrg').innerHTML=orgOptions;$('#integrationOrg').innerHTML=orgOptions;
  updateEnrollmentClients();
}
function updateEnrollmentClients(){const org=$('#enrollOrg').value;$('#enrollClient').innerHTML=state.clients.filter((c)=>!org||c.organizationId===org).map((c)=>`<option value="${c.id}">${esc(c.name)}${c.code?` (${esc(c.code)})`:''}</option>`).join('');}

async function openMachine(id){
  const m=state.machines.find((x)=>x.id===id);if(!m)return;
  $('#modalBody').innerHTML=`<h2>${esc(m.displayName)}</h2><p class="muted">${esc(m.hostname||'')} · Agent ${esc(m.agent?.version||'não conectado')} · ${esc(m.osName||'Windows')} ${esc(m.osVersion||'')}</p><div class="cards"><div class="panel metric"><small>Agente</small><b class="metric-small">${status(m.agent?.status||'offline')}</b></div><div class="panel metric"><small>SQLBackupAndFTP</small><b class="metric-small">${m.sqlBackup?.present?esc(m.sqlBackup.appVersion||'Detectado'):'Ausente'}</b></div></div><div class="panel-title"><h3>Jobs</h3><button id="refreshMachine" class="ghost small" ${m.agent?'':'disabled'}>Atualizar inventário</button></div><div class="job-list">${m.jobs.map((j)=>`<div class="job"><div><strong>${esc(j.name)}</strong><div class="muted">${j.isScheduled?'Agendado':'Manual/indeterminado'} · ${esc(j.source||'')}</div></div><div><select id="type-${j.id}"><option>Default</option><option>Full</option><option>FullCopy</option><option>Diff</option><option>TranLog</option><option>TranLogCopy</option></select><button class="primary small run-job" data-job="${j.id}" ${m.agent?.status==='online'?'':'disabled'}>Executar</button></div></div>`).join('')||'<div class="empty">Nenhum job inventariado.</div>'}</div>`;
  $('#modal').classList.remove('hidden');$$('.run-job').forEach((b)=>b.onclick=()=>runJob(b.dataset.job,$(`#type-${b.dataset.job}`).value));if($('#refreshMachine'))$('#refreshMachine').onclick=()=>command(`/api/v1/agents/${m.agent.id}/inventory-refresh`,{}).then(()=>toast('Atualização de inventário enfileirada.')).catch((e)=>toast(e.message,6000));
}
async function command(url,payload){return json(url,{method:'POST',headers:{'Idempotency-Key':crypto.randomUUID()},body:JSON.stringify(payload)});}
async function runJob(id,backupType){try{const r=await command(`/api/v1/jobs/${id}/executions`,{backupType});toast(`Comando ${r.commandId} enfileirado.`);$('#modal').classList.add('hidden');}catch(e){toast(e.message,6000);}}
async function loadCommands(){try{const data=await gql(`query{executions(first:100){edges{node{id jobId machineId commandId source backupType status startedAt completedAt exitCode summary}}}}`);const rows=data.executions.edges.map(({node:e})=>`<tr><td>${esc(e.commandId||'-')}</td><td>${esc(e.backupType||'')}</td><td>${status(e.status)}</td><td>${esc(formatDate(e.startedAt))}</td><td>${esc(e.exitCode??'')}</td><td>${esc(e.summary||'')}</td></tr>`);$('#commandsTable').innerHTML=table(['Command','Tipo','Status','Início','Exit','Resumo'],rows);}catch(e){$('#commandsTable').innerHTML=`<div class="error">${esc(e.message)}</div>`;}}

async function enrollment(event){event.preventDefault();try{const result=await json('/api/v1/agents/enrollments',{method:'POST',body:JSON.stringify({organizationId:$('#enrollOrg').value,clientId:$('#enrollClient').value,label:$('#enrollLabel').value,ttlSeconds:1800})});$('#enrollResult').textContent=`URL da Central: ${location.origin}\nToken: ${result.token}\n\nNo cliente: AutoRunner → Conectar à Central.\nCole esses dois valores.\n\nExpira: ${formatDate(result.expires_at||result.expiresAt)}`;toast('Token de enrollment criado.');}catch(error){toast(error.message,6000);}}

function formModal(title,html,onSubmit){
  $('#modalBody').innerHTML=`<h2>${esc(title)}</h2><form id="dynamicForm">${html}<div class="inline-actions"><button type="submit" class="primary">Salvar</button><button type="button" id="dynamicCancel" class="ghost">Cancelar</button></div></form>`;$('#modal').classList.remove('hidden');$('#dynamicCancel').onclick=()=>$('#modal').classList.add('hidden');$('#dynamicForm').onsubmit=async(event)=>{event.preventDefault();try{const close=await onSubmit(new FormData(event.currentTarget));if(close!==false)$('#modal').classList.add('hidden');await load();}catch(error){toast(error.message,6000);}};
}
function openNewOrganization(){formModal('Nova organização',`<label>Nome<input name="name" minlength="2" maxlength="200" required></label>`,async(fd)=>{await json('/api/v1/organizations',{method:'POST',body:JSON.stringify({name:fd.get('name')})});toast('Organização criada.');});}
function openNewClient(){if(!state.organizations.length){toast('Crie uma organização primeiro.');return;}const options=state.organizations.map((o)=>`<option value="${o.id}">${esc(o.name)}</option>`).join('');formModal('Novo cliente',`<label>Organização<select name="organizationId" required>${options}</select></label><label>Código<input name="code" maxlength="100"></label><label>Nome<input name="name" minlength="2" maxlength="200" required></label>`,async(fd)=>{await json('/api/v1/clients',{method:'POST',body:JSON.stringify({organizationId:fd.get('organizationId'),code:fd.get('code')||null,name:fd.get('name')})});toast('Cliente criado.');});}
function openNewWebhook(){if(!state.organizations.length)return;const options=state.organizations.map((o)=>`<option value="${o.id}">${esc(o.name)}</option>`).join('');formModal('Novo webhook',`<label>Organização<select name="organizationId" required>${options}</select></label><label>Nome<input name="name" maxlength="100" required></label><label>URL HTTPS<input name="url" type="url" placeholder="https://sistema.exemplo/webhooks/autorunner" required></label><label>Eventos (separados por vírgula)<input name="events" placeholder="execution.completed,agent.offline"></label>`,async(fd)=>{const eventTypes=String(fd.get('events')||'').split(',').map((x)=>x.trim()).filter(Boolean);const result=await json('/api/v1/webhooks',{method:'POST',body:JSON.stringify({organizationId:fd.get('organizationId'),name:fd.get('name'),url:fd.get('url'),eventTypes})});$('#modalBody').innerHTML=`<h2>Webhook criado</h2><p class="danger-text"><strong>Guarde o segredo HMAC agora.</strong> Ele não será exibido novamente.</p><div class="secret-box">${esc(result.secret)}</div><div class="inline-actions spaced-top"><button id="copySecret" class="primary">Copiar</button><button id="closeSecret" class="ghost">Fechar</button></div>`;$('#copySecret').onclick=()=>navigator.clipboard.writeText(result.secret).then(()=>toast('Segredo copiado.'));$('#closeSecret').onclick=()=>$('#modal').classList.add('hidden');toast('Webhook criado.');await loadIntegrations();return false;});}
function openNewApiKey(){if(!state.organizations.length)return;const org=$('#integrationOrg').value||state.organizations[0].id;formModal('Nova API Key',`<input type="hidden" name="organizationId" value="${esc(org)}"><label>Nome<input name="name" value="AlphaExpress" maxlength="100" required></label><label>Finalidade<input name="purpose" value="integracao" maxlength="100"></label><label><span><input name="execute" type="checkbox" checked class="check-inline"> Permitir executar jobs remotamente</span></label>`,async(fd)=>{const permissions={clients:['read'],machines:['read'],jobs:['read'],executions:['read']};if(fd.get('execute'))permissions.jobs.push('execute');const result=await json('/api/v1/integrations/api-keys',{method:'POST',body:JSON.stringify({organizationId:fd.get('organizationId'),name:fd.get('name'),purpose:fd.get('purpose'),permissions})});$('#modalBody').innerHTML=`<h2>API Key criada</h2><p class="danger-text"><strong>Copie agora.</strong> O segredo não será exibido novamente.</p><div class="secret-box">${esc(result.key)}</div><div class="inline-actions spaced-top"><button id="copySecret" class="primary">Copiar</button><button id="closeSecret" class="ghost">Fechar</button></div>`;$('#copySecret').onclick=()=>navigator.clipboard.writeText(result.key).then(()=>toast('API Key copiada.'));$('#closeSecret').onclick=()=>$('#modal').classList.add('hidden');await loadIntegrations();return false;});}

async function loadIntegrations(){
  try{
    const wh=await json('/api/v1/webhooks');
    $('#webhooksTable').innerHTML=table(['Nome','URL','Eventos','Status',''],(wh.items||[]).map((w)=>`<tr><td>${esc(w.name)}</td><td>${esc(w.url)}</td><td>${esc((w.event_types||[]).join(', ')||'todos')}</td><td>${status(w.enabled?'online':'offline')}</td><td><button class="small ghost delete-webhook" data-id="${w.id}">Remover</button></td></tr>`));
    $$('.delete-webhook').forEach((b)=>b.onclick=async()=>{if(!confirm('Remover este webhook?'))return;try{await json(`/api/v1/webhooks/${b.dataset.id}`,{method:'DELETE'});await loadIntegrations();}catch(e){toast(e.message,6000);}});
    const org=$('#integrationOrg').value||state.organizations[0]?.id;if(!org){$('#apiKeysTable').innerHTML='<div class="empty">Nenhuma organização.</div>';return;}
    const keys=await json(`/api/v1/integrations/api-keys?organizationId=${encodeURIComponent(org)}`);
    $('#apiKeysTable').innerHTML=table(['Nome','Prefixo','Criada','Último uso',''],(keys.items||[]).map((k)=>`<tr><td>${esc(k.name||'Integração')}</td><td>${esc(k.prefix||k.start||'ar_')}</td><td>${esc(formatDate(k.createdAt))}</td><td>${esc(formatDate(k.lastRequest))}</td><td><button class="small ghost delete-key" data-id="${k.id}">Revogar</button></td></tr>`));
    $$('.delete-key').forEach((b)=>b.onclick=async()=>{if(!confirm('Revogar permanentemente esta API Key?'))return;try{await json(`/api/v1/integrations/api-keys/${b.dataset.id}?organizationId=${encodeURIComponent(org)}`,{method:'DELETE'});await loadIntegrations();}catch(e){toast(e.message,6000);}});
  }catch(error){$('#webhooksTable').innerHTML=`<div class="error">${esc(error.message)}</div>`;$('#apiKeysTable').innerHTML=`<div class="error">${esc(error.message)}</div>`;}
}

async function realtime(){
  try{
    const r=await json('/api/v1/realtime/token',{method:'POST',body:'{}'});const url=new URL(r.url,location.href);if(url.protocol==='ws:'&&location.protocol==='https:')url.protocol='wss:';url.searchParams.delete('token');const ws=new WebSocket(url,['autorunner-ui',`token.${r.token}`]);state.socket=ws;
    ws.onopen=()=>{$('#connectionDot').classList.add('online');$('#connectionText').textContent='Realtime conectado';};
    ws.onclose=()=>{$('#connectionDot').classList.remove('online');$('#connectionText').textContent='Reconectando...';if(state.socket===ws)setTimeout(realtime,3000);};
    ws.onmessage=async(event)=>{try{const message=JSON.parse(event.data);if(message.type==='event'&&/^(agent\.|inventory\.|execution\.|command\.)/.test(message.payload?.event_type||''))await load();}catch{}};
  }catch{setTimeout(realtime,5000);}
}
async function boot(){const s=await session();if(!s){$('#login').classList.remove('hidden');$('#app').classList.add('hidden');return;}state.me=s;$('#login').classList.add('hidden');$('#app').classList.remove('hidden');$('#userBadge').textContent=s.user.email||s.user.name;await load();realtime();}

$('#loginForm').addEventListener('submit',login);$('#logout').onclick=logout;$('#refresh').onclick=()=>load().catch((e)=>toast(e.message));$('#modalClose').onclick=()=>$('#modal').classList.add('hidden');$('#modal').onclick=(e)=>{if(e.target===$('#modal'))$('#modal').classList.add('hidden');};$('#enrollForm').addEventListener('submit',enrollment);$('#enrollOrg').onchange=updateEnrollmentClients;$('#integrationOrg').onchange=()=>loadIntegrations();$('#newOrganization').onclick=openNewOrganization;$('#newClient').onclick=openNewClient;$('#newWebhook').onclick=openNewWebhook;$('#newApiKey').onclick=openNewApiKey;
$$('.nav').forEach((button)=>button.onclick=async()=>{view(button.dataset.view);if(button.dataset.view==='commands')await loadCommands();if(button.dataset.view==='webhooks')await loadIntegrations();});
boot();
