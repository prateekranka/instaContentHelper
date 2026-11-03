import { test } from '@e2e-dev/mobile';
import { expect, type Locator, type Screen } from 'e2e';
import { scrollToControl, tapVisibleControl } from './mobile-support';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';

async function tap(screen: Screen, locator: Locator) {
  await tapVisibleControl(screen, locator);
}

test('demo moves from an idea to a saved filming plan', async ({ app, screen, device }) => {
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-MCO_FORCE_FIXTURE_UI', '1'],
  });
  for (let step = 0; step < 2; step += 1) {
    const back = screen.getByTestId('BackButton');
    if (await back.count() === 0) break;
    await back.tap();
  }
  await expect(screen.getByTestId('mira.new-project')).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByRole('button', 'Try Mamta’s demo notebook', { exact: true }));
  await expect(screen.getByText('DEMO · Example generation, no AI request')).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Show three ideas', { exact: true }));
  const firstIdea = screen.getByText('One breakfast I actually make', { exact: true });
  await scrollToControl(screen, firstIdea);
  await expect(firstIdea).toBeVisible({ timeout: 45_000 });
  await app.screenshot('mira-demo-ideas');
  await tap(screen, screen.getByRole('button', 'Use this idea', { exact: true }).first());
  await tap(screen, screen.getByRole('button', 'Draft hook, script and caption', { exact: true }));
  const spoken = screen.getByRole('textbox', 'Spoken script', { exact: true });
  await scrollToControl(screen, spoken);
  await expect(spoken).toBeVisible({ timeout: 45_000 });
  expect((await spoken.inputValue()).length).toBeGreaterThan(0);
  await app.screenshot('mira-demo-script');
  await tap(screen, screen.getByRole('button', 'Make shot list', { exact: true }));
  const plan = screen.getByText('Your filming plan', { exact: true });
  await scrollToControl(screen, plan, 'up');
  await expect(plan).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByRole('button', 'Start filming', { exact: true }));
  await expect(screen.getByText('Shot 1 of 3', { exact: true })).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Mark filmed', { exact: true }));
  const filmedCount = screen.getByText('1 filmed by you', { exact: true });
  await scrollToControl(screen, filmedCount, 'up');
  await expect(filmedCount).toBeVisible();
  await app.screenshot('mira-demo-filming');
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-MCO_FORCE_FIXTURE_UI', '1'],
  });
  await expect(screen.getByText('1 filmed by you', { exact: true })).toBeVisible({ timeout: 45_000 });
});
