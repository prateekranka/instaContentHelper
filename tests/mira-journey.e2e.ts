import { test } from '@e2e-dev/mobile';
import { expect, type Locator, type Screen } from 'e2e';
import { scrollToControl, tapVisibleControl } from './mobile-support';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';
const english = ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US'];
const fixtureLaunch = [...english, '-MCO_FORCE_FIXTURE_UI', '1'];

async function tap(screen: Screen, locator: Locator) {
  await tapVisibleControl(screen, locator);
}

async function dismissSystemVerification(screen: Screen) {
  const alert = screen.getByRole('alert', /Apple.Account Verification/);
  if (await alert.count() === 0) return;
  await alert.getByRole('button', 'Not Now', { exact: true }).tap();
  await expect(alert).not.toBeVisible();
}

test('demo moves from an idea to a saved filming plan', async ({ app, screen, device }) => {
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: fixtureLaunch,
  });
  await dismissSystemVerification(screen);
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
  const shot = screen.getByText('Shot 1', { exact: true });
  await scrollToControl(screen, shot);
  await expect(shot).toBeVisible();
  for (const field of ['Phone position', 'Distance', 'Framing', 'Seconds', 'Words to say', 'On-screen text']) {
    const label = screen.getByText(field, { exact: true }).first();
    await scrollToControl(screen, label);
    await expect(label).toBeVisible();
  }
  const onScreenText = screen.getByText('My everyday routine', { exact: true });
  await scrollToControl(screen, onScreenText);
  await expect(onScreenText).toBeVisible();
  await app.screenshot('mira-demo-shot-list');
  for (const value of ['5 seconds in the final video', 'Head and shoulders', 'One arm’s length',
    'Stand the phone on a steady shelf at eye level.']) {
    const detail = screen.getByText(value, { exact: true }).first();
    await scrollToControl(screen, detail, 'up');
    await expect(detail).toBeVisible();
  }
  await tap(screen, screen.getByRole('button', 'Start filming', { exact: true }));
  await expect(screen.getByText('Shot 1 of 3', { exact: true })).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Mark filmed', { exact: true }));
  const filmedCount = screen.getByText('1 filmed by you', { exact: true });
  await scrollToControl(screen, filmedCount, 'up');
  await expect(filmedCount).toBeVisible();
  await app.screenshot('mira-demo-filming');
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: fixtureLaunch,
  });
  await dismissSystemVerification(screen);
  await expect(screen.getByText('1 filmed by you', { exact: true })).toBeVisible({ timeout: 45_000 });
});

test('Profile shows Allow and Decline immediately after each choice', async ({ app, screen, device }) => {
  test.skip(process.env.MIRA_E2E_CONSENT_FIXTURE !== '1', 'Use an isolated Debug app with a synthetic paired account.');
  expect(bundleId).toBe('com.prateekranka.creatorcontenthelper.codexverify');
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, { relaunch: true, launchArguments: english });
  await dismissSystemVerification(screen);
  for (let step = 0; step < 2; step += 1) {
    const back = screen.getByTestId('BackButton');
    if (await back.count() === 0) break;
    await back.tap();
  }
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  const review = screen.getByText('Review AI data permission', { exact: true });
  await scrollToControl(screen, review);
  await expect(screen.getByText('Not decided yet', { exact: true })).toBeVisible();
  for (const [action, status] of [
    ['Allow AI partners', 'Allowed'],
    ['Decline AI permission', 'Not allowed yet'],
  ]) {
    await review.tap();
    await tap(screen, screen.getByRole('button', action, { exact: true }));
    await expect(screen.getByText(status, { exact: true })).toBeVisible();
    await app.screenshot(`mira-profile-${status}`);
  }
});
