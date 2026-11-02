import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { selectTab, startFromOnboarding, tapEditorControl, dismissKeyboard, scrollToControl, openLoopSession, openLoopPlanDay, approveLoopPackage, openLoopTodayRoot, selectTodayPiece, relaunchLoopSession, tapVisibleControl } from './pocket-support';

test('Pocket opens with one ready idea and a reachable filming action', async ({ app, screen, device }) => {
  if (process.env.POCKET_E2E_INSTALL === '1') await device.installApp();
  await startFromOnboarding(app, screen);
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  const action = await screen.getByTestId('today.startFilming').boundingBox();
  expect(action.height).toBeGreaterThanOrEqual(44);
  expect(action.width).toBeGreaterThanOrEqual(44);
  expect(action.x + action.width).toBeLessThanOrEqual(402);
  expect(action.y + action.height).toBeLessThanOrEqual(874);
  await app.screenshot('pocket-today-ready');
});

test('filming survives repeated navigation, edits, and posted undo', { timeout: 420_000 }, async ({ app, screen, device }) => {
  await startFromOnboarding(app, screen);
  const title = await screen.getByTestId('today.package.title').textContent();
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of');
  const progress = await screen.getByTestId('shoot.progress').textContent();
  const count = Number(progress.match(/of\s+(\d+)/)?.[1]);
  expect(count).toBeGreaterThan(1);
  expect(count).toBeLessThanOrEqual(12);
  await expect(screen.getByTestId('shoot.previous')).toBeDisabled();
  for (let cycle = 0; cycle < 6; cycle += 1) {
    await screen.getByTestId('shoot.next').tap();
    await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 2 of');
    await screen.getByTestId('shoot.previous').tap();
    await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of');
  }
  await expect(screen.getByTestId('shoot.complete')).toBeEnabled();
  await app.screenshot('pocket-filming');
  for (let shot = 1; shot <= count; shot += 1) {
    await expect(screen.getByTestId('shoot.progress')).toContainText(`Shot ${shot} of`);
    if (shot < count) {
      await screen.getByTestId('shoot.complete').doubleTap();
      await expect(screen.getByTestId('shoot.complete')).toContainText('Next shot');
      await expect(screen.getByTestId('shoot.complete')).toBeEnabled();
      await expect(screen.getByTestId('shoot.progress')).toContainText(`Shot ${shot} of`);
      await screen.getByTestId('shoot.next').tap();
    } else {
      await expect(screen.getByTestId('shoot.next')).toBeDisabled();
      await screen.getByTestId('shoot.complete').tap();
    }
  }
  await expect(screen.getByTestId('post.manualInstructions')).toContainText('does not publish');
  if (process.env.POCKET_E2E_SCENARIO === 'sync-error') {
    await expect(screen.getByTestId('post.syncError')).toBeVisible();
    await expect(screen.getByTestId('post.markPosted')).toBeEnabled();
  }
  await app.screenshot('pocket-post');
  await screen.getByTestId('post.edit').tap();
  await expect(screen.getByTestId('post.script.editor')).toBeVisible();
  const oldScript = await screen.getByTestId('post.script.editor').inputValue();
  await screen.getByTestId('post.script.editor').pressSequentially(' Hello.');
  expect(await screen.getByTestId('post.script.editor').inputValue()).not.toBe(oldScript);
  await dismissKeyboard(screen, 'post.keyboardDone');
  await expect(screen.getByTestId('post.cancel')).toBeEnabled();
  await tapEditorControl(screen, 'post.cancel');
  await screen.getByTestId('post.edit').tap();
  await expect(screen.getByTestId('post.script.editor')).toHaveValue(oldScript);
  await screen.getByTestId('post.script.editor').pressSequentially(' Small steps.');
  await dismissKeyboard(screen, 'post.keyboardDone');
  const savedScript = await screen.getByTestId('post.script.editor').inputValue();
  expect(savedScript).not.toBe(oldScript);
  await scrollToControl(screen, screen.getByTestId('post.caption.editor'));
  const oldCaption = await screen.getByTestId('post.caption.editor').inputValue();
  await screen.getByTestId('post.caption.editor').pressSequentially(' Today.');
  await dismissKeyboard(screen, 'post.keyboardDone');
  const savedCaption = await screen.getByTestId('post.caption.editor').inputValue();
  expect(savedCaption).not.toBe(oldCaption);
  await tapEditorControl(screen, 'post.save');
  await expect(screen.getByTestId('post.edit')).toBeVisible();
  await scrollToControl(screen, screen.getByTestId('post.copy.caption'));
  await screen.getByTestId('post.copy.caption').tap();
  expect(await device.clipboard()).toBe(savedCaption);
  await screen.getByTestId('post.markPosted').tap();
  await scrollToControl(screen, screen.getByText('Posted', { exact: true }), 'up');
  await expect(screen.getByText('Posted', { exact: true })).toBeVisible();
  await app.screenshot('pocket-posted');
  await screen.getByTestId('post.undoPosted').tap();
  await expect(screen.getByTestId('post.markPosted')).toBeEnabled();
  await screen.getByTestId('post.markPosted').tap();
  await scrollToControl(screen, screen.getByText('Posted', { exact: true }), 'up');
  await expect(screen.getByText('Posted', { exact: true })).toBeVisible();
  await device.openApp('com.prateekranka.creatorcontenthelper', {
    relaunch: true,
    launchArguments: ['-MCO_FORCE_FIXTURE_UI', '1', '-MCO_FORCE_APP_MODE', 'creator',
      '-MCO_QA_SESSION', process.env.POCKET_E2E_SESSION!, '-MCO_FORCE_ONBOARDING', '0'],
  });
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByText('Posted', { exact: true })).toBeVisible();
  await screen.getByTestId('post.edit').tap();
  await expect.poll(async () => (await screen.getByTestId('post.script.editor').inputValue()).trimEnd()).toBe(savedScript.trimEnd());
  await scrollToControl(screen, screen.getByTestId('post.caption.editor'));
  await expect.poll(async () => (await screen.getByTestId('post.caption.editor').inputValue()).trimEnd()).toBe(savedCaption.trimEnd());
  await app.screenshot('pocket-persisted-edits');
  await device.openApp('com.prateekranka.creatorcontenthelper', {
    relaunch: true,
    launchArguments: ['-MCO_FORCE_FIXTURE_UI', '1', '-MCO_FORCE_APP_MODE', 'creator',
      '-MCO_QA_SESSION', process.env.POCKET_E2E_SESSION!, '-MCO_FORCE_ONBOARDING', '0'],
  });
  await selectTab(screen, 'You');
  await scrollToControl(screen, screen.getByText(title, { exact: true }));
  await expect(screen.getByText(title, { exact: true })).toHaveCount(1);
  await app.screenshot('pocket-single-archive-entry');
});

