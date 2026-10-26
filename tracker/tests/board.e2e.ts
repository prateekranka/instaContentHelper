import {test} from '@e2e-dev/web';
import {expect} from 'e2e';

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
