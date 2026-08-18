import { buildRestApp } from '../services/ms-a-rest/src/app.ts';

let appPromise;
function getApp(){
  if(!appPromise) appPromise=buildRestApp();
  return appPromise;
}

export default async function handler(req,res){
  const app=await getApp();
  app.server.emit('request',req,res);
}
