import {test} from '@e2e-dev/web';
import {expect} from 'e2e';
import {randomUUID} from 'node:crypto';

test('public desktop and mobile board opens details and preserves data after refresh failure',async({app,screen,browser})=>{
 await app.open('/');
 await expect(screen.getByRole('heading','Mira — Build progress')).toBeVisible();
 await expect(screen.getByRole('status')).toContainText('Connected');
 await expect(browser.locator('#board > section')).toHaveCount(3);
 await app.screenshot('tracker-desktop');
 await screen.getByRole('button',/MIRA-001:.*Open details/).click();
 await expect(screen.getByRole('dialog')).toBeVisible();
 await expect(screen.getByRole('heading','Acceptance criteria')).toBeVisible();
 await expect(screen.getByRole('heading','Activity history')).toBeVisible();
 await screen.getByRole('button','Close details').click();
 await browser.setViewport({width:375,height:812});
 await expect(screen.getByRole('button',/^Working \(\d+\)$/)).toBeVisible();
 await screen.getByRole('button',/^Planned \(\d+\)$/).click();
 await expect(screen.getByRole('heading',/^Planned · \d+$/)).toBeVisible();
 await expect(screen.getByRole('heading',/^Working · \d+$/)).toBeHidden();
 expect(await browser.evaluate(()=>document.documentElement.scrollWidth<=innerWidth)).toBe(true);
 await app.screenshot('tracker-mobile');
 await browser.route('**/api/tasks',route=>route.abort());
 await screen.getByRole('button','Refresh now').click();
 await expect(screen.getByRole('status')).toContainText('showing stale data');
 await expect(screen.getByRole('heading',/^Planned · \d+$/)).toBeVisible();
 await browser.unrouteAll();
 await screen.getByRole('button','Refresh now').click();
 await expect(screen.getByRole('status')).toContainText('Connected');
});

test('public reads reject unauthenticated editing and authenticated updates are idempotent',async({app})=>{
 const url=new URL('/api/tasks',app.baseUrl);
 expect((await fetch(url)).status).toBe(200);
 const body=JSON.stringify({id:'MIRA-001',note:'Authenticated API verification: public reads, rejected anonymous writes and duplicate-safe update checked.'});
 const key=randomUUID();
 const headers={'Content-Type':'application/json','Idempotency-Key':key};
 expect((await fetch(url,{method:'POST',headers,body})).status).toBe(401);
 const token=process.env.TRACKER_WRITE_TOKEN;
 if(!token)throw new Error('Authenticated API check needs TRACKER_WRITE_TOKEN in the test environment.');
 const authorized={...headers,Authorization:`Bearer ${token}`};
 const first=await fetch(url,{method:'POST',headers:authorized,body});
 expect(first.status).toBe(200);const task=await first.json();
 const replay=await fetch(url,{method:'POST',headers:authorized,body});
 expect(replay.status).toBe(200);const replayTask=await replay.json();
 expect(replayTask.updatedAt).toBe(task.updatedAt);expect(replayTask.history.length).toBe(task.history.length);
 const conflict=await fetch(url,{method:'POST',headers:authorized,body:JSON.stringify({id:'MIRA-001',note:'Different mutation using same key'})});
 expect(conflict.status).toBe(409);
});
