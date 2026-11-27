import { test, type Device } from '@e2e-dev/mobile';
import { expect, type App, type Locator, type Screen } from 'e2e';
import { fixtureSessionArguments } from '../e2e.mira.config';
import { closeKeyboard, mobileKeyboard, scrollToControl, tapVisibleControl } from './mobile-support';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';
const english = ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-MCO_APPEARANCE', 'light'];
const fixtureLaunch = [...english, '-MCO_FORCE_FIXTURE_UI', '1', ...fixtureSessionArguments];

async function tap(screen: Screen, locator: Locator) {
  await tapVisibleControl(screen, locator);
}

async function appIsRunning(screen: Screen) {
  try {
    await screen.getByTestId('BackButton').count();
    return true;
  } catch (error) {
    if (error instanceof Error && /is not running/.test(error.message)) return false;
    throw error;
  }
}

async function waitForApp(screen: Screen) {
  for (let check = 0; check < 10; check += 1) {
    if (await appIsRunning(screen)) return true;
    await new Promise(resolve => setTimeout(resolve, 1_000));
  }
  return false;
}

async function launchMira(screen: Screen, device: Device, install = false) {
  if (install && process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, { relaunch: true, launchArguments: fixtureLaunch });
  if (!await waitForApp(screen)) {
    await device.openApp(bundleId, { launchArguments: fixtureLaunch });
    expect(await waitForApp(screen)).toBe(true);
  }
  await dismissSystemVerification(screen);
}

async function tabControl(screen: Screen, name: string) {
  const tab = screen.getByRole('tab', name, { exact: true });
  if (await tab.count() > 0) return tab.first();
  return screen.getByRole('tablist', 'Tab Bar', { exact: true }).getByRole('button', name, { exact: true });
}

async function openTab(screen: Screen, name: string) {
  await (await tabControl(screen, name)).tap();
}

async function sectionControl(screen: Screen, name: string) {
  const tab = screen.getByRole('tab', name, { exact: true });
  if (await tab.count() > 0) return tab.first();
  return screen.getByRole('button', name, { exact: true }).first();
}

async function menuControl(screen: Screen, name: string) {
  const popUp = screen.getByRole('pop-up-button', name, { exact: true });
  if (await popUp.count() > 0) return popUp.first();
  return screen.getByRole('button', name, { exact: true }).first();
}

async function fillText(field: Locator, text: string) {
  try {
    await field.fill(text);
  } catch (error) {
    if (!(error instanceof Error && /could not confirm the typed text/.test(error.message))) throw error;
    await field.fill(text);
  }
  if (text.length > 0) expect(await field.inputValue()).toBe(text);
}

async function dismissSystemVerification(screen: Screen) {
  const alert = screen.getByRole('alert', /Apple.Account Verification/);
  if (await alert.count() === 0) return;
  await alert.getByRole('button', 'Not Now', { exact: true }).tap();
  await expect(alert).not.toBeVisible();
}

async function backOut(screen: Screen) {
  for (let step = 0; step < 4; step += 1) {
    const back = screen.getByTestId('BackButton');
    if (await back.count() === 0) break;
    await back.tap();
  }
}

async function openToday(screen: Screen) {
  await backOut(screen);
  await openTab(screen, 'Today');
  await backOut(screen);
  await stopLeftoverIdeas(screen);
}

async function stopLeftoverIdeas(screen: Screen) {
  for (let batch = 0; batch < 3; batch += 1) {
    const open = screen.getByTestId('mira.today.open');
    if (await open.count() === 0) return;
    await open.tap();
    await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
    const busy = screen.getByRole('button', /^Idea \d of 3, (waiting to start|Mira is making it)$/);
    for (let idea = 0; idea < 3 && await busy.count() > 0; idea += 1) {
      await busy.first().tap();
      await (await menuControl(screen, 'More')).tap();
      await screen.getByRole('button', 'Stop this idea', { exact: true }).tap();
      await expect(screen.getByText('This idea was stopped.', { exact: true, visible: true })).toBeVisible();
    }
    await backOut(screen);
  }
}

test('demo moves from an idea to a saved filming plan', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await openToday(screen);
  await expect(screen.getByTestId('mira.today.make')).toBeVisible({ timeout: 45_000 });
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  await tap(screen, screen.getByTestId('mira.profile.demo'));
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
  await launchMira(screen, device);
  await expect(screen.getByText('1 filmed by you', { exact: true })).toBeVisible({ timeout: 45_000 });
});

