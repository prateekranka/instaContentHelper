import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { selectTab, startFromOnboarding, scrollToControl } from './pocket-support';

const scenario = process.env.POCKET_E2E_SCENARIO ?? 'large';

test(`Pocket remains usable in ${scenario}`, { timeout: 240_000 }, async ({ app, screen }) => {
  if (['welcome', 'empty'].includes(scenario)) await app.open();
  else await startFromOnboarding(app, screen);
  if (scenario === 'welcome') {
    await expect(screen.getByTestId('sign-in.welcome')).toBeVisible();
    await expect(screen.getByTestId('sign-in-with-apple')).toBeVisible();
    await app.screenshot('pocket-welcome');
    return;
  }
  if (scenario === 'empty') {
    await expect(screen.getByTestId('today.empty')).toBeVisible();
    await expect(screen.getByTestId('today.empty.create')).toBeVisible();
    await expect(screen.getByTestId('today.empty.write')).toBeVisible();
    await app.screenshot('pocket-empty');
    await screen.getByTestId('today.empty.create').tap();
    await screen.getByTestId('composer.topic').pressSequentially('A calm start to the week');
    await screen.getByTestId('composer.createDraft').tap();
    await expect(screen.getByTestId('piece.status')).toContainText('Draft', { timeout: 45_000 });
    await expect(screen.getByTestId('piece.approve')).toHaveText('Approve content');
    await app.screenshot('pocket-empty-ai-draft');
    await screen.getByTestId('piece.approve').tap();
    await expect(screen.getByTestId('piece.status')).toContainText('Approved · version 1');
    await screen.getByTestId('composer.cancel').tap();
    await expect(screen.getByTestId('today.summary')).toHaveText('Day approved · 1 piece');
    await app.screenshot('pocket-empty-recovered');
    return;
  }
  await expect(screen.getByTestId('today.primaryAction')).toBeVisible();
  const primary = await screen.getByTestId('today.primaryAction').boundingBox();
  expect(primary.height).toBeGreaterThanOrEqual(44);
  expect(primary.x).toBeGreaterThanOrEqual(0);
  expect(primary.x + primary.width).toBeLessThanOrEqual(402);
  expect(primary.y + primary.height).toBeLessThanOrEqual(874);
  await app.screenshot(`pocket-${scenario}-today`);
  await screen.getByTestId('today.primaryAction').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 1 OF');
  for (const id of ['filming.markCaptured', 'filming.previous', 'filming.pause']) {
    const box = await screen.getByTestId(id).boundingBox();
    expect(box.width).toBeGreaterThanOrEqual(44);
    expect(box.height).toBeGreaterThanOrEqual(44);
    expect(box.x).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width).toBeLessThanOrEqual(402);
    expect(box.y + box.height).toBeLessThanOrEqual(874);
  }
  await app.screenshot(`pocket-${scenario}-filming`);
  const commandTop = (await screen.getByTestId('filming.markCaptured').boundingBox()).y;
  await scrollToControl(screen, screen.getByTestId('filming.attachClip'), 'down', commandTop - 16);
  await app.screenshot(`pocket-${scenario}-filming-instructions`);
  await screen.getByTestId('filming.markCaptured').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 2 OF');
  await screen.getByTestId('filming.pause').tap();
  await screen.getByTestId('today.overflow').tap();
  await screen.getByTestId('today.notEasier').tap();
  await app.screenshot(`pocket-${scenario}-alternatives`);
  await screen.scrollUntilVisible(screen.getByRole('button', /Plan tomorrow/));
  await screen.getByRole('button', /Plan tomorrow/).tap();
  await expect(screen.getByTestId('plan.title')).toBeVisible();
  await app.screenshot(`pocket-${scenario}-plan`);
  await selectTab(screen, 'You');
  await expect(screen.getByTestId('you.preferences.toggle')).toBeVisible();
  await screen.getByTestId('you.preferences.toggle').tap();
  await screen.scrollUntilVisible(screen.getByTestId('you.row.production'));
  await app.screenshot(`pocket-${scenario}-you`);
});
