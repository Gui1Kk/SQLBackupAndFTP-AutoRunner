import Fastify from 'fastify';
import cors from '@fastify/cors';
import helmet from '@fastify/helmet';
import rateLimit from '@fastify/rate-limit';
import swagger from '@fastify/swagger';
import swaggerUi from '@fastify/swagger-ui';
import { fromNodeHeaders } from 'better-auth/node';
import { auth } from './auth.ts';
import { registerRoutes } from './routes.ts';
import { config } from '../../shared/src/config.ts';
import { DomainError } from '../../shared/src/problem.ts';
import { log } from '../../shared/src/logger.ts';

const app=Fastify({logger:false,bodyLimit:1024*1024,trustProxy:true,requestTimeout:30_000,keepAliveTimeout:72_000});
await app.register(cors,{origin:(origin,cb)=>{if(!origin||config.trustedOrigins.includes(origin))cb(null,true);else cb(new Error('Origin não confiável.'),false);},credentials:true,methods:['GET','POST','PATCH','DELETE','OPTIONS'],allowedHeaders:['content-type','authorization','x-api-key','idempotency-key','x-requested-with']});
await app.register(helmet,{global:true,contentSecurityPolicy:false});
await app.register(rateLimit,{global:true,max:300,timeWindow:'1 minute',skipOnError:false});
await app.register(swagger,{mode:'static',specification:{path:'./contracts/openapi.yaml',postProcessor:(document)=>({...document,servers:[{url:config.publicBaseUrl}]})}});
await app.register(swaggerUi,{routePrefix:'/docs',uiConfig:{docExpansion:'list',deepLinking:true}});

app.addHook('onRequest',async(req)=>{req.startedAt=Date.now();});
app.addHook('onResponse',async(req,reply)=>log('info','http_request',{requestId:req.id,method:req.method,url:req.url,statusCode:reply.statusCode,durationMs:Date.now()-(req.startedAt||Date.now()),ip:req.ip}));

app.route({method:['GET','POST'],url:'/api/auth/*',config:{rateLimit:{max:100,timeWindow:'1 minute'}},async handler(request,reply){
  // API-key and organization administration are intentionally exposed only through
  // the Control Plane routes, where our RBAC and organization scoping are enforced.
  const authPath=String(request.url||'').toLowerCase();
  if(authPath.includes('/api-key/')||authPath.includes('/organization/')){
    return reply.code(404).type('application/problem+json').send({type:'urn:autorunner:problem:NOT_FOUND',title:'Recurso não encontrado',status:404,code:'NOT_FOUND'});
  }
  const proto=request.headers['x-forwarded-proto']||'http';
  const host=request.headers.host||'localhost';
  const url=new URL(request.url,`${proto}://${host}`);
  const headers=fromNodeHeaders(request.headers);
  const init={method:request.method,headers};
  if(request.body!==undefined && !['GET','HEAD'].includes(request.method)){init.body=JSON.stringify(request.body);if(!headers.get('content-type'))headers.set('content-type','application/json');}
  const response=await auth.handler(new Request(url,init));
  reply.status(response.status);response.headers.forEach((v,k)=>reply.header(k,v));
  const text=response.body?await response.text():'';return text?reply.send(text):reply.send();
}});

await registerRoutes(app);
app.setNotFoundHandler({preHandler:app.rateLimit({max:30,timeWindow:'1 minute'})},async(_req,reply)=>reply.code(404).type('application/problem+json').send({type:'urn:autorunner:problem:NOT_FOUND',title:'Recurso não encontrado',status:404,code:'NOT_FOUND'}));
app.setErrorHandler(async(error,req,reply)=>{
  if(error instanceof DomainError) return reply.code(error.status).type('application/problem+json').send({type:`urn:autorunner:problem:${error.code}`,title:error.code,status:error.status,code:error.code,detail:error.message,traceId:req.id,...error.meta});
  if(error.validation) return reply.code(400).type('application/problem+json').send({type:'urn:autorunner:problem:VALIDATION_ERROR',title:'Requisição inválida',status:400,code:'VALIDATION_ERROR',detail:error.message,traceId:req.id});
  log('error','unhandled_http_error',{requestId:req.id,error:error.message,stack:config.nodeEnv==='development'?error.stack:undefined});
  return reply.code(500).type('application/problem+json').send({type:'urn:autorunner:problem:INTERNAL_ERROR',title:'Erro interno',status:500,code:'INTERNAL_ERROR',detail:'Falha interna não tratada.',traceId:req.id});
});

const close=async()=>{try{await app.close();}finally{process.exit(0);}};process.on('SIGTERM',close);process.on('SIGINT',close);
await app.listen({host:config.serviceHost,port:config.msAPort});
log('info','service_started',{port:config.msAPort,version:'3.0.0-RC'});