test('Profile shows Allow and Decline immediately after each choice', async ({ app, screen, device }) => {
  test.skip(process.env.MIRA_E2E_CONSENT_FIXTURE !== '1', 'Use an isolated Debug app with a synthetic paired account.');
  expect(bundleId).toBe('com.prateekranka.creatorcontenthelper.codexverify');
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, { relaunch: true, launchArguments: english });
  await dismissSystemVerification(screen);
  await openToday(screen);
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
  await launchMira(screen, device, true);
  await openToday(screen);
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
  await tap(screen, screen.getByTestId('mira.today.makeCard.3'));
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
  await launchMira(screen, device);
  await expect(title('Shot 2 of 3')).toBeVisible();
  await expect(title('Say the next part')).toBeVisible();
  for (let step = 0; step < 3; step += 1) await screen.getByTestId('BackButton').tap();

  const request = screen.getByTestId('mira.today.request');
  await fillText(request, 'Demo card failure');
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
  await launchMira(screen, device, true);
  await openToday(screen);
  const make = screen.getByTestId('mira.today.make');
  const title = (label: string) => screen.getByText(label, { exact: true, visible: true });
  const approve = screen.getByTestId('mira.words.approve');
  await expect(make).toBeVisible({ timeout: 45_000 });
  await make.tap();
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await screen.getByTestId('mira.today.page.1').tap();
  await expect(title('A quick movement break')).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByTestId('mira.today.makeCard.1'));
  await expect(approve).toBeVisible();
  await expect(screen.getByText('Shot 1 of 3', { exact: true })).not.toBeVisible();
  await app.screenshot('words-gate');

  await launchMira(screen, device);
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
  if (fixtureSessionArguments.length) {
    const updating = screen.getByText('Updating your shots…', { exact: true, visible: true });
    await expect(updating).toBeVisible();
    await app.screenshot('s2-words-updating-shots');
  }
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
  await bottomAboveTabs(app, screen, title('Mira does not post. You post in Instagram.'), 'done-screen');
});

const look = process.env.MIRA_E2E_LOOK ?? 'light';

test('Today has one question, chips, Continue rules and start options in Profile', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await openToday(screen);
  const make = screen.getByTestId('mira.today.make');
  const request = screen.getByTestId('mira.today.request');
  await expect(make).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByText('What can you film today?', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('mira.today.mic')).toBeVisible();
  await expect(screen.getByText('Plan step by step', { exact: true })).not.toBeVisible();
  await expect(screen.getByText('Try Mamta’s demo notebook', { exact: true })).not.toBeVisible();
  await fillText(request, '');
  await closeKeyboard(screen, request);
  await app.screenshot(`d1-today-${look}`);

  const chip = (id: string) => screen.getByTestId(`mira.today.chip.${id}`);
  const keyboard = mobileKeyboard(screen);
  await request.tap();
  await expect(keyboard).toBeVisible();
  await chip('gym').tap();
  await expect(keyboard).not.toBeVisible();
  expect(await request.inputValue()).toBe('At the gym');
  await chip('home').tap();
  expect(await request.inputValue()).toBe('At home');
  await chip('10min').tap();
  expect(await request.inputValue()).toBe('At home, 10 minutes');
  await chip('20min').tap();
  expect(await request.inputValue()).toBe('At home, 20 minutes');
  await chip('20min').tap();
  expect(await request.inputValue()).toBe('At home');
  await chip('outside').tap();
  expect(await request.inputValue()).toBe('Outside');
  await app.screenshot(`d1-today-chips-${look}`);
  await fillText(request, '');
  await expect(keyboard).toBeVisible();
  await screen.getByText(/^Good (morning|afternoon|evening)[,.]/, { visible: true }).tap();
  await expect(keyboard).not.toBeVisible();

  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  const stepByStep = screen.getByTestId('mira.profile.stepByStep');
  await scrollToControl(screen, stepByStep);
  await expect(screen.getByText('Opens in the Projects tab. You choose each part yourself.', { exact: true })).toBeVisible();
  await app.screenshot(`d1-profile-start-options-${look}`);
  await tap(screen, stepByStep);
  await expect(screen.getByText('Choosing an idea', { exact: true })).toBeVisible({ timeout: 45_000 });
  await openTab(screen, 'Today');
  await expect(make).toBeVisible();
  await expect(screen.getByText('Untitled Reel', { exact: true })).not.toBeVisible();

  await fillText(request, 'Demo slow cards');
  await expect(keyboard).toBeVisible();
  await app.screenshot('today-keyboard-open');
  await closeKeyboard(screen, request);
  expect(await request.inputValue()).toBe('Demo slow cards');
  await expect(make).toBeVisible();
  await expect(make).toBeEnabled();
  const makeBox = await make.boundingBox();
  const pageBox = await screen.getByRole('scroll-view', { visible: true }).first().boundingBox();
  const tabBox = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  expect(makeBox.y).toBeGreaterThanOrEqual(pageBox.y);
  expect(makeBox.y + makeBox.height).toBeLessThanOrEqual(Math.min(pageBox.y + pageBox.height, tabBox.y));
  await app.screenshot('today-keyboard-closed');
  await make.tap();
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await expect(screen.getByText('About 1 minute', { exact: true })).toBeVisible();
  await expect(screen.getByText('Mira is making idea 1 of 3', { exact: true })).toBeVisible();
  await app.screenshot(`d1-wait-${look}`);
  await expect(screen.getByText('A quick movement break', { exact: true, visible: true })).toBeVisible({ timeout: 30_000 });
  await app.screenshot(`d1-first-card-ready-${look}`);
  await expect(screen.getByText('About 1 minute', { exact: true })).not.toBeVisible({ timeout: 40_000 });
  await screen.getByTestId('mira.today.page.3').tap();
  await expect(screen.getByText('3 of 3', { exact: true })).toBeVisible();
  await expect(screen.getByText('A small pause in my day', { exact: true, visible: true })).toBeVisible();
  await app.screenshot(`d1-card-3-of-3-${look}`);
  await screen.getByTestId('mira.today.page.2').tap();
  await expect(screen.getByText('2 of 3', { exact: true })).toBeVisible();
  await expect(screen.getByText('My simple breakfast', { exact: true, visible: true })).toBeVisible();
  await screen.getByTestId('BackButton').tap();
  await expect(screen.getByTestId('mira.today.continue')).toBeVisible();
  await app.screenshot(`d1-today-continue-${look}`);
});

