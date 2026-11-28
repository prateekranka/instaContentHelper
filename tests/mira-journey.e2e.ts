import { test, type Device } from '@e2e-dev/mobile';
import { expect, type App, type Locator, type Screen } from 'e2e';
import { d2FixtureArguments, fixtureSessionArguments } from '../e2e.mira.config';
import { appIsRunning, closeKeyboard, mobileKeyboard, scrollToControl, tapVisibleControl, waitForMobileApp } from './mobile-support';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';
const english = ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-MCO_APPEARANCE', 'light'];
let sampleSession = '';
test.beforeEach(() => {
  sampleSession = fixtureSessionArguments.length ? `${fixtureSessionArguments[1]}-${Date.now()}` : '';
});

function fixtureLaunch() {
  return [...english, '-MCO_FORCE_FIXTURE_UI', '1', ...d2FixtureArguments,
    ...(sampleSession ? ['-MCO_QA_SESSION', sampleSession] : [])];
}

if (fixtureSessionArguments.length !== 2 || !fixtureSessionArguments[1]?.trim()) {
  throw new Error('Set MIRA_E2E_FIXTURE_SESSION before running the Mira sample suite.');
}

async function tap(screen: Screen, locator: Locator) {
  await tapVisibleControl(screen, locator);
}

async function launchMira(app: App, screen: Screen, device: Device, install = false) {
  if (install && process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  if (sampleSession) await device.openApp(bundleId, { relaunch: true, launchArguments: fixtureLaunch() });
  else await app.open();
  await waitForMobileApp(screen);
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
  await openTab(screen, 'Home');
  await backOut(screen);
  await expect(screen.getByTestId('mira.fixture.profile')).toBeVisible();
}

async function stopLeftoverIdeas(screen: Screen) {
  await expect(screen.getByTestId('mira.fixture.profile')).toBeVisible();
  const batch = screen.getByTestId('mira.today.continue');
  await expect(batch).toHaveCount(1);
  await tap(screen, batch);
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  const busy = screen.getByRole('button', /^Idea \d of 3, (waiting to start|Mira is making it|Waiting to try again)$/);
  for (let idea = 0; idea < 3 && await busy.count() > 0; idea += 1) {
    await busy.first().tap();
    await (await menuControl(screen, 'More')).tap();
    await screen.getByRole('button', 'Stop this idea', { exact: true }).tap();
    await expect(screen.getByText('This idea was stopped.', { exact: true, visible: true }).first()).toBeVisible();
  }
  await backOut(screen);
}

const homeRequest = (screen: Screen) =>
  screen.getByRole('textbox', 'What can you film today?', { exact: true });
const homeIdeaButton = (screen: Screen, name: string | RegExp) =>
  screen.getByRole('scroll-view').getByRole('button', name, { exact: true });
const homeMic = (screen: Screen) => homeIdeaButton(screen, /^(Speak instead of typing|Open Settings)$/);
const makeToday = (screen: Screen) => screen.getByRole('button', "Make today's Reel", { exact: true });

async function d2Fixture(scenario: string, update: Record<string, string | number | boolean> = {}) {
  const address = process.env.MIRA_D2_FIXTURE_CONTROL;
  test.skip(!address || !process.env.MIRA_E2E_D2_ENDPOINT, 'Set both D2 fixture endpoints for these phone scenarios.');
  const response = await fetch(`${address}/control`, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ scenario, ...update }),
  });
  expect(response.ok).toBe(true);
  return await response.json() as {
    card: number; starts: number; prematureOptIns: number; optedIn: number;
    expiredGets: number; freshGets: number; refreshes: number;
  }[];
}

const d2Step = (screen: Screen, name: string) => screen.getByLabel(name, { exact: true, visible: true });
const d2Picture = (screen: Screen, kind: string, shot: number) =>
  screen.getByRole('image', `${kind} for shot ${shot}`, { exact: true, visible: true });

test('E1 Home shows the idea card with no work, including after saving an empty Reel', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await openToday(screen);
  const idea = screen.getByText('Nothing planned today. Want an idea?', { exact: true });
  await expect(idea).toBeVisible();
  await expect(homeRequest(screen)).toBeVisible();
  await expect(homeMic(screen)).toBeVisible();
  await expect(homeIdeaButton(screen, 'Home')).toBeVisible();
  await expect(screen.getByText("How you're doing", { exact: true })).not.toBeVisible();
  await app.screenshot('e1-home-empty');
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  await tap(screen, screen.getByTestId('mira.profile.stepByStep'));
  await expect(screen.getByText('1 / 6', { exact: true })).toBeVisible();
  await openToday(screen);
  await expect(idea).toBeVisible();
  await expect(screen.getByTestId('mira.today.continue')).toHaveCount(0);
});

test('E1 shows a Continue card and the words action for each unfinished Reel', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await chooseTodayCard(screen, 1, 'A quick movement break');
  await chooseTodayCard(screen, 2, 'My simple breakfast');
  await openToday(screen);
  const cards = screen.getByTestId('mira.today.continue');
  await expect(cards).toHaveCount(2);
  await expect(cards.first()).toHaveAccessibleName('Approve your words');
  await expect(cards.last()).toHaveAccessibleName('Approve your words');
  const progress = screen.getByLabel('Reel progress', { exact: true }).first();
  await expect(progress).toBeAttached();
  await expect(screen.getByText('You have 2 Reels in progress.', { exact: true })).toBeVisible();
  await app.screenshot('e1-home-with-work');
  await tap(screen, cards.first());
  await expect(screen.getByText('2 / 6', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('mira.words.approve')).toBeAttached();
});

