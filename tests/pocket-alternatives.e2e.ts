import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { selectTab, startFromOnboarding } from './pocket-support';

test('partial filming survives relaunch and backup preview preserves the main idea', { timeout: 240_000 }, async ({ app, screen, device }) => {
  await startFromOnboarding(app, screen);
  const title = await screen.getByTestId('today.package.title').textContent();
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('shoot.complete').tap();
  await expect(screen.getByTestId('shoot.complete')).toContainText('Next shot');
  await expect(screen.getByTestId('shoot.complete')).toBeEnabled();
  await device.openApp('com.prateekranka.creatorcontenthelper', {
    relaunch: true,
    launchArguments: ['-MCO_FORCE_FIXTURE_UI', '1', '-MCO_FORCE_APP_MODE', 'creator',
      '-MCO_QA_SESSION', process.env.POCKET_E2E_SESSION!, '-MCO_FORCE_ONBOARDING', '0'],
  });
  await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 2 of');
  await app.screenshot('pocket-resumed-filming');
  await screen.getByTestId('shoot.previous').tap();
  await expect(screen.getByTestId('shoot.complete')).toContainText('Next shot');
  await expect(screen.getByTestId('shoot.complete')).toBeEnabled();
  await app.back();
  await screen.getByTestId('today.notEasier').tap();
  await screen.getByRole('button', /10-second story/).tap();
  await screen.scrollUntilVisible(screen.getByTestId('backup.confirmPosted'));
  await expect(screen.getByTestId('backup.confirmPosted')).toBeVisible();
  await app.screenshot('pocket-backup-preview');
  const cancel = await screen.getByRole('button', 'Cancel', { exact: true }).boundingBox();
  // The native runner's overlap guard misidentifies this visible sheet toolbar.
  // Tap its observed geometry and verify that the preview really closes.
  expect(cancel.y + cancel.height).toBeLessThanOrEqual(160);
  await screen.tapAt({ x: cancel.x + cancel.width / 2, y: cancel.y + cancel.height / 2 });
  await expect(screen.getByTestId('backup.confirmPosted')).toBeHidden();
  await screen.getByRole('button', /Plan tomorrow/).tap();
  await expect(screen.getByTestId('plan.title')).toBeVisible();
  const days = screen.getByTestId(/^plan\.sevenDaySelector\.day\./);
  await expect(days.nth(1)).toBeSelected();
  await selectTab(screen, 'Today');
  await expect(screen.getByTestId('today.package.title')).toHaveText(title);
  await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  await screen.getByTestId('today.notEasier').tap();
  await screen.getByRole('button', /Caption-only post/).tap();
  await screen.scrollUntilVisible(screen.getByTestId('backup.confirmPosted'));
  const confirm = await screen.getByTestId('backup.confirmPosted').boundingBox();
  expect(confirm.height).toBeGreaterThanOrEqual(44);
  expect(confirm.y + confirm.height).toBeLessThanOrEqual(874);
  await screen.tapAt({ x: confirm.x + confirm.width / 2, y: confirm.y + confirm.height / 2 });
  await expect(screen.getByText('Used backup: caption-only post', { exact: true }).first()).toBeVisible();
  await expect(screen.getByTestId('today.package.title')).toHaveText(title);
  await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  await app.screenshot('pocket-backup-confirmed');
});