async function startTodayCard(screen: Screen, request: string, card: number) {
  await openToday(screen);
  const make = screen.getByTestId('mira.today.make');
  await expect(make).toBeVisible({ timeout: 45_000 });
  const field = screen.getByTestId('mira.today.request');
  await fillText(field, request);
  await closeKeyboard(screen, field);
  await make.tap();
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await screen.getByTestId(`mira.today.page.${card}`).tap();
}

async function chooseTodayCard(screen: Screen, card: number, title: string) {
  await startTodayCard(screen, '', card);
  await expect(screen.getByText(title, { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByTestId(`mira.today.makeCard.${card}`));
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
}

async function openProjectFromList(screen: Screen, title: string) {
  await openTab(screen, 'Projects');
  await backOut(screen);
  const row = screen.getByText(title, { exact: true, visible: true }).first();
  await scrollToControl(screen, row);
  await row.tap();
}

test('S1 B1 the Projects shot list asks her to approve the words before filming', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await chooseTodayCard(screen, 1, 'A quick movement break');
  await openProjectFromList(screen, 'A quick movement break');
  const back = screen.getByTestId('BackButton');
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
  await back.tap();
  const shotsSection = await sectionControl(screen, 'Shots');
  await scrollToControl(screen, shotsSection, 'up');
  await tap(screen, shotsSection);
  const approveLink = screen.getByTestId('mira.shots.approve');
  await scrollToControl(screen, approveLink, 'up');
  await expect(approveLink).toBeVisible();
  await expect(screen.getByRole('button', 'Start filming', { exact: true })).not.toBeVisible();
  await app.screenshot(`s1-b1-shots-approve-${look}`);
  await tap(screen, approveLink);
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await back.tap();
  await back.tap();
  await scrollToControl(screen, shotsSection, 'up');
  await tap(screen, shotsSection);
  const continueLink = screen.getByRole('button', 'Continue filming', { exact: true });
  await scrollToControl(screen, continueLink, 'up');
  await expect(continueLink).toBeVisible();
  await expect(screen.getByTestId('mira.shots.approve')).not.toBeVisible();
  await app.screenshot(`s1-b1-shots-approved-${look}`);
});

test('S1 B2 open filming closes its controls when the approval is undone', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await chooseTodayCard(screen, 2, 'My simple breakfast');
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await openProjectFromList(screen, 'My simple breakfast');
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible();
  await screen.getByTestId('BackButton').tap();
  await screen.getByRole('button', 'Plan options', { exact: true }).tap();
  await screen.getByRole('button', 'Undo last content change', { exact: true }).tap();
  await openTab(screen, 'Today');
  const message = screen.getByTestId('mira.approveFirst.message');
  await expect(message).toBeVisible();
  await expect(screen.getByRole('button', 'Mark filmed', { exact: true })).not.toBeVisible();
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).not.toBeVisible();
  await app.screenshot(`s1-b2-filming-gate-${look}`);

  await launchMira(screen, device);
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible({ timeout: 45_000 });
  await expect(message).not.toBeVisible();
  await app.screenshot(`s1-b2-relaunch-words-${look}`);
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await openTab(screen, 'Projects');
  await screen.getByRole('button', 'Plan options', { exact: true }).tap();
  await screen.getByRole('button', 'Undo last content change', { exact: true }).tap();
  await openTab(screen, 'Today');
  await expect(message).toBeVisible();
  await tap(screen, screen.getByTestId('mira.approveFirst.words'));
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  const mark = screen.getByRole('button', 'Mark filmed', { exact: true });
  await scrollToControl(screen, mark);
  await expect(mark).toBeVisible();
  await screen.getByTestId('BackButton').tap();
  await expect(screen.getByTestId('mira.words.start')).toBeVisible();
});