test('E1 tabs share the Ask Mira bar and My Brand keeps archived Reels reachable', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await openToday(screen);
  for (const name of ['Home', 'Deals', 'My Brand']) await expect(await tabControl(screen, name)).toBeVisible();
  await bottomAboveTabs(app, screen, makeToday(screen), 'e1-home-ask-clearance');
  await openTab(screen, 'Deals');
  const help = screen.getByText('Share a brand brief to Mira', { exact: true });
  await bottomAboveTabs(app, screen, help, 'e1-deals-ask-clearance');
  await sendAsk(screen, 'Caption: Sample breakfast at home');
  const draft = screen.getByRole('textbox', 'Original brand requirements', { exact: true });
  expect(await draft.inputValue()).toBe('Caption: Sample breakfast at home');
  await app.screenshot('e1-deals-brief-draft');
  await tap(screen, screen.getByRole('button', 'Save as a Reel brief', { exact: true }));
  await expect(screen.getByText('1 / 6', { exact: true })).toBeVisible();
  await backOut(screen);
  await expandAllReels(screen);
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Archive', { exact: true }), 'e1-my-brand-all-reels');
  await tap(screen, screen.getByRole('button', 'Archive', { exact: true }));
  const archived = screen.getByRole('switch', 'Show archived projects', { exact: true });
  const nativeSwitch = screen.getByRole('switch', /^[01]$/);
  await (await nativeSwitch.count() === 1 ? nativeSwitch : archived).check();
  await expect(archived).toBeChecked();
  await expect(screen.getByText('Untitled Reel', { exact: true })).toBeVisible();
  await tap(screen, screen.getByText('Untitled Reel', { exact: true }));
  await expect(screen.getByTestId('mira.ask.bar', { visible: true })).toBeVisible();
  await app.screenshot('e1-archived-reel-ask');
});

test('E1 resumes Words, reads the one-page shot list, and goes to the saved shot', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await chooseTodayCard(screen, 1, 'A quick movement break');
  const step = screen.getByTestId('mira.task.step');
  await expect(step).toHaveText('2 / 6');
  await sendAsk(screen, 'Use simpler words for the opening');
  const note = screen.getByTestId('mira.words.note');
  await scrollToControl(screen, note);
  expect(await note.inputValue()).toBe('Use simpler words for the opening');
  await tap(screen, screen.getByRole('button', 'Cancel', { exact: true }));
  await launchMira(app, screen, device);
  await expect(step).toHaveText('2 / 6');
  await app.screenshot('e1-words-step');
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await expect(step).toHaveText('3 / 6');
  await launchMira(app, screen, device);
  await expect(step).toHaveText('3 / 6');
  const plan = screen.getByText('Your filming plan', { exact: true });
  await scrollToControl(screen, plan);
  for (const label of ['Where', 'What to bring', 'Audio']) {
    await expect(screen.getByText(label, { exact: true }).first()).toBeAttached();
  }
  await app.screenshot('e1-shot-list-summary');
  const shoot = screen.getByTestId('mira.shots.film');
  await bottomAboveTabs(app, screen, shoot, 'e1-shot-list-action');
  await expect(shoot).toHaveAccessibleName("Got it, I'll go shoot");
  await shoot.tap();
  await expect(step).toHaveText('4 / 6');
  await tap(screen, screen.getByRole('button', 'Mark filmed', { exact: true }));
  await tap(screen, screen.getByRole('button', 'Next', { exact: true }));
  await launchMira(app, screen, device);
  await expect(step).toHaveText('4 / 6');
  await expect(screen.getByText('Shot 2 of 3', { exact: true })).toBeVisible();
  await expect(screen.getByText('1 filmed by you', { exact: true })).toBeVisible();
  await app.screenshot('e1-resume-shot-two');
});

test('D2 wait follows the server steps and opens the first ready card', async ({ app, screen, device }) => {
  const scenario = 'Demo D2 steps';
  await d2Fixture(scenario, { begin: true });
  await launchMira(app, screen, device);
  await startTodayCard(screen, scenario, 1);
  await expect.poll(async () => (await d2Fixture(scenario)).length).toBe(3);
  const idea = d2Step(screen, 'Finding an idea, done');
  await expect(idea).not.toBeVisible();
  await d2Fixture(scenario, { card: 1, step: 'idea_ready' });
  await expect(idea).toBeVisible();
  await expect(d2Step(screen, 'Writing your words, now')).toBeVisible();
  await expect(d2Step(screen, 'Planning 3 shots, next')).toBeVisible();
  await app.screenshot('wait-idea-ready');
  await d2Fixture(scenario, { card: 1, step: 'script_ready' });
  await expect(d2Step(screen, 'Writing your words, done')).toBeVisible();
  await expect(d2Step(screen, 'Planning 3 shots, now')).toBeVisible();
  await app.screenshot('wait-script-ready');
  await d2Fixture(scenario, { card: 1, step: 'storyboard_ready' });
  await expect(d2Step(screen, 'Planning 3 shots, done')).toBeVisible();
  await expect(screen.getByTestId('mira.today.makeCard.1')).not.toBeVisible();
  await app.screenshot('wait-storyboard-ready');
  await d2Fixture(scenario, { card: 1, finish: true });
  await expect(screen.getByTestId('mira.today.makeCard.1')).toBeVisible();
  await expect(screen.getByTestId('mira.today.page.2')).toHaveAccessibleName('Idea 2 of 3, Mira is making it');
  await d2Fixture(scenario, { finish: true });
  await expect(screen.getByRole('button', /^Idea [1-3] of 3, ready$/)).toHaveCount(3);
});

test('D2 legacy reply without a step keeps the simple wait screen', async ({ app, screen, device }) => {
  const scenario = 'Demo D2 legacy';
  await d2Fixture(scenario, { begin: true });
  await launchMira(app, screen, device);
  await startTodayCard(screen, scenario, 1);
  await expect.poll(async () => (await d2Fixture(scenario)).length).toBe(3);
  await expect(screen.getByText('Mira is making idea 1 of 3', { exact: true, visible: true })).toBeVisible();
  await expect(screen.getByLabel(/^Finding an idea,/)).not.toBeVisible();
  await expect(screen.getByText('About 1 minute', { exact: true })).toBeVisible();
  await app.screenshot('wait-legacy');
  await d2Fixture(scenario, { finish: true });
  await expect(screen.getByRole('button', /^Idea [1-3] of 3, ready$/)).toHaveCount(3);
  await screen.getByTestId('mira.today.page.1').tap();
  await expect(screen.getByTestId('mira.today.makeCard.1')).toBeVisible();
});

