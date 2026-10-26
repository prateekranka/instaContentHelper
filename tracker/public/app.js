const $=id=>document.getElementById(id);
const statuses=['Planned','Working','Done']; let selected='Working', data, lastFetch;
const el=(tag,text,cls)=>{const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e;};
const time=value=>{if(!value)return 'Not yet';const d=new Date(value);const minutes=Math.max(0,Math.floor((Date.now()-d)/60000));return `${d.toLocaleString(undefined,{timeZoneName:'short'})} · ${minutes<1?'just now':minutes+' min ago'}`;};
function details(task){
 const c=$('detail-content');c.replaceChildren(el('p',`${task.id} · ${task.status} · ${task.milestone}`,'tag'));const title=el('h2',task.title);title.id='detail-title';c.append(title,el('p',task.description));
 for(const [label,value] of [['Blocker',task.blocker],['Next action',task.nextAction],['Verification',task.verification]])if(value)c.append(el('h3',label),el('p',value));
 c.append(el('h3','Acceptance criteria'));const ul=el('ul');task.criteria.forEach(x=>ul.append(el('li',x)));c.append(ul,el('h3','Pushed GitHub commits'));
 if(!task.commits.length)c.append(el('p','No pushed commits attached yet.'));
 task.commits.forEach(url=>{const p=el('p');const a=el('a',url.split('/').at(-1));a.href=url;a.target='_blank';a.rel='noopener noreferrer';p.append(a);c.append(p);});
 c.append(el('h3','Timestamps'));for(const key of ['createdAt','startedAt','updatedAt','completedAt'])c.append(el('p',`${key.replace('At','')}: ${time(task[key])}`));
 c.append(el('h3','Activity history'));for(const h of [...task.history].reverse())c.append(el('p',`${time(h.at)} · ${h.status} — ${h.note}`));
 $('detail').showModal();
}
function render(){
 const tasks=data.tasks;const active=tasks.filter(t=>t.status==='Working');$('focus').textContent=active.length?`Current focus: ${active.map(t=>t.title+(t.blocker?' (blocked)':'')).join('; ')}`:'No task is currently active.';
 $('activity').textContent='Last project activity: '+time(data.activityAt);$('fetched').textContent='Last fetched: '+time(lastFetch);
 $('board').replaceChildren();$('selector').replaceChildren();for(const status of statuses){const items=tasks.filter(t=>t.status===status);const tab=el('button',`${status} (${items.length})`);tab.setAttribute('aria-pressed',String(selected===status));tab.onclick=()=>{selected=status;render();};$('selector').append(tab);
 const column=el('section',undefined,'column');column.setAttribute('aria-label',status);column.hidden=innerWidth<=780&&selected!==status;column.append(el('h2',`${status} · ${items.length}`));
 for(const task of items){const card=el('button',undefined,'card');card.setAttribute('aria-label',`${task.id}: ${task.title}. ${task.status}. Open details`);card.append(el('span',`${task.id} · ${task.milestone}`,'tag'),el('h3',task.title),el('p',task.description));if(task.blocker)card.append(el('p','Blocked: '+task.blocker,'blocked'));card.append(el('p',`${task.commits.length} pushed commit${task.commits.length===1?'':'s'} · ${task.verification?'Verification recorded':'Verification pending'}`,'evidence'),el('time','Updated '+time(task.updatedAt)));card.onclick=()=>details(task);column.append(card);}
 if(!items.length)column.append(el('p','No tasks in this column.'));$('board').append(column);}
}
let fetching=false;
async function refresh(){if(fetching)return;fetching=true;$('connection').textContent='Refreshing…';try{const r=await fetch('/api/tasks',{cache:'no-store',signal:AbortSignal.timeout(12000)});if(!r.ok)throw Error();const next=await r.json();if(!Array.isArray(next.tasks))throw Error();data=next;lastFetch=new Date().toISOString();render();$('connection').textContent='Connected · refreshes every 30 seconds';$('connection').className='';}catch{$('connection').textContent=data?'Connection failed · showing stale data':'Cannot connect · try Refresh now';$('connection').className='stale';}finally{fetching=false;}}
$('refresh').onclick=refresh;$('close').onclick=()=>$('detail').close();addEventListener('resize',()=>{if(data)render();});setInterval(refresh,30000);refresh();
