import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { relaunch, selectTab, startFromOnboarding, tapEditorControl } from './pocket-support';

test('Pocket opens with the day\'s piece and a reachable next action', async ({ app, screen, device }) => {
  if (process.env.POCKET_E2E_INSTALL === '1') await device.installApp();
  await startFromOnboarding(app, screen);
  await expect(screen.getByTestId('today.title')).toBeVisible();
  await expect(screen.getByTestId('today.piece.0')).toContainText('Approved');
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Start filming');
  const action = await screen.getByTestId('today.primaryAction').boundingBox();
  expect(action.height).toBeGreaterThanOrEqual(44);
  expect(action.width).toBeGreaterThanOrEqual(44);
  expect(action.x + action.width).toBeLessThanOrEqual(402);
  expect(action.y + action.height).toBeLessThanOrEqual(874);
  await app.screenshot('pocket-today-ready');
});

test('caption edits create a draft revision, survive relaunch and keep the archive single', { timeout: 360_000 }, async ({ app, screen, device }) => {
  await startFromOnboarding(app, screen);
  await screen.getByTestId('today.piece.0').tap();
  const title = await screen.getByTestId('piece.title').textContent();
  await screen.getByTestId('piece.edit.caption').tap();
  await expect(screen.getByTestId('editor.caption')).toBeVisible();
  const oldCaption = await screen.getByTestId('editor.caption').inputValue();
  await screen.getByTestId('editor.caption').pressSequentially(' Today.');
  await screen.getByTestId('editor.keyboardDone').tap();
  const savedCaption = await screen.getByTestId('editor.caption').inputValue();
  expect(savedCaption).not.toBe(oldCaption);
  await tapEditorControl(screen, 'editor.save');
  await expect(screen.getByTestId('piece.draftBadge')).toContainText('Draft version 2');
  await screen.getByTestId('piece.approve').tap();
  await expect(screen.getByTestId('piece.status')).toContainText('Approved · version 2');
  await app.screenshot('pocket-caption-revision');

  await relaunch(device);
  await screen.getByTestId('today.piece.0').tap();
  await expect(screen.getByTestId('piece.status')).toContainText('Approved · version 2');
  await screen.getByTestId('piece.edit.caption').tap();
  await expect(screen.getByTestId('editor.caption')).toHaveValue(savedCaption);
  await screen.getByTestId('editor.cancel').tap();
  await app.screenshot('pocket-persisted-edits');

  await relaunch(device);
  await selectTab(screen, 'You');
  await screen.scrollUntilVisible(screen.getByTestId('you.yourContent'));
  await screen.getByTestId('you.yourContent').tap();
  await expect(screen.getByTestId(`content.piece.${title}`)).toHaveCount(1);
  await app.screenshot('pocket-single-content-entry');
});