test('D2 previews keep drawn frames and refresh an expired picture URL', async ({ app, screen, device }) => {
  const scenario = 'Demo D2 pictures';
  await d2Fixture(scenario, { begin: true });
  await launchMira(app, screen, device);
  await startTodayCard(screen, scenario, 1);
  await expect.poll(async () => (await d2Fixture(scenario)).length).toBe(3);
  await d2Fixture(scenario, { card: 1, previews: 'pending' });
  await d2Fixture(scenario, { card: 1, finish: true });
  const stats = async () => (await d2Fixture(scenario)).find(item => item.card === 1);
  await expect.poll(async () => (await stats())?.optedIn ?? 0).toBeGreaterThan(0);
  await expect(screen.getByTestId('mira.today.makeCard.1')).toBeVisible();
  await expect(d2Picture(screen, 'Drawn frame', 1)).toBeVisible();
  await app.screenshot('drawn-placeholder');
  await d2Fixture(scenario, { card: 1, previews: 'ready' });
  await expect(d2Picture(screen, 'AI picture', 1)).toBeVisible({ timeout: 45_000 });
  await expect(d2Picture(screen, 'Drawn frame', 2)).toBeVisible();
  await expect(d2Picture(screen, 'Drawn frame', 3)).toBeVisible();
  await app.screenshot('ai-picture-and-drawn-backup');
  const counts = await stats();
  expect(counts?.expiredGets ?? 0).toBeGreaterThan(0);
  expect(counts?.refreshes ?? 0).toBeGreaterThan(0);
  expect(counts?.freshGets ?? 0).toBeGreaterThan(0);
  expect((await d2Fixture(scenario, { finish: true })).map(({ starts, prematureOptIns }) => [starts, prematureOptIns]))
    .toEqual([[1, 0], [1, 0], [1, 0]]);
  await tap(screen, screen.getByTestId('mira.today.makeCard.1'));
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await startShooting(screen);
  await expect(d2Picture(screen, 'AI picture', 1)).toBeVisible();
  await app.screenshot('fixture-filming-ai-picture');
  await launchMira(app, screen, device);
  await expect(screen.getByText('Shot 1 of 3', { exact: true })).toBeVisible();
  await expect(d2Picture(screen, 'AI picture', 1)).toBeVisible({ timeout: 45_000 });
  await app.screenshot('fixture-reopened-filming-ai-picture');
  expect((await stats())?.starts).toBe(1);
});

test('D2 replays a cut start reply with the same job ID', async ({ app, screen, device }) => {
  const scenario = 'Demo D2 transport';
  await d2Fixture(scenario, { begin: true });
  await launchMira(app, screen, device);
  await startTodayCard(screen, scenario, 1);
  const starts = async () => (await d2Fixture(scenario)).map(({ card, starts }) => [card, starts]).sort();
  await expect.poll(starts).toEqual([[1, 2], [2, 1], [3, 1]]);
  await d2Fixture(scenario, { card: 1, finish: true });
  await expect(screen.getByTestId('mira.today.makeCard.1')).toBeVisible();
  await app.screenshot('transport-recovered-card');
  await d2Fixture(scenario, { finish: true });
  await expect(screen.getByRole('button', /^Idea [1-3] of 3, ready$/)).toHaveCount(3);
  expect(await starts()).toEqual([[1, 2], [2, 1], [3, 1]]);
});

test('demo moves from an idea to a saved filming plan', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
  await openToday(screen);
  await expect(makeToday(screen)).toBeVisible({ timeout: 45_000 });
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
  await startShooting(screen);
  await expect(screen.getByText('Shot 1 of 3', { exact: true })).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Mark filmed', { exact: true }));
  const filmedCount = screen.getByText('1 filmed by you', { exact: true });
  await scrollToControl(screen, filmedCount, 'up');
  await expect(filmedCount).toBeVisible();
  await app.screenshot('mira-demo-filming');
  await launchMira(app, screen, device);
  await expect(screen.getByText('1 filmed by you', { exact: true })).toBeVisible({ timeout: 45_000 });
});

test('Profile shows Allow and Decline immediately after each choice', async ({ app, screen, device }) => {
  test.skip(process.env.MIRA_E2E_CONSENT_FIXTURE !== '1', 'Use an isolated Debug app with a synthetic paired account.');
  expect(bundleId).toBe('com.prateekranka.creatorcontenthelper.codexverify');
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await device.openApp(bundleId, { relaunch: true, launchArguments: english });
  await dismissSystemVerification(screen);
  await openTab(screen, 'Home');
  await backOut(screen);
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
  await launchMira(app, screen, device, true);
  await openToday(screen);
  const make = makeToday(screen);
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
  await startShooting(screen);
  await expect(title('Shot 1 of 3')).toBeVisible({ timeout: 45_000 });
  await expect(picture(1)).toBeVisible();
  await tap(screen, screen.getByRole('button', 'Next', { exact: true }));
  const chosenShot = title('Say the next part');
  await scrollToControl(screen, chosenShot, 'up');
  await expect(title('Shot 2 of 3')).toBeVisible();
  await expect(chosenShot).toBeVisible();
  await expect(screen.getByRole('image', 'Shot 2, side view, 20 seconds', { exact: true })).toBeVisible();
  await app.screenshot('today-selected-filming');
  await launchMira(app, screen, device);
  await expect(title('Shot 2 of 3')).toBeVisible();
  await expect(title('Say the next part')).toBeVisible();
  await startTodayCard(screen, 'Demo card failure', 2);
  await expect(page(3)).toBeVisible();
  await page(2).tap();
  const retry = screen.getByRole('button', 'Try again', { exact: true, visible: true });
  await expect(retry).toBeVisible();
  await app.screenshot('today-one-card-failure');
  await tap(screen, retry);
  await expect(title('My simple breakfast')).toBeVisible();
  await page(1).tap();
  await expect(title('A quick movement break')).toBeVisible();
  await page(3).tap();
  await expect(title('A small pause in my day')).toBeVisible();
});

