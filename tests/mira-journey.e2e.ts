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
  for (let step = 0; step < 4; step += 1) {
    const back = screen.getByTestId('BackButton');
    if (await back.count() === 0) break;
    await back.tap();
  }
  await expect(screen.getByTestId('mira.today.make')).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByRole('button', 'Try Mamta’s demo notebook', { exact: true }));
  await expect(screen.getByText('Example — not your content')).toBeVisible();
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
  const startFilming = screen.getByRole('button', 'Start filming', { exact: true });
  await scrollToControl(screen, startFilming, 'up');
  await tap(screen, startFilming);
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
  for (let step = 0; step < 4; step += 1) {
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


test('Today cards swipe into the matching filming plan and retry one failed card', async ({ app, screen, device }) => {
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, { relaunch: true, launchArguments: fixtureLaunch });
  await dismissSystemVerification(screen);
  for (let step = 0; step < 4; step += 1) {
    const back = screen.getByTestId('BackButton');
    if (await back.count() === 0) break;
    await back.tap();
  }
  const make = screen.getByTestId('mira.today.make');
  const title = (label: string) => screen.getByText(label, { exact: true, visible: true });
  const page = (number: number) => screen.getByTestId(`mira.today.page.${number}`);
  const picture = (number: number) => screen.getByTestId(`mira.shot.picture.${number}`, { visible: true });
  const swipeLeft = async () => {
    const card = await screen.getByRole('scroll-view', { visible: true }).first().boundingBox();
    await screen.swipe({ from: { x: card.x + card.width * 0.86, y: card.y + card.height * 0.73 },
      to: { x: card.x + card.width * 0.14, y: card.y + card.height * 0.73 } });
  };
  await expect(make).toBeVisible();
  await make.tap();
  await expect(page(3)).toBeVisible();
  await page(1).tap();
  await expect(title('A quick movement break')).toBeVisible();
  await expect(picture(2)).toBeVisible();
  await app.screenshot('today-movement-card');
  await swipeLeft();
  await expect(title('My simple breakfast')).toBeVisible();
  await expect(picture(2)).toBeVisible();
  await app.screenshot('today-food-card');
  await swipeLeft();
  await expect(title('A small pause in my day')).toBeVisible();
  await expect(picture(2)).toBeVisible();
  await app.screenshot('today-mindset-card');
  await tap(screen, screen.getByRole('button', 'Make this one', { exact: true, visible: true }));
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(title('Shot 1 of 3')).toBeVisible({ timeout: 45_000 });
  await expect(picture(1)).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Next', { exact: true }));
  const chosenShot = title('Say the next part');
  await scrollToControl(screen, chosenShot, 'up');
  await expect(title('Shot 2 of 3')).toBeVisible();
  await expect(chosenShot).toBeVisible();
  await expect(screen.getByRole('image', 'Shot 2, side view, 20 seconds', { exact: true })).toBeVisible();
  await app.screenshot('today-selected-filming');
  await device.openApp(bundleId, { relaunch: true, launchArguments: fixtureLaunch });
  await expect(title('Shot 2 of 3')).toBeVisible();
  await expect(title('Say the next part')).toBeVisible();
  for (let step = 0; step < 3; step += 1) await screen.getByTestId('BackButton').tap();

  const request = screen.getByTestId('mira.today.request');
  await request.fill('Demo card failure');
  await make.tap();
  await expect(page(3)).toBeVisible();
  await page(2).tap();
  const retry = screen.getByRole('button', 'Try again', { exact: true, visible: true });
  await expect(retry).toBeVisible();
  await app.screenshot('today-one-card-failure');
  await retry.tap();
  await expect(title('My simple breakfast')).toBeVisible();
  await page(1).tap();
  await expect(title('A quick movement break')).toBeVisible();
  await page(3).tap();
  await expect(title('A small pause in my day')).toBeVisible();
});

test('Your words gate leads to approved filming and the Done screen', async ({ app, screen, device }) => {
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, { relaunch: true, launchArguments: fixtureLaunch });
  await dismissSystemVerification(screen);
  for (let step = 0; step < 4; step += 1) {
    const back = screen.getByTestId('BackButton');
    if (await back.count() === 0) break;
    await back.tap();
  }
  const make = screen.getByTestId('mira.today.make');
  const title = (label: string) => screen.getByText(label, { exact: true, visible: true });
  const approve = screen.getByTestId('mira.words.approve');
  await expect(make).toBeVisible({ timeout: 45_000 });
  await make.tap();
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await screen.getByTestId('mira.today.page.1').tap();
  await expect(title('A quick movement break')).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByRole('button', 'Make this one', { exact: true, visible: true }));
  await expect(approve).toBeVisible();
  await expect(screen.getByText('Shot 1 of 3', { exact: true })).not.toBeVisible();
  await app.screenshot('words-gate');

  await device.openApp(bundleId, { relaunch: true, launchArguments: fixtureLaunch });
  await dismissSystemVerification(screen);
  await expect(approve).toBeVisible({ timeout: 45_000 });
  await app.screenshot('words-gate-after-relaunch');

  await tap(screen, screen.getByTestId('mira.words.change'));
  await expect(screen.getByTestId('mira.words.send')).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Cancel', { exact: true, visible: true }));

  await tap(screen, screen.getByTestId('mira.words.simpler'));
  const newVersion = screen.getByText('Mira\'s new version', { exact: true });
  await scrollToControl(screen, newVersion);
  await expect(newVersion).toBeVisible({ timeout: 45_000 });
  await app.screenshot('words-new-version');
  await tap(screen, screen.getByTestId('mira.words.use'));
  await expect(newVersion).not.toBeVisible();

  await tap(screen, approve);
  await expect(title('Shot 1 of 3')).toBeVisible({ timeout: 45_000 });
  await app.screenshot('words-approved-filming');
  for (let shot = 1; shot <= 3; shot += 1) {
    const header = screen.getByText(`Shot ${shot} of 3`, { exact: true });
    await scrollToControl(screen, header, 'up');
    await expect(header).toBeVisible();
    const mark = screen.getByRole('button', 'Mark filmed', { exact: true });
    await scrollToControl(screen, mark);
    await tap(screen, mark);
    if (shot < 3) {
      const next = screen.getByRole('button', 'Next', { exact: true });
      await scrollToControl(screen, next);
      await tap(screen, next);
    }
  }
  const finish = screen.getByTestId('mira.filming.finish');
  await scrollToControl(screen, finish);
  await tap(screen, finish);
  await expect(title('3 clips filmed')).toBeVisible();
  const copy = screen.getByTestId('mira.done.copy');
  await scrollToControl(screen, copy);
  await tap(screen, copy);
  await expect(screen.getByRole('button', 'Copied', { exact: true })).toBeVisible();
  const instagram = screen.getByTestId('mira.done.instagram');
  await scrollToControl(screen, instagram);
  await expect(instagram).toBeVisible();
  await app.screenshot('done-screen');
});