test('S1 B3 Continue says Approve your words until she approves', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await chooseTodayCard(screen, 3, 'A small pause in my day');
  await openToday(screen);
  const continueCard = screen.getByTestId('mira.today.continue');
  await expect(continueCard).toBeVisible();
  await expect(screen.getByText('Approve your words', { exact: true })).toBeVisible();
  await expect(screen.getByText('Start filming', { exact: true })).not.toBeVisible();
  await app.screenshot(`s1-b3-continue-approve-${look}`);
  await continueCard.tap();
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await openToday(screen);
  await expect(screen.getByText('Continue filming', { exact: true })).toBeVisible();
  await openTab(screen, 'Projects');
  await backOut(screen);
  await expect(screen.getByText('Filming · Continue filming', { exact: true }).first()).toBeVisible();
  await app.screenshot(`s1-b3-projects-stage-${look}`);
});

test('S1 B4 a full server shows Waiting to start and sends the idea again by itself', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await startTodayCard(screen, 'Demo busy server', 3);
  const waiting = screen.getByTestId('mira.today.waiting.3');
  await expect(waiting).toBeVisible({ timeout: 10_000 });
  await expect(screen.getByText('Mira is making idea 3 of 3', { exact: true, visible: true })).not.toBeVisible();
  await app.screenshot(`s1-b4-waiting-${look}`);
  await screen.getByTestId('BackButton').tap();
  const open = screen.getByTestId('mira.today.open');
  await expect(open).toBeVisible();
  await expect(screen.getByTestId('mira.today.make')).not.toBeVisible();
  await app.screenshot(`s1-b4-today-open-${look}`);
  await open.tap();
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await expect(screen.getByText('About 1 minute', { exact: true })).not.toBeVisible({ timeout: 45_000 });
  await screen.getByTestId('mira.today.page.3').tap();
  await expect(screen.getByText('A small pause in my day', { exact: true, visible: true })).toBeVisible();
  await expect(waiting).not.toBeVisible();
  await app.screenshot(`s1-b4-all-ready-${look}`);
  await screen.getByTestId('BackButton').tap();
  await expect(screen.getByTestId('mira.today.make')).toBeVisible();
});

test('S1 B5 Stop on an idea that the server never took ends as stopped', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await startTodayCard(screen, 'Demo stop unknown', 3);
  await expect(screen.getByTestId('mira.today.waiting.3')).toBeVisible({ timeout: 10_000 });
  await (await menuControl(screen, 'More')).tap();
  await screen.getByRole('button', 'Stop this idea', { exact: true }).tap();
  await expect(screen.getByText('This idea was stopped.', { exact: true, visible: true })).toBeVisible();
  await expect(screen.getByRole('button', 'Try again', { exact: true, visible: true })).toBeVisible();
  await expect(screen.getByTestId('mira.today.waiting.3')).not.toBeVisible();
  await app.screenshot(`s1-b5-stopped-${look}`);
  await screen.getByTestId('mira.today.page.1').tap();
  await expect(screen.getByText('A quick movement break', { exact: true, visible: true })).toBeVisible();
  await screen.getByTestId('BackButton').tap();
  await expect(screen.getByTestId('mira.today.make')).toBeVisible();
});

test('Profile Look setting', async ({ app, screen, device }) => {
  await launchMira(screen, device, true);
  await backOut(screen);
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  const setting = screen.getByTestId('mira.profile.look');
  await expect(setting).toBeVisible();
  for (const appearance of ['Dark', 'Light']) {
    const choice = setting.getByRole('button', appearance, { exact: true });
    await choice.tap();
    await expect(choice).toBeSelected();
    await app.screenshot(`profile-look-${appearance.toLowerCase()}`);
  }
});