test('Your words gate leads to approved filming and the Done screen', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
  await openToday(screen);
  const make = makeToday(screen);
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

  await launchMira(app, screen, device);
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
    if (await updating.isVisible()) await app.screenshot('s2-words-updating-shots');
  }
  await startShooting(screen);
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
  await launchMira(app, screen, device, true);
  await openToday(screen);
  const make = makeToday(screen);
  const request = homeRequest(screen);
  const keyboard = fixtureSessionArguments.length
    ? screen.getByRole('window', 'Next keyboard', { exact: true })
    : mobileKeyboard(screen);
  const dismissKeyboard = async () => {
    if (await keyboard.isVisible()) await request.press('Enter');
    await expect(keyboard).not.toBeVisible();
  };
  await expect(make).toBeVisible({ timeout: 45_000 });
  await expect(request).toHaveAccessibleName('What can you film today?');
  await expect(homeMic(screen)).toBeVisible();
  await expect(screen.getByText('Plan step by step', { exact: true })).not.toBeVisible();
  await expect(screen.getByText('Try Mamta’s demo notebook', { exact: true })).not.toBeVisible();
  await fillText(request, '');
  await dismissKeyboard();
  await app.screenshot(`d1-today-${look}`);

  const chip = (label: string) => homeIdeaButton(screen, label);
  await request.tap();
  await expect(keyboard).toBeVisible();
  await chip('Gym').tap();
  await expect(keyboard).not.toBeVisible();
  expect(await request.inputValue()).toBe('At the gym');
  await chip('Home').tap();
  expect(await request.inputValue()).toBe('At home');
  await chip('10 min').tap();
  expect(await request.inputValue()).toBe('At home, 10 minutes');
  await chip('20 min').tap();
  expect(await request.inputValue()).toBe('At home, 20 minutes');
  await chip('20 min').tap();
  expect(await request.inputValue()).toBe('At home');
  await chip('Outside').tap();
  expect(await request.inputValue()).toBe('Outside');
  await app.screenshot(`d1-today-chips-${look}`);
  await fillText(request, '');
  await expect(keyboard).toBeVisible();
  await screen.getByText('Nothing planned today.', { exact: true, visible: true }).tap();
  await expect(keyboard).not.toBeVisible();

  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  const stepByStep = screen.getByTestId('mira.profile.stepByStep');
  await scrollToControl(screen, stepByStep);
  await expect(screen.getByText('Opens from My Brand. You choose each part yourself.', { exact: true })).toBeVisible();
  await app.screenshot(`d1-profile-start-options-${look}`);
  await tap(screen, stepByStep);
  await expect(screen.getByText('Choosing an idea', { exact: true })).toBeVisible({ timeout: 45_000 });
  await openTab(screen, 'Home');
  await expect(make).toBeVisible();
  await expect(screen.getByText('Untitled Reel', { exact: true })).not.toBeVisible();

  await fillText(request, 'Demo slow cards');
  await expect(keyboard).toBeVisible();
  await app.screenshot('today-keyboard-open');
  await dismissKeyboard();
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
  await expect(screen.getByTestId('mira.today.continue').first()).toBeVisible();
  await app.screenshot(`d1-today-continue-${look}`);
});

async function startTodayCard(screen: Screen, request: string, card: number) {
  await openToday(screen);
  const make = makeToday(screen);
  if (await make.count()) {
    if (request) {
      const field = homeRequest(screen);
      await fillText(field, request);
      await closeKeyboard(screen, field);
    }
    await tap(screen, make);
  } else {
    await sendAsk(screen, request || 'Something I can film at home');
  }
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await screen.getByTestId(`mira.today.page.${card}`).tap();
}

