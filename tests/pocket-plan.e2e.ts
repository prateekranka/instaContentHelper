import { test } from '@e2e-dev/mobile';
import { expect, type Screen } from 'e2e';
import type { Device } from '@e2e-dev/mobile';
import { selectTab, startFromOnboarding, scrollToControl, dismissKeyboard, openLoopSession, openLoopPlanDay, tapVisibleControl, addPlanPiece, selectPlanPiece, relaunchLoopSession, requestLoopReplacement, openDayReview, openReviewSession } from './pocket-support';

test('Plan keeps seven dates separate and supports cancelling or confirming a future overwrite', { timeout: 360_000 }, async ({ app, screen }) => {
  await startFromOnboarding(app, screen);
  await selectTab(screen, 'Plan');
  await expect(screen.getByTestId('plan.title')).toBeVisible();
  const days = screen.getByTestId(/^plan\.sevenDaySelector\.day\./);
  await expect(days).toHaveCount(7);
  for (let index = 0; index < 8; index += 1) {
    await days.nth(index % 7).tap();
    await expect(days.nth(index % 7)).toBeSelected();
  }
  await days.nth(1).tap();
  await scrollToControl(screen, screen.getByTestId('plan.voiceGate.setup'));
  await screen.getByTestId('plan.voiceGate.setup').tap();
  await expect(screen.getByTestId('you.voice.positioning')).toBeVisible();
  await screen.getByTestId('you.voice.positioning').pressSequentially('Practical daily routines.');
  await dismissKeyboard(screen, 'you.voice.keyboardDone');
  await scrollToControl(screen, screen.getByTestId('you.voice.rules'));
  await screen.getByTestId('you.voice.rules').pressSequentially('Use short, direct sentences.');
  await dismissKeyboard(screen, 'you.voice.keyboardDone');
  await scrollToControl(screen, screen.getByTestId('you.voice.save'));
  await screen.getByTestId('you.voice.save').tap();
  await expect(screen.getByTestId('you.voice.save')).toBeDisabled();
  await scrollToControl(screen, screen.getByRole('button', 'Back to Plan', { exact: true }), 'up');
  await screen.getByRole('button', 'Back to Plan', { exact: true }).tap();
  await scrollToControl(screen, screen.getByTestId('plan.daygen.idea.0'));
  await expect(screen.getByTestId('plan.daygen.idea.0')).toBeEnabled();
  await screen.getByTestId('plan.daygen.idea.0').tap();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByTestId('daily.availableOnToday')).toContainText('Save for');
  const originalTitle = await screen.getByTestId('plan.package.title').textContent();
  await app.screenshot('pocket-plan-future-draft');
  await scrollToControl(screen, screen.getByTestId('daily.availableOnToday'));
  await screen.getByTestId('daily.availableOnToday').tap();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
  await expect(screen.getByTestId('plan.title')).toBeVisible();
  await expect(days.nth(1)).toBeSelected();
  await scrollToControl(screen, screen.getByTestId('plan.package.tab.caption'));
  for (let index = 0; index < 8; index += 1) {
    const tab = ['script', 'caption', 'storyboard'][index % 3];
    await scrollToControl(screen, screen.getByTestId(`plan.package.tab.${tab}`));
    await screen.getByTestId(`plan.package.tab.${tab}`).tap();
    await expect(screen.getByTestId(`plan.package.tab.${tab}`)).toBeSelected();
  }
  await scrollToControl(screen, screen.getByTestId('plan.package.replaceIdea'));
  await screen.getByTestId('plan.package.replaceIdea').tap();
  await scrollToControl(screen, screen.getByTestId('plan.daygen.idea.0'), 'up');
  await screen.getByTestId('plan.daygen.idea.0').tap();
  await expect(screen.getByRole('button', 'Overwrite', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Cancel', { exact: true }).tap();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
  await scrollToControl(screen, days.nth(2));
  await days.nth(2).tap();
  await scrollToControl(screen, days.nth(1), 'up');
  await days.nth(1).tap();
  await expect(screen.getByTestId('plan.package.tab.caption')).toBeVisible();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  await app.screenshot('pocket-plan-future-ready');
  await scrollToControl(screen, screen.getByTestId('plan.package.replaceIdea'));
  await screen.getByTestId('plan.package.replaceIdea').tap();
  await scrollToControl(screen, screen.getByTestId('plan.daygen.idea.1'), 'up');
  await screen.getByTestId('plan.daygen.idea.1').tap();
  await expect(screen.getByRole('button', 'Overwrite', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Overwrite', { exact: true }).tap();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByTestId('daily.availableOnToday')).toContainText('Save for');
  const replacementTitle = await screen.getByTestId('plan.package.title').textContent();
  expect(replacementTitle).not.toBe(originalTitle);
  await scrollToControl(screen, screen.getByTestId('daily.availableOnToday'));
  await screen.getByTestId('daily.availableOnToday').tap();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
  await scrollToControl(screen, days.nth(2));
  await days.nth(2).tap();
  await scrollToControl(screen, days.nth(1), 'up');
  await days.nth(1).tap();
  await expect(screen.getByTestId('plan.package.tab.storyboard')).toBeVisible();
  await expect(screen.getByTestId('plan.package.title')).toHaveText(replacementTitle);
  await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  await app.screenshot('pocket-plan-overwrite-confirmed');
});

async function copyPieceScript(screen: Screen, device: Device) {
  const tab = screen.getByTestId('plan.package.tab.script');
  await scrollToControl(screen, tab, 'up');
  await tab.tap();
  await tapVisibleControl(screen, screen.getByTestId('plan.package.copyScript'));
  return device.clipboard();
}

async function pieceTitle(screen: Screen) {
  const title = screen.getByTestId('plan.package.title');
  await scrollToControl(screen, title, 'up');
  return title.textContent();
}

test('Plan keeps two pieces and the selected piece after a tab switch and relaunch', { timeout: 360_000 }, async ({ screen, device }) => {
  const session = await openLoopSession(device, 'ready');
  await openLoopPlanDay(screen, 1);
  const title0 = await pieceTitle(screen);
  const script0 = await copyPieceScript(screen, device);
  await tapVisibleControl(screen, screen.getByTestId('plan.piece.add'));
  await tapVisibleControl(screen, screen.getByTestId('plan.piece.cancel'));
  expect(await pieceTitle(screen)).toBe(title0);
  await addPlanPiece(screen, 1);
  await scrollToControl(screen, screen.getByTestId('plan.piece.1'), 'up');
  await expect(screen.getByTestId('plan.piece.1')).toBeSelected({ timeout: 45_000 });
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  const title1 = await pieceTitle(screen);
  const script1 = await copyPieceScript(screen, device);
  await selectTab(screen, 'You');
  await selectTab(screen, 'Plan');
  await scrollToControl(screen, screen.getByTestId('plan.piece.1'), 'up');
  await expect(screen.getByTestId('plan.piece.1')).toBeSelected();
  await relaunchLoopSession(device, session);
  await selectTab(screen, 'Plan');
  for (const position of [0, 1]) {
    const piece = screen.getByTestId(`plan.piece.${position}`);
    await scrollToControl(screen, piece, 'up');
    await expect(piece).toHaveCount(1);
  }
  await expect(screen.getByTestId('plan.piece.1')).toBeSelected();
  expect(await pieceTitle(screen)).toBe(title1);
  expect(await copyPieceScript(screen, device)).toBe(script1);
  await selectPlanPiece(screen, 0);
  expect(await pieceTitle(screen)).toBe(title0);
  expect(await copyPieceScript(screen, device)).toBe(script0);
});

test('Plan Choose another idea replaces only piece 1 through relaunch', { timeout: 360_000 }, async ({ screen, device }) => {
  const session = await openLoopSession(device, 'ready');
  await openLoopPlanDay(screen, 1);
  const title0 = await pieceTitle(screen);
  const script0 = await copyPieceScript(screen, device);
  await addPlanPiece(screen, 1);
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  const script1 = await copyPieceScript(screen, device);
  await requestLoopReplacement(screen, 2);
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  await scrollToControl(screen, screen.getByTestId('plan.piece.1'), 'up');
  await expect(screen.getByTestId('plan.piece.1')).toBeSelected();
  const replacementScript = await copyPieceScript(screen, device);
  expect(replacementScript).not.toBe(script1);
  await selectPlanPiece(screen, 0);
  expect(await pieceTitle(screen)).toBe(title0);
  expect(await copyPieceScript(screen, device)).toBe(script0);
  await relaunchLoopSession(device, session);
  await selectTab(screen, 'Plan');
  await scrollToControl(screen, screen.getByTestId('plan.piece.0'), 'up');
  await expect(screen.getByTestId('plan.piece.0')).toBeSelected();
  expect(await pieceTitle(screen)).toBe(title0);
  expect(await copyPieceScript(screen, device)).toBe(script0);
  await selectPlanPiece(screen, 1);
  expect(await copyPieceScript(screen, device)).toBe(replacementScript);
});

test('Plan day review counts only the reviewed pieces selected for approval', { timeout: 240_000 }, async ({ screen, device }) => {
  const { date } = await openReviewSession(device, screen, { MCO_REVIEW_SELECT_ALL: '0' });
  const approve = screen.getByTestId('review.day.approve');
  await scrollToControl(screen, approve);
  await expect(approve).toHaveText('Approve 0 pieces');
  await expect(approve).toBeDisabled();
  for (const position of [0, 1]) {
    const select = screen.getByTestId(`review.piece.${date}.${position}.select`);
    await scrollToControl(screen, select);
    await select.check();
  }
  await scrollToControl(screen, approve);
  await expect(approve).toHaveText('Approve 2 pieces');
  const select = screen.getByTestId(`review.piece.${date}.0.select`);
  await scrollToControl(screen, select, 'up');
  await select.uncheck();
  await scrollToControl(screen, approve);
  await expect(approve).toHaveText('Approve 1 piece');
  await scrollToControl(screen, select, 'up');
  await select.check();
  await scrollToControl(screen, approve);
  await expect(approve).toHaveText('Approve 2 pieces');
});

test('Plan day and week summaries count every real piece', { timeout: 240_000 }, async ({ screen, device }) => {
  await openLoopSession(device, 'ready', { MCO_REVIEW_TWO_DRAFTS: '1' });
  const date = await openDayReview(screen);
  await tapVisibleControl(screen, screen.getByTestId('review.day.close'));
  await scrollToControl(screen, screen.getByTestId('plan.day.summary'));
  await expect(screen.getByTestId('plan.day.summary')).toHaveText('0 approved · 2 needs review');
  const sameWeekAsTomorrow = new Date(`${date}T12:00:00Z`).getUTCDay() !== 0;
  await scrollToControl(screen, screen.getByTestId('plan.week.summary'));
  await expect(screen.getByTestId('plan.week.summary')).toHaveText(
    `This week: ${sameWeekAsTomorrow ? 3 : 2} pieces · ${sameWeekAsTomorrow ? 1 : 0} approved · 2 needs review`,
  );
});
