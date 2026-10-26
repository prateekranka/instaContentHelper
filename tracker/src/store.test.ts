import {test} from 'node:test';
import assert from 'node:assert/strict';
import {mkdtempSync} from 'node:fs';
import {tmpdir} from 'node:os';
import {join} from 'node:path';
import {Store,mutation} from './store.ts';
test('transactional updates, idempotency, durable reopen, evidence gate and completion history',()=>{
 const path=join(mkdtempSync(join(tmpdir(),'mira-store-')),'db.sqlite');let store=new Store(path);
 const input=mutation.parse({id:'MIRA-099',title:'Proof',description:'Durability',milestone:'Test',criteria:['Persist'],codeTask:true,note:'Created'});
 const first=store.apply('create-test',input);assert.deepEqual(store.apply('create-test',input),first);
 assert.throws(()=>store.apply('create-test',{...input,note:'Different'}));
 assert.throws(()=>store.apply('bad-done',{id:input.id,status:'Done',note:'No proof'}));
 assert.equal(store.list()[0].status,'Planned');
 const done=store.apply('finish-test',{id:input.id,status:'Done',note:'Verified',verification:'Store test passed',commits:['https://github.com/prateekranka/instaContentHelper/commit/'+'a'.repeat(40)]});
 assert.ok(done.completedAt);store.db.close();store=new Store(path);assert.deepEqual(store.list()[0],done);
 const reopened=store.apply('reopen-test',{id:input.id,status:'Working',note:'Follow-up required'});assert.equal(reopened.completedAt,null);assert.equal(reopened.history[1].status,'Done');store.db.close();
});