async function chooseTodayCard(screen: Screen, card: number, title: string) {
  await startTodayCard(screen, '', card);
  await expect(screen.getByText(title, { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await tap(screen, screen.getByTestId(`mira.today.makeCard.${card}`));
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
}

async function expandAllReels(screen: Screen) {
  const archived = screen.getByText('Show archived projects', { exact: true });
  if (!await archived.count()) await tap(screen, screen.getByText('All Reels', { exact: true }).first());
  await expect(archived).toBeAttached();
}

async function sendAsk(screen: Screen, request: string) {
  const bar = screen.getByTestId('mira.ask.bar');
  await fillText(bar, request);
  const send = screen.getByRole('button', 'Send to Mira', { exact: true });
  await expect(send).toBeVisible();
  await send.tap();
}

async function startShooting(screen: Screen) {
  const shoot = screen.getByTestId('mira.shots.film');
  await expect(shoot).toBeAttached({ timeout: 45_000 });
  await tap(screen, shoot);
}

async function openProjectFromList(screen: Screen, title: string) {
  await openTab(screen, 'My Brand');
  await backOut(screen);
  await expandAllReels(screen);
  const row = screen.getByText(title, { exact: true }).first();
  await scrollToControl(screen, row);
  await row.tap();
}

test('S1 B1 the Projects shot list asks her to approve the words before filming', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
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
  await startShooting(screen);
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await back.tap();
  const continueLink = screen.getByRole('button', 'Continue filming', { exact: true });
  await scrollToControl(screen, continueLink);
  await expect(continueLink).toBeVisible();
  await expect(screen.getByTestId('mira.shots.approve')).not.toBeVisible();
  await app.screenshot(`s1-b1-shots-approved-${look}`);
});

test('S1 B2 open filming closes its controls when the approval is undone', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
  await chooseTodayCard(screen, 2, 'My simple breakfast');
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await startShooting(screen);
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  const mark = screen.getByRole('button', 'Mark filmed', { exact: true });
  const next = screen.getByRole('button', 'Next', { exact: true });
  for (let shot = 1; shot <= 2; shot += 1) {
    await tap(screen, mark);
    await tap(screen, next);
  }
  await openProjectFromList(screen, 'My simple breakfast');
  await tap(screen, await sectionControl(screen, 'Shots'));
  await (await menuControl(screen, 'Plan options')).tap();
  await screen.getByRole('button', 'Undo last content change', { exact: true }).tap();
  await openTab(screen, 'Home');
  const message = screen.getByTestId('mira.approveFirst.message');
  await expect(message).toBeVisible();
  await expect(screen.getByRole('button', 'Mark filmed', { exact: true })).not.toBeVisible();
  await expect(screen.getByText('Shot 3 of 3', { exact: true, visible: true })).not.toBeVisible();
  await app.screenshot(`s1-b2-filming-gate-${look}`);

  await launchMira(app, screen, device);
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible({ timeout: 45_000 });
  await expect(message).not.toBeVisible();
  await app.screenshot(`s1-b2-relaunch-words-${look}`);
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await startShooting(screen);
  await expect(screen.getByText('Shot 3 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByText('2 filmed by you', { exact: true, visible: true })).toBeVisible();
  await app.screenshot('m01-filming-progress-after-undo');
  await openTab(screen, 'My Brand');
  await (await menuControl(screen, 'Plan options')).tap();
  await screen.getByRole('button', 'Undo last content change', { exact: true }).tap();
  await openTab(screen, 'Home');
  await expect(message).toBeVisible();
  await tap(screen, screen.getByTestId('mira.approveFirst.words'));
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await startShooting(screen);
  await expect(screen.getByText('Shot 3 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await scrollToControl(screen, mark);
  await expect(mark).toBeVisible();
  await screen.getByTestId('BackButton').tap();
  await expect(screen.getByText('3 / 6', { exact: true })).toBeVisible();
});

test('S1 B3 Continue says Approve your words until she approves', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
  await chooseTodayCard(screen, 3, 'A small pause in my day');
  await openToday(screen);
  const continueCard = screen.getByTestId('mira.today.continue').first();
  await expect(continueCard).toBeVisible();
  await expect(screen.getByText('Approve your words', { exact: true })).toBeVisible();
  await expect(screen.getByText('Start filming', { exact: true })).not.toBeVisible();
  await app.screenshot(`s1-b3-continue-approve-${look}`);
  await continueCard.tap();
  await expect(screen.getByTestId('mira.words.approve')).toBeVisible();
  await tap(screen, screen.getByTestId('mira.words.approve'));
  await startShooting(screen);
  await expect(screen.getByText('Shot 1 of 3', { exact: true, visible: true })).toBeVisible({ timeout: 45_000 });
  await openToday(screen);
  await expect(screen.getByText('Continue filming', { exact: true })).toBeVisible();
  await openTab(screen, 'My Brand');
  await backOut(screen);
  await expandAllReels(screen);
  await expect(screen.getByText('Filming · Continue filming', { exact: true }).first()).toBeVisible();
  await app.screenshot(`s1-b3-projects-stage-${look}`);
});

test('S1 B4 a full server shows Waiting to start and sends the idea again by itself', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
  await startTodayCard(screen, 'Demo busy server', 3);
  const waiting = screen.getByTestId('mira.today.waiting.3');
  await expect(waiting).toBeVisible({ timeout: 10_000 });
  await expect(screen.getByText('Mira is making idea 3 of 3', { exact: true, visible: true })).not.toBeVisible();
  await app.screenshot(`s1-b4-waiting-${look}`);
  await screen.getByTestId('BackButton').tap();
  const open = screen.getByTestId('mira.today.continue').first();
  await expect(open).toBeVisible();
  await expect(makeToday(screen)).not.toBeVisible();
  await app.screenshot(`s1-b4-today-open-${look}`);
  await open.tap();
  await expect(screen.getByTestId('mira.today.page.3')).toBeVisible();
  await expect(screen.getByText('About 1 minute', { exact: true })).not.toBeVisible({ timeout: 45_000 });
  await screen.getByTestId('mira.today.page.3').tap();
  await expect(screen.getByText('A small pause in my day', { exact: true, visible: true })).toBeVisible();
  await expect(waiting).not.toBeVisible();
  await app.screenshot(`s1-b4-all-ready-${look}`);
  await screen.getByTestId('BackButton').tap();
  await expect(screen.getByTestId('mira.ask.bar')).toBeVisible();
});

test('S1 B5 Stop on an idea that the server never took ends as stopped', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
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
  await expect(screen.getByTestId('mira.ask.bar')).toBeVisible();
});

test('Profile Look setting', async ({ app, screen, device }) => {
  await launchMira(app, screen, device, true);
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
    launchArguments: [...fixtureLaunch(), '-MCO_DEBUG_CRASH', '1'],
  });
  await expect.poll(() => appIsRunning(screen), {
    timeout: 20_000,
    interval: 1_000,
    message: 'Mira should stop running after the deliberate debug crash.',
  }).toBe(false);

  await launchMira(app, screen, device);
  await backOut(screen);
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  const accountStatus = screen.getByText(/^(Connect account|Allowed|Not decided yet|Not allowed yet)$/);
  await scrollToControl(screen, accountStatus);
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
  const askBox = await screen.getByTestId('mira.ask.bar').boundingBox();
  const box = await end.boundingBox();
  expect(askBox.y + askBox.height).toBeLessThanOrEqual(tabBox.y);
  expect(box.y).toBeGreaterThan(0);
  expect(box.y + box.height).toBeLessThanOrEqual(askBox.y - 8);
  await app.screenshot(label);
}

test('S2 Plan step by step uses plain microphone words and scrolls above the tab bar', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await openToday(screen);
  const continueCard = screen.getByTestId('mira.today.continue').first();
  const todayEnd = await continueCard.count() ? continueCard : makeToday(screen);
  await bottomAboveTabs(app, screen, todayEnd, 's2-today-bottom');
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  await tap(screen, screen.getByTestId('mira.profile.stepByStep'));
  const note = screen.getByText('Your voice stays on this phone. Check the words before you send them.', { exact: true });
  await bottomAboveTabs(app, screen, note, 's2-microphone-note');
  const timeNote = screen.getByText(
    'You can change these. This is time to get ready and film. Set the Reel length below.', { exact: true },
  );
  await bottomAboveTabs(app, screen, timeNote, 's3-filming-time-note');
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Share current plan', { exact: true }), 's2-step-by-step-bottom');
});

