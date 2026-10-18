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
    await expect(screen.getByTestId('today.emptyCard')).toBeVisible();
    await expect(screen.getByTestId('today.planCTA')).toBeVisible();
    await app.screenshot('pocket-empty');
    await screen.getByTestId('today.planCTA').tap();
    await expect(screen.getByTestId('plan.title')).toBeVisible();
    await scrollToControl(screen, screen.getByTestId('plan.daygen.idea.0'));
    await expect(screen.getByTestId('plan.daygen.idea.0')).toBeEnabled();
    await screen.getByTestId('plan.daygen.idea.0').tap();
    await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
    await expect(screen.getByTestId('daily.availableOnToday')).toContainText('Make ready for Today');
    await scrollToControl(screen, screen.getByTestId('daily.availableOnToday'));
    await screen.getByTestId('daily.availableOnToday').tap();
    await expect(screen.getByTestId('today.startFilming')).toBeVisible();
    await app.screenshot('pocket-empty-recovered');
    return;
  }
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  const primary = await screen.getByTestId('today.startFilming').boundingBox();
  expect(primary.height).toBeGreaterThanOrEqual(44);
  expect(primary.x).toBeGreaterThanOrEqual(0);
  expect(primary.x + primary.width).toBeLessThanOrEqual(402);
  expect(primary.y + primary.height).toBeLessThanOrEqual(874);
  await app.screenshot(`pocket-${scenario}-today`);
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of');
  for (const id of ['shoot.complete', 'shoot.next', 'shoot.previous']) {
    const box = await screen.getByTestId(id).boundingBox();
    expect(box.width).toBeGreaterThanOrEqual(44);
    expect(box.height).toBeGreaterThanOrEqual(44);
    expect(box.x).toBeGreaterThanOrEqual(0);
    expect(box.x + box.width).toBeLessThanOrEqual(402);
    expect(box.y + box.height).toBeLessThanOrEqual(874);
  }
  await app.screenshot(`pocket-${scenario}-filming`);
  const commandTop = (await screen.getByTestId('shoot.complete').boundingBox()).y;
  await scrollToControl(screen, screen.getByText('CAPTURE', { exact: true }), 'down', commandTop - 16);
  await app.screenshot(`pocket-${scenario}-filming-instructions`);
  await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 2 of');
  await app.back();
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
