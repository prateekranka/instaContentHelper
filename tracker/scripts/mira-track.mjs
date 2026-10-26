import {readFile,writeFile,mkdir,readdir,unlink} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {resolve} from 'node:path';
const queue=resolve(import.meta.dirname,'../../work/tracker-pending');await mkdir(queue,{recursive:true});
const [command,file]=process.argv.slice(2);
if(command==='update'){
 if(!file)throw Error('Usage: node tracker/scripts/mira-track.mjs update mutation.json');
 const payload=JSON.parse(await readFile(file,'utf8'));const key=randomUUID();
 await writeFile(resolve(queue,key+'.json'),JSON.stringify({key,payload}),{mode:0o600});
} else if(command!=='flush')throw Error('Use update <JSON file> or flush. Failed writes remain in work/tracker-pending.');
if(!process.env.TRACKER_URL||!process.env.TRACKER_WRITE_TOKEN)throw Error('TRACKER_URL and TRACKER_WRITE_TOKEN are required; pending writes retained');
for(const name of (await readdir(queue)).filter(x=>x.endsWith('.json')).sort()){
 const path=resolve(queue,name);const {key,payload}=JSON.parse(await readFile(path,'utf8'));
 const response=await fetch(new URL('/api/tasks',process.env.TRACKER_URL),{method:'POST',headers:{Authorization:`Bearer ${process.env.TRACKER_WRITE_TOKEN}`,'Content-Type':'application/json','Idempotency-Key':key},body:JSON.stringify(payload),signal:AbortSignal.timeout(15000)});
 if(!response.ok)throw Error(`Update failed (${response.status}); mutation retained: ${name}`);
 await unlink(path);console.log(`${payload.id}: update confirmed`);
}