test('S2 resumes cards, words, filming plan and filming with content clear of the tab bar', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await startTodayCard(screen, '', 1);
  const card = screen.getByTestId('mira.today.makeCard.1');
  await expect(card).toBeVisible();
  await launchMira(app, screen, device);
  await expect(screen.getByTestId('mira.today.page.1')).toBeVisible();
  await screen.getByTestId('mira.today.page.1').tap();
  const selectedCard = screen.getByRole('scroll-view', { visible: true }).filter({ has: card }).last();
  const change = selectedCard.getByRole('button', 'Change something', { exact: true });
  await bottomAboveTabs(app, screen, change, 's2-resume-today-cards');
  await tap(screen, card);
  const approve = screen.getByTestId('mira.words.approve');
  await launchMira(app, screen, device);
  await expect(approve).toBeVisible();
  await bottomAboveTabs(app, screen, screen.getByTestId('mira.words.change'), 's2-resume-words');

  await openTab(screen, 'My Brand');
  await backOut(screen);
  await expandAllReels(screen);
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Delete', { exact: true }).last(), 's2-projects-bottom');
  const row = screen.getByText('A quick movement break', { exact: true }).first();
  await scrollToControl(screen, row, 'up');
  await row.tap();
  await screen.getByTestId('BackButton').tap();
  await bottomAboveTabs(app, screen, screen.getByRole('button', 'Share current plan', { exact: true }), 's2-script-bottom');
  await scrollToControl(screen, screen.getByRole('textbox', 'Project name', { exact: true }), 'up');
  const shots = await sectionControl(screen, 'Shots');
  await scrollToControl(screen, shots, 'up');
  await tap(screen, shots);
  const plan = screen.getByText('Your filming plan', { exact: true });
  await expect(plan).toBeVisible();
  await launchMira(app, screen, device);
  await expect(plan).toBeVisible();
  const opening = screen.getByText("Here's a movement I do between tasks.", { exact: true }).first();
  await bottomAboveTabs(app, screen, opening, 's2-shot-one-text');
  await bottomAboveTabs(app, screen, screen.getByText(/^Record for about \d+ seconds\.$/).last(), 's2-resume-plan');

  const approval = screen.getByTestId('mira.shots.approve');
  await scrollToControl(screen, approval, 'up');
  await tap(screen, approval);
  await tap(screen, approve);
  await startShooting(screen);
  const filming = screen.getByText('Shot 1 of 3', { exact: true });
  await expect(filming).toBeVisible();
  await launchMira(app, screen, device);
  await expect(filming).toBeVisible();
  await bottomAboveTabs(app, screen,
    screen.getByText('Mira does not record or analyse footage. Filmed is progress you report yourself.', { exact: true }),
    's2-resume-filming');
});

test('S3 relaunch keeps the sample projects', async ({ app, screen, device }) => {
  await device.closeApp();
  await launchMira(app, screen, device);
  await openToday(screen);
  for (let step = 0; step < 2; step += 1) {
    await screen.getByRole('button', 'Profile', { exact: true }).tap();
    await tap(screen, screen.getByTestId('mira.profile.demo'));
    await expect(screen.getByText('Example — not your content')).toBeVisible();
    await backOut(screen);
  }
  await openTab(screen, 'My Brand');
  await backOut(screen);
  await expandAllReels(screen);
  const rows = screen.getByRole('button', 'Rename', { exact: true });
  const count = await rows.count();
  expect(count).toBeGreaterThanOrEqual(2);
  await launchMira(app, screen, device);
  await expandAllReels(screen);
  await expect(rows).toHaveCount(count);
  await app.screenshot('sample-projects-after-relaunch');
});

test('S3 an isolated damaged library restores its last safe save', async ({ app, screen, device }) => {
  expect(fixtureSessionArguments.length).toBe(2);
  const session = fixtureSessionArguments[1];
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: [
      ...english, '-MCO_FORCE_FIXTURE_UI', '1', '-MCO_QA_SESSION', `${session}-damaged-${Date.now()}`,
      '-MCO_QA_DAMAGED_LIBRARY', '1',
    ],
  });
  await waitForMobileApp(screen);
  await dismissSystemVerification(screen);
  await expect(screen.getByText(/Recovered your last safe save/)).toBeVisible();
  await app.screenshot('damaged-file-restored');
  await screen.getByRole('button', 'Try opening saved work again', { exact: true }).tap();
  await expect(screen.getByTestId('mira.fixture.profile')).toBeVisible();
  await openTab(screen, 'My Brand');
  await expandAllReels(screen);
  await expect(screen.getByText('Recovered sample Reel', { exact: true })).toBeVisible();
  await app.screenshot('recovered-project');
});

test('S3 editing a confirmed sample brief requires review again', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await openToday(screen);
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  await tap(screen, screen.getByTestId('mira.profile.demo'));
  await expect(screen.getByText('Example — not your content')).toBeVisible();
  const brief = screen.getByRole('button', 'Add brand requirements', { exact: true });
  await tap(screen, brief);
  const original = screen.getByRole('textbox', 'Original brand requirements', { exact: true });
  const keyboard = screen.getByRole('window', 'Next keyboard', { exact: true });
  await fillText(original, 'Caption: Oats from home');
  await original.press('Enter');
  await expect(keyboard).not.toBeVisible();
  await tap(screen, screen.getByRole('button', 'Extract proposed requirements', { exact: true }));
  const close = screen.getByRole('button', 'Close', { exact: true });
  await expect(close).not.toBeVisible();
  const use = screen.getByRole('button', 'Use this', { exact: true });
  await scrollToControl(screen, use, 'up');
  await tap(screen, use);
  await tap(screen, brief);
  const confirm = screen.getByRole('button', 'Confirm these requirements', { exact: true });
  await scrollToControl(screen, confirm);
  await expect(screen.getByText('Unresolved details', { exact: true })).toBeAttached();
  await tap(screen, confirm);
  const confirmed = screen.getByText(/^Brand requirements confirmed ·/);
  await expect(confirmed).toBeAttached();
  await tap(screen, brief);
  await fillText(original, 'Caption: A new caption');
  await original.press('Enter');
  await expect(keyboard).not.toBeVisible();
  await expect(screen.getByText(/^Source changed ·/)).toBeAttached();
  await scrollToControl(screen, confirm);
  await expect(confirm).toBeDisabled();
  await app.screenshot('brief-source-changed');
  await close.tap();
  await expect(confirmed).not.toBeAttached();
});