test('crash log', async ({ app, screen, device }) => {
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: [...fixtureLaunch, '-MCO_DEBUG_CRASH', '1'],
  });
  await expect.poll(() => appIsRunning(screen), {
    timeout: 20_000,
    interval: 1_000,
    message: 'Mira should stop running after the deliberate debug crash.',
  }).toBe(false);

  await launchMira(screen, device);
  await backOut(screen);
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  const connect = screen.getByText('Connect account', { exact: true });
  await scrollToControl(screen, connect);
  const reports = screen.getByTestId('mira.profile.problemReports');
  if (await reports.count() > 0) {
    await scrollToControl(screen, reports);
    await expect(reports.getByText('Problem reports', { exact: true })).toBeVisible();
    await app.screenshot('profile-problem-reports-visible');
  } else {
    await app.screenshot('profile-problem-reports-absent');
  }
});

async function bottomAboveTabs(app: App, screen: Screen, end: Locator, label: string) {
  await scrollToControl(screen, end);
  const tabs = screen.getByRole('tablist', 'Tab Bar', { exact: true, visible: true });
  const tabBox = await tabs.boundingBox();
  const box = await end.boundingBox();
  expect(box!.y).toBeGreaterThan(0);
  expect(box!.y + box!.height).toBeLessThanOrEqual(tabBox!.y - 8);
  await app.screenshot(label);
}

test('S2 Plan step by step uses plain microphone words and scrolls above the tab bar', async ({ app, screen, device }) => {
  await launchMira(screen, device);
  await openToday(screen);
  const continueCard = screen.getByTestId('mira.today.continue');
  const todayEnd = await continueCard.count() ? continueCard : screen.getByTestId('mira.today.make');
  await bottomAboveTabs(app, screen, todayEnd, 's2-today-bottom');
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  await tap(screen, screen.getByTestId('mira.profile.stepByStep'));
  const note = screen.getByText('Your voice stays on this phone. Check the words before you send them.', { exact: true });
  await bottomAboveTabs(app, screen, note, 's2-microphone-note');
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Share current plan', { exact: true }), 's2-step-by-step-bottom');
});

test('S2 resumes cards, words, filming plan and filming with content clear of the tab bar', async ({ app, screen, device }) => {
  await launchMira(screen, device);
  await startTodayCard(screen, '', 1);
  const card = screen.getByTestId('mira.today.makeCard.1');
  await expect(card).toBeVisible();
  await launchMira(screen, device);
  await expect(screen.getByTestId('mira.today.page.1')).toBeVisible();
  await screen.getByTestId('mira.today.page.1').tap();
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Change something', { exact: true, visible: true }), 's2-resume-today-cards');
  await tap(screen, card);
  const approve = screen.getByTestId('mira.words.approve');
  await launchMira(screen, device);
  await expect(approve).toBeVisible();
  await bottomAboveTabs(app, screen, screen.getByTestId('mira.words.change'), 's2-resume-words');

  await openTab(screen, 'Projects');
  await backOut(screen);
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Delete', { exact: true }).last(), 's2-projects-bottom');
  const row = screen.getByText('A quick movement break', { exact: true }).first();
  await scrollToControl(screen, row, 'up');
  await row.tap();
  await screen.getByTestId('BackButton').tap();
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Share current plan', { exact: true }), 's2-script-bottom');
  const shots = await sectionControl(screen, 'Shots');
  await scrollToControl(screen, shots, 'up');
  await tap(screen, shots);
  const plan = screen.getByText('Your filming plan', { exact: true });
  await expect(plan).toBeVisible();
  await launchMira(screen, device);
  await expect(plan).toBeVisible();
  const opening = screen.getByText("Here's a movement I do between tasks.", { exact: true }).first();
  await bottomAboveTabs(app, screen, opening, 's2-shot-one-text');
  await bottomAboveTabs(app, screen, screen.getByText('More filming details', { exact: true }).last(), 's2-resume-plan');

  const approval = screen.getByTestId('mira.shots.approve');
  await scrollToControl(screen, approval, 'up');
  await tap(screen, approval);
  await tap(screen, approve);
  const filming = screen.getByText('Shot 1 of 3', { exact: true });
  await expect(filming).toBeVisible();
  await launchMira(screen, device);
  await expect(filming).toBeVisible();
  await bottomAboveTabs(app, screen,
    screen.getByText('Mira does not record or analyse footage. Filmed is progress you report yourself.', { exact: true }),
    's2-resume-filming');
});
