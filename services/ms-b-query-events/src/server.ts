import http from 'node:http';
import { GraphQLError, Kind, NoSchemaIntrospectionCustomRule } from 'graphql';
import { createSchema, createYoga } from 'graphql-yoga';
import { resolvers, typeDefs } from './resolvers.ts';
import { databaseReady, pool } from '../../shared/src/db.ts';
import { config } from '../../shared/src/config.ts';
import { log } from '../../shared/src/logger.ts';
import { startWebhookWorkers } from './webhooks.ts';

process.env.SERVICE_NAME='ms-b-query-events';
const abort = new AbortController();
const requestWindows = new Map();
function requestIp(req){const forwarded=String(req.headers['x-forwarded-for']||'').split(',')[0].trim();return forwarded||req.socket.remoteAddress||'unknown';}
function allowRequest(ip,limit){const now=Date.now();const current=requestWindows.get(ip);if(!current||now-current.startedAt>=60_000){requestWindows.set(ip,{startedAt:now,count:1});return true;}current.count+=1;return current.count<=limit;}
const requestWindowGc=setInterval(()=>{const cutoff=Date.now()-120_000;for(const [key,value] of requestWindows)if(value.startedAt<cutoff)requestWindows.delete(key);},60_000);requestWindowGc.unref?.();

function operationBudgetRule(maxDepth,maxFields){
  return (context)=>({
    Document(node){
      const fragments=new Map(node.definitions.filter((d)=>d.kind===Kind.FRAGMENT_DEFINITION).map((d)=>[d.name.value,d]));
      const operations=node.definitions.filter((d)=>d.kind===Kind.OPERATION_DEFINITION);
      for(const operation of operations){
        let fields=0; let deepest=0; const fragmentStack=new Set();
        const walk=(selectionSet,depth)=>{
          if(!selectionSet)return;
          deepest=Math.max(deepest,depth);
          if(deepest>maxDepth||fields>maxFields)return;
          for(const selection of selectionSet.selections){
            if(selection.kind===Kind.FIELD){fields+=1;walk(selection.selectionSet,depth+1);}
            else if(selection.kind===Kind.INLINE_FRAGMENT){walk(selection.selectionSet,depth+1);}
            else if(selection.kind===Kind.FRAGMENT_SPREAD){
              const name=selection.name.value;
              if(fragmentStack.has(name))continue;
              const fragment=fragments.get(name);
              if(fragment){fragmentStack.add(name);walk(fragment.selectionSet,depth+1);fragmentStack.delete(name);}
            }
            if(deepest>maxDepth||fields>maxFields)return;
          }
        };
        walk(operation.selectionSet,1);
        if(deepest>maxDepth)context.reportError(new GraphQLError(`Consulta excede profundidade máxima ${maxDepth}.`,{nodes:[operation]}));
        if(fields>maxFields)context.reportError(new GraphQLError(`Consulta excede limite de ${maxFields} campos.`,{nodes:[operation]}));
      }
    },
  });
}

const validationPlugin={
  onValidate({addValidationRule}){
    addValidationRule(operationBudgetRule(config.graphqlMaxDepth,config.graphqlMaxFields));
    if(config.nodeEnv==='production'&&!config.graphqlAllowIntrospection)addValidationRule(NoSchemaIntrospectionCustomRule);
  },
};

const yoga=createYoga({
  schema:createSchema({typeDefs,resolvers}),
  graphqlEndpoint:'/graphql',
  graphiql: config.nodeEnv !== 'production',
  maskedErrors: config.nodeEnv === 'production',
  context:({request})=>({request,signal:request.signal}),
  cors:{origin:config.trustedOrigins,credentials:true,allowedHeaders:['content-type','authorization','x-api-key']},
  plugins:[validationPlugin],
});

const server=http.createServer(async(req,res)=>{
  if(req.url==='/health/live'){res.writeHead(200,{'content-type':'application/json'});return res.end(JSON.stringify({status:'ok',service:'ms-b'}));}
  if(req.url==='/health/ready'){const ok=await databaseReady();res.writeHead(ok?200:503,{'content-type':'application/json'});return res.end(JSON.stringify({status:ok?'ready':'not-ready'}));}
  if(!String(req.url||'').startsWith('/graphql')){res.writeHead(404);return res.end();}
  const contentLength=Number(req.headers['content-length']||0);
  if(Number.isFinite(contentLength)&&contentLength>config.graphqlMaxBodyBytes){res.writeHead(413,{'content-type':'application/json'});return res.end(JSON.stringify({errors:[{message:'Corpo GraphQL excede o limite permitido.'}]}));}
  if(!allowRequest(requestIp(req),config.graphqlRequestsPerMinute)){res.writeHead(429,{'content-type':'application/json','retry-after':'60'});return res.end(JSON.stringify({errors:[{message:'Limite de requisições excedido.'}]}));}
  return yoga(req,res);
});
startWebhookWorkers(abort.signal);
server.listen(config.msBPort,config.serviceHost,()=>log('info','ms_b_listening',{port:config.msBPort}));
async function shutdown(signal){log('info','shutdown',{signal});abort.abort();clearInterval(requestWindowGc);await new Promise((resolve)=>server.close(resolve));await pool.end();process.exit(0);}
for(const sig of ['SIGTERM','SIGINT'])process.on(sig,()=>shutdown(sig));
