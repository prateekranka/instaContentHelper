import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import {
  selectTab, openLoopSession, openLoopEditor, openLoopPlanDay,
  finishLoopFilming, openLoopTodayRoot, scrollToControl,
} from './pocket-support';

// A non-asserting-ish guided tour that screenshots each creator-loop surface.
// Screenshots land in the config `output` dir.
test('journey tour: capture each creator-loop surface', { timeout: 420_000 }, async ({ app, screen, device }) => {
  // 1) Today
  await openLoopSession(device, 'ready');
  await expect(screen.getByTestId('today.package.title')).toBeVisible();
  await app.screenshot('tour-01-today');

  // 2) Plan — idea picker on a future (empty) day
  try {
    await openLoopPlanDay(screen, 3);
    await app.screenshot('tour-02-plan-ideas');
  } catch (e) { await app.screenshot('tour-02-plan-ideas-FALLBACK'); }

  // 3) Shoot Folio editor (scenes) + Script tab
  try {
    await openLoopTodayRoot(screen);
    await openLoopEditor(screen);
    await app.screenshot('tour-03-shootfolio-scenes');
    await screen.getByRole('button', 'Script', { exact: true }).tap();
    await app.screenshot('tour-04-script');
    await screen.getByTestId('shootFolio.cancelEdit').tap();
  } catch (e) { await app.screenshot('tour-03-shootfolio-FALLBACK'); }

  // 4) Filming carousel (shot-by-shot)
  try {
    await openLoopTodayRoot(screen);
    await screen.getByTestId('today.startFilming').tap();
    await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of');
    await app.screenshot('tour-05-filming');
    await app.back();
  } catch (e) { await app.screenshot('tour-05-filming-FALLBACK'); }

  // 5) Post text (after finishing filming)
  try {
    await openLoopTodayRoot(screen);
    await finishLoopFilming(screen);
    await app.screenshot('tour-06-post');
    await screen.getByTestId('post.edit').tap();
    await app.screenshot('tour-07-post-edit');
  } catch (e) { await app.screenshot('tour-06-post-FALLBACK'); }
});
