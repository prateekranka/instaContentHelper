import { test } from '@e2e-dev/mobile';
import { expect, type Screen } from 'e2e';
import { relaunch, selectTab, startFromOnboarding } from './pocket-support';

async function openAlternatives(screen: Screen) {
  await screen.getByTestId('today.overflow').tap();
  await screen.getByTestId('today.notEasier').tap();
}

test('partial filming survives relaunch and backup preview preserves the main piece', { timeout: 240_000 }, async ({ app, screen, device }) => {
  await startFromOnboarding(app, screen);
  const piece = await screen.getByTestId('today.piece.0').textContent();
  await screen.getByTestId('today.primaryAction').tap();
  await screen.getByTestId('filming.markCaptured').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 2 OF');
  await relaunch(device);
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Continue filming');
  await screen.getByTestId('today.primaryAction').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 2 OF');
  await app.screenshot('pocket-resumed-filming');
  await screen.getByTestId('filming.previous').tap();
  await expect(screen.getByTestId('filming.unmark')).toBeVisible();
  await screen.getByTestId('filming.pause').tap();
  await openAlternatives(screen);
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
  await expect(screen.getByTestId('today.piece.0')).toHaveText(piece);
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Continue filming');
  await openAlternatives(screen);
  await screen.getByRole('button', /Caption-only post/).tap();
  await screen.scrollUntilVisible(screen.getByTestId('backup.confirmPosted'));
  const confirm = await screen.getByTestId('backup.confirmPosted').boundingBox();
  expect(confirm.height).toBeGreaterThanOrEqual(44);
  expect(confirm.y + confirm.height).toBeLessThanOrEqual(874);
  await screen.tapAt({ x: confirm.x + confirm.width / 2, y: confirm.y + confirm.height / 2 });
  await expect(screen.getByText('Used backup: caption-only post', { exact: true }).first()).toBeVisible();
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Continue filming');
  await app.screenshot('pocket-backup-confirmed');
});
