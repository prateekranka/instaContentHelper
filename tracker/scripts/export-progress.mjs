import {writeFile,rename} from 'node:fs/promises';
import {resolve} from 'node:path';
const root=resolve(import.meta.dirname,'../..');
const origin=process.env.TRACKER_URL??'http://127.0.0.1:3000';
const response=await fetch(new URL('/api/tasks',origin),{signal:AbortSignal.timeout(15000)});
if(!response.ok)throw Error(`Board snapshot failed (${response.status}); previous files retained`);
const board=await response.json();if(!Array.isArray(board.tasks))throw Error('Invalid board response');
const hosted=new URL(origin).protocol==='https:';
let md='# Mira implementation progress\n\n';
md+=hosted?`Public tracker: ${origin}\n\n`:'This is a public GitHub snapshot of the local tracker. The standalone HTTPS tracker is not yet deployed.\n\n';
md+=`Snapshot fetched: ${board.fetchedAt}. Last project activity: ${board.activityAt}. All recorded timestamps are UTC.\n\n`;
md+='The native Mira journey, cross-platform workflow/persistence and Supabase job source are implemented. Compilation/type checks and recorded E2E evidence are separate from native runtime and production deployment. The owner removed all unit suites and prohibits future unit tests; earlier unit counts are historical only. Prefer realistic E2E scenarios with reproducible artifacts under [the repository policy](../AGENTS.md). The owner confirmed existing server-side AI credential reuse and waived archive/device access. Full native compilation, native UI/speech/accessibility and live Supabase generation remain unverified.\n\n';
md+='Multiple Working tasks await required native or production verification. They represent one agent’s sequential implementation, with external verification blockers recorded on each card. No completion percentage is inferred from source changes.\n\n';
const columns=['Planned','Working','Done'].map(status=>board.tasks.filter(t=>t.status===status));
md+='| Planned | Working | Done |\n| --- | --- | --- |\n';
for(let i=0;i<Math.max(...columns.map(c=>c.length));i++)md+='| '+columns.map(c=>c[i]?`${c[i].id} — ${c[i].title}${c[i].blocker?' **(blocked)**':''}`:'—').join(' | ')+' |\n';
md+='\n## Per-task evidence\n\n';
for(const task of board.tasks){
 md+=`### ${task.id} — ${task.title}\n\n${task.status} · Updated ${task.updatedAt}\n\n`;
 if(task.verification)md+=task.verification+'\n\n';
 if(task.blocker)md+='Blocker: '+task.blocker+'\n\n';
 if(task.nextAction)md+='Next action: '+task.nextAction+'\n\n';
 for(const url of task.commits)md+=`- [Pushed commit ${url.split('/').at(-1)}](${url})\n`;
 md+='\n';
}
md+='Full criteria, created/started/completed timestamps and history: [JSON snapshot](mira-progress.json).\n\nRead [the implementation handoff](mira-handoff.md), [toolchain record](mira-toolchain.md), and [tracker operations](../tracker/README.md). Committed screenshots show the tracker, not the native app. No TestFlight or App Store distribution occurred.\n';
for(const [name,value] of [['mira-progress.json',JSON.stringify(board,null,2)+'\n'],['mira-progress.md',md]]){
 const path=resolve(root,'docs',name);await writeFile(path+'.pending',value);await rename(path+'.pending',path);
}
console.log(`Exported ${board.tasks.length} tasks; ${columns[2].length} Done. Hosted tracker: ${hosted?'yes':'no'}.`);
await writeFile(resolve(root,'tracker/initial-state.json'),JSON.stringify(board.tasks,null,2)+'\n');