for (const large of [false, true]) {
  test(`Today keeps two independent pieces and its selection${large ? ' at the largest text size' : ''}`, { timeout: 420_000 }, async ({ screen, device }) => {
    const session = await openLoopSession(device, 'ready', large ? { MCO_DYNAMIC_TYPE_ACCESSIBILITY5: '1' } : {});
    await openLoopPlanDay(screen, 0);
    await tapVisibleControl(screen, screen.getByTestId('plan.package.tab.caption'));
    await tapVisibleControl(screen, screen.getByTestId('plan.piece.add'));
    await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
    await tapVisibleControl(screen, screen.getByTestId('plan.daygen.idea.1'));
    await scrollToControl(screen, screen.getByTestId('daily.availableOnToday'));
    await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
    await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
    await scrollToControl(screen, screen.getByTestId('plan.package.title'));
    const secondTitle = await screen.getByTestId('plan.package.title').textContent();
    await approveLoopPackage(screen);
    await openLoopTodayRoot(screen);
    await scrollToControl(screen, screen.getByTestId('today.title'), 'up');
    await scrollToControl(screen, screen.getByTestId('today.piece.0'));
    await expect(screen.getByTestId('today.piece.0')).toBeSelected();
    await scrollToControl(screen, screen.getByTestId('today.piece.1'));
    await selectTodayPiece(screen, 1);
    await scrollToControl(screen, screen.getByTestId('today.package.title'));
    await expect(screen.getByTestId('today.package.title')).toHaveText(secondTitle!);
    await selectTab(screen, 'You');
    await selectTab(screen, 'Today');
    await scrollToControl(screen, screen.getByTestId('today.title'), 'up');
    await scrollToControl(screen, screen.getByTestId('today.piece.1'));
    await expect(screen.getByTestId('today.piece.1')).toBeSelected();
    await relaunchLoopSession(device, session);
    await scrollToControl(screen, screen.getByTestId('today.piece.1'));
    await expect(screen.getByTestId('today.piece.1')).toBeSelected();
    await tapVisibleControl(screen, screen.getByTestId('today.startFilming'));
    await scrollToControl(screen, screen.getByTestId('shoot.complete'));
    await expect(screen.getByTestId('shoot.complete')).toBeEnabled();
    await screen.getByTestId('shoot.complete').tap();
    await scrollToControl(screen, screen.getByTestId('shoot.complete'));
    await expect(screen.getByTestId('shoot.complete')).toContainText('Next shot');
    await expect(screen.getByTestId('shoot.complete')).toBeEnabled();
    await relaunchLoopSession(device, session);
    await scrollToControl(screen, screen.getByTestId('today.piece.0'));
    await selectTodayPiece(screen, 0);
    await scrollToControl(screen, screen.getByTestId('today.startFilming'), large ? 'up' : 'down');
    await expect(screen.getByTestId('today.startFilming')).toContainText('Start filming');
    await scrollToControl(screen, screen.getByTestId('today.piece.1'));
    await selectTodayPiece(screen, 1);
    await scrollToControl(screen, screen.getByTestId('today.startFilming'), large ? 'up' : 'down');
    await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  });
}