test('S3 server backoff shows Waiting to try again and can stop', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await startTodayCard(screen, 'Demo server retry', 1);
  const selected = screen.getByTestId('mira.today.page.1');
  await expect(selected).toBeSelected();
  await expect(selected).toHaveAccessibleName('Idea 1 of 3, Waiting to try again');
  await expect(screen.getByText('Waiting to try again', { exact: true, visible: true }).first()).toBeVisible();
  await app.screenshot('waiting-to-try-again');
  await stopLeftoverIdeasAfterOpening(screen);
});

async function stopLeftoverIdeasAfterOpening(screen: Screen) {
  await screen.getByTestId('BackButton').tap();
  await stopLeftoverIdeas(screen);
  await expect(screen.getByTestId('mira.ask.bar')).toBeVisible();
}

test('S3 denied speech shows one Settings action and still accepts typing', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await openToday(screen);
  const mic = homeMic(screen);
  await expect(mic).toHaveAccessibleName('Speak instead of typing');
  await app.screenshot('mic-idle');
  const denied = screen.getByText(
    'To use voice input, allow Speech Recognition and Microphone in Settings. You can still type.', { exact: true },
  );
  const settings = screen.getByRole('button', 'Open Settings', { exact: true, visible: true });
  try {
    await mic.tap();
    if (!await denied.isVisible()) await device.openApp(bundleId, { launchArguments: fixtureLaunch() });
  } catch (error) {
    if (!(error instanceof Error && /not running|foreground|application.*interrupt/i.test(error.message))) throw error;
    await device.openApp(bundleId, { launchArguments: fixtureLaunch() });
  }
  await expect(denied).toBeVisible();
  await expect(settings).toHaveCount(1);
  await expect(mic).toHaveAccessibleName('Open Settings');
  await expect(screen.getByRole('alert')).not.toBeVisible();
  await app.screenshot('mic-denied');
  const request = homeRequest(screen);
  await fillText(request, 'Film a sample clip at home');
  await request.press('Enter');
  await expect(screen.getByRole('window', 'Next keyboard', { exact: true })).not.toBeVisible();
  expect(await request.inputValue()).toBe('Film a sample clip at home');
  await app.screenshot('mic-denied-typing');
});

const wordsApprove = (screen: Screen) => screen.getByTestId('mira.words.approve');
const wordsStart = (screen: Screen) => screen.getByTestId('mira.words.start');
const shotUpdate = (screen: Screen) => screen.getByRole('button', 'Update shot list', { exact: true });
const firstShot = (screen: Screen) => screen.getByText('Shot 1 of 3', { exact: true, visible: true });

test('M03 undo restores the previous card title, selected idea and filming constraints', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await startTodayCard(screen, '12 minutes at home', 1);
  await tap(screen, screen.getByTestId('mira.today.makeCard.1'));
  await screen.getByTestId('BackButton').tap();
  await screen.getByTestId('mira.today.page.2').tap();
  const second = screen.getByTestId('mira.today.makeCard.2');
  const card = screen.getByRole('scroll-view', { visible: true }).filter({ has: second }).last();
  await tap(screen, card.getByRole('button', 'Change something', { exact: true }));
  const note = screen.getByRole('textbox', 'What would help?', { exact: true });
  await fillText(note, '4 minutes in the kitchen');
  await closeKeyboard(screen, note);
  await tap(screen, screen.getByRole('button', 'Propose change', { exact: true }));
  await expect(screen.getByText('About 4 min to film', { exact: true })).toBeVisible();
  await tap(screen, second);
  await openProjectFromList(screen, 'My simple breakfast');
  await expect(wordsApprove(screen)).toBeVisible();
  await screen.getByTestId('BackButton').tap();
  await tap(screen, await sectionControl(screen, 'Script'));
  await tap(screen, screen.getByRole('button', 'Undo last content change', { exact: true }));
  const title = screen.getByRole('textbox', 'Project name', { exact: true });
  expect(await title.inputValue()).toBe('A quick movement break');
  await expect(screen.getByText('Show the movement from start to finish.', { exact: true }).first()).toBeAttached();
  await tap(screen, await sectionControl(screen, 'Shots'));
  await sendAsk(screen, 'Explain this plan');
  await tap(screen, screen.getByRole('button', 'Explain this plan', { exact: true }));
  const explanation = screen.getByText(/^This Reel is planned for Home, with 12 minutes/);
  await scrollToControl(screen, explanation);
  await expect(explanation).toBeVisible();
  await app.screenshot('m03-undo-card-constraints');
});

test('M04 updating stale shots routes to explicit approval before generating', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await chooseTodayCard(screen, 1, 'A quick movement break');
  await tap(screen, screen.getByTestId('mira.words.simpler'));
  await tap(screen, screen.getByTestId('mira.words.use'));
  await openProjectFromList(screen, 'A quick movement break');
  await screen.getByTestId('BackButton').tap();
  await tap(screen, await sectionControl(screen, 'Shots'));
  await tap(screen, shotUpdate(screen));
  await expect(wordsApprove(screen)).toBeVisible();
  await expect(wordsStart(screen)).not.toBeAttached();
  await app.screenshot('m04-update-requires-approval');
  await tap(screen, wordsApprove(screen));
  await startShooting(screen);
  await expect(firstShot(screen)).toBeVisible({ timeout: 45_000 });
});

