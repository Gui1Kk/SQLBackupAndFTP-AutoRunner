import { buildRestApp } from './app.ts';
import { config } from '../../shared/src/config.ts';
import { log } from '../../shared/src/logger.ts';

const app=await buildRestApp();
const close=async()=>{try{await app.close();}finally{process.exit(0);}};
process.on('SIGTERM',close);
process.on('SIGINT',close);
await app.listen({host:config.serviceHost,port:config.msAPort});
log('info','service_started',{port:config.msAPort,version:'3.0.1'});