test('M05 M06 Projects proposal needs Use this and mismatched dialogue blocks open filming', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await chooseTodayCard(screen, 1, 'A quick movement break');
  await tap(screen, wordsApprove(screen));
  await startShooting(screen);
  await expect(firstShot(screen)).toBeVisible();
  await app.screenshot('m05-hook-prefixed-script-filming');
  await screen.getByTestId('BackButton').tap();
  await screen.getByTestId('BackButton').tap();
  await openProjectFromList(screen, 'A quick movement break');
  await tap(screen, await sectionControl(screen, 'Shots'));
  await sendAsk(screen, 'Replace the first shot words with sugar.');
  const note = screen.getByRole('textbox', 'What would help?', { exact: true });
  await expect(note).toBeVisible();
  expect(await note.inputValue()).toBe('Replace the first shot words with sugar.');
  await tap(screen, screen.getByRole('button', 'Propose change', { exact: true }));
  await openTab(screen, 'Home');
  await expect(wordsStart(screen)).toBeVisible({ timeout: 60_000 });
  await expect(firstShot(screen)).not.toBeAttached();
  await app.screenshot('m06-words-awaits-explicit-filming');
  await tap(screen, wordsStart(screen));
  await startShooting(screen);
  await expect(firstShot(screen)).toBeVisible();
  await openTab(screen, 'My Brand');
  const use = screen.getByRole('button', 'Use this', { exact: true });
  await tap(screen, use);
  const warning = screen.getByText('Mira needs to update the shots', { exact: true });
  await scrollToControl(screen, warning);
  await expect(warning).toBeVisible();
  await expect(screen.getByTestId('mira.shots.film')).not.toBeAttached();
  await openTab(screen, 'Home');
  await expect(warning).toBeVisible();
  await expect(shotUpdate(screen)).toHaveCount(1);
  await expect(firstShot(screen)).not.toBeAttached();
  await expect(screen.getByText('Add the sugar.', { exact: true })).not.toBeAttached();
  await expect(screen.getByRole('button', 'Mark filmed', { exact: true })).not.toBeAttached();
  await app.screenshot('m05-wrong-dialogue-blocked');
});

test('M13 permission withdrawal stops a waiting card with its request still saved', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  const request = 'Demo permission withdrawn while waiting';
  await startTodayCard(screen, request, 3);
  await expect(screen.getByTestId('mira.today.waiting.3')).toBeVisible();
  await expect(screen.getByText('This idea was stopped.', { exact: true })).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByText('AI permission is off. Your words are saved.', { exact: true })).toBeVisible();
  await app.screenshot('m13-permission-withdrawal-stopped');
  await expect(screen.getByTestId('mira.today.makeCard.3')).not.toBeAttached();
});

test('M14 a different account cannot start a saved unsent card', async ({ app, screen, device }) => {
  const relaunch = async (owner: string) => {
    await device.openApp(bundleId, { relaunch: true, launchArguments: [
      ...english, '-MCO_FORCE_FIXTURE_UI', '1', '-MCO_QA_SESSION', `${sampleSession}-ownership`,
      '-MCO_QA_FIXTURE_CREATOR', owner,
    ] });
    await waitForMobileApp(screen);
    await dismissSystemVerification(screen);
  };
  await relaunch('B8C9289A-D541-40BA-91B0-64D9390D188A');
  await startTodayCard(screen, 'Demo stop unknown', 3);
  await expect(screen.getByTestId('mira.today.waiting.3')).toBeVisible();
  await relaunch('89725BE6-737E-4F48-A2D9-78A11B720D7F');
  await screen.getByTestId('mira.today.page.3').tap();
  await expect(screen.getByText('This belongs to another account', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('mira.today.waiting.3')).not.toBeAttached();
  await app.screenshot('m14-unsent-card-account-refused');
});

test('M16 Home filming preserves the My Brand Script section for the same Reel', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await chooseTodayCard(screen, 1, 'A quick movement break');
  await tap(screen, wordsApprove(screen));
  await startShooting(screen);
  await expect(firstShot(screen)).toBeVisible();
  await openProjectFromList(screen, 'A quick movement break');
  const script = await sectionControl(screen, 'Script');
  await tap(screen, script);
  await expect(script).toBeSelected();
  await openTab(screen, 'Home');
  await expect(firstShot(screen)).toBeVisible();
  await openTab(screen, 'My Brand');
  await expect(script).toBeSelected();
  await launchMira(app, screen, device);
  await expect(await sectionControl(screen, 'Script')).toBeSelected();
  await app.screenshot('m16-projects-script-section');
  await openTab(screen, 'Home');
  await expect(firstShot(screen)).toBeVisible();
});

test('M17 a rejected update keeps Retry as the next step and retry reaches filming', async ({ app, screen, device }) => {
  await launchMira(app, screen, device);
  await startTodayCard(screen, 'Demo rejected shot update', 1);
  await tap(screen, screen.getByTestId('mira.today.makeCard.1'));
  await tap(screen, screen.getByTestId('mira.words.simpler'));
  await tap(screen, screen.getByTestId('mira.words.use'));
  await tap(screen, wordsApprove(screen));
  const alert = screen.getByRole('alert', 'Mira', { exact: true });
  await expect(alert).toBeVisible({ timeout: 45_000 });
  await alert.getByRole('button', 'OK', { exact: true }).tap();
  const retry = screen.getByTestId('mira.words.shots.retry');
  await scrollToControl(screen, retry);
  await expect(retry).toBeVisible();
  await expect(screen.getByTestId('mira.words.change')).not.toBeAttached();
  await expect(wordsStart(screen)).not.toBeAttached();
  await app.screenshot('m17-rejected-update-retry');
  await tap(screen, retry);
  await startShooting(screen);
  await expect(firstShot(screen)).toBeVisible({ timeout: 45_000 });
});

test('M19 missing Instagram permission offers Connect again in the sample library', async ({ app, screen, device }) => {
  await device.openApp(bundleId, { relaunch: true, launchArguments: [...fixtureLaunch(), '-MCO_INSIGHTS_SCENARIO', 'permission'] });
  await waitForMobileApp(screen);
  await dismissSystemVerification(screen);
  await openToday(screen);
  await screen.getByTestId('mira.fixture.profile').tap();
  await tap(screen, screen.getByTestId('mira.profile.insights'));
  await expect(screen.getByText('Permission needed', { exact: true })).toBeVisible();
  const reconnect = screen.getByRole('button', 'Connect again', { exact: true });
  await expect(reconnect).toBeVisible();
  await app.screenshot('m19-instagram-reconnect');
  await tap(screen, reconnect);
  await expect(screen.getByText('Instagram connection is unavailable in the sample library.', { exact: true })).toBeVisible();
});
