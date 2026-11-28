import { test, type Device } from '@e2e-dev/mobile';
import { expect, type App, type Locator, type Screen } from 'e2e';
import { appendFileSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { e3Brief, e3Deliverables } from './fixtures/mira-deal-brief';
import { scrollToControl, tapVisibleControl } from './mobile-support';

const evidence = resolve(
  process.env.MIRA_E2E_LIVE_LEDGER_DIR ?? process.env.MIRA_E2E_OUTPUT ?? 'work/evidence/mira-live-journey',
);
const ledgerPath = resolve(evidence, 'live-requests.jsonl');
const timeout = 240_000;
const recorded = (path = ledgerPath) => {
  try {
    return readFileSync(path, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line) as Entry);
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return [];
    throw error;
  }
};

type Entry = {
  scenario: number; action: string; calls?: number; title?: string; at?: string;
  card?: number; pictures?: number; shots?: number; milliseconds?: number;
};

function record(entry: Entry) {
  mkdirSync(evidence, { recursive: true });
  appendFileSync(ledgerPath, `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`, { mode: 0o600 });
}

async function request(scenario: number, action: string, calls: number, tap: () => Promise<void>) {
  const prior = recorded();
  const limit = Number(process.env.MIRA_E2E_LIVE_REQUEST_LIMIT ?? '12');
  expect(prior.reduce((total, entry) => total + (entry.calls ?? 0), 0) + calls).toBeLessThanOrEqual(limit);
  expect(prior.filter(entry => entry.scenario === scenario && entry.action === action && entry.calls)).toHaveLength(0);
  record({ scenario, action, calls });
  await tap();
  record({ scenario, action: `${action} tap returned` });
}

const text = (screen: Screen, name: string | RegExp) => screen.getByText(name, { exact: true, visible: true });
const button = (screen: Screen, name: string | RegExp) => screen.getByRole('button', name, { exact: true });
const back = (screen: Screen) => screen.getByTestId('BackButton', { visible: true });
const approve = (screen: Screen) => screen.getByTestId('mira.words.approve');
const keyboardWindow = (screen: Screen) => screen.getByRole('window', 'Next keyboard', { exact: true });

async function launch(app: App, screen: Screen, device: Device) {
  const tabs = screen.getByRole('tablist', 'Tab Bar', { exact: true });
  await app.open();
  try {
    await tabs.count();
  } catch (error) {
    if (!(error instanceof Error && /is not running/.test(error.message))) throw error;
    await device.openApp('com.prateekranka.creatorcontenthelper', { relaunch: true });
    await expect.poll(() => tabs.count(), { timeout: 15_000, interval: 1_000 }).toBe(1);
  }
  await expect(screen.getByTestId('sign-in.welcome')).not.toBeVisible();
  const verification = screen.getByRole('alert', /Apple.Account Verification/);
  if (await verification.isVisible()) {
    await verification.getByRole('button', 'Not Now', { exact: true }).tap();
  }
  await expect(tabs).toBeVisible({ timeout: 45_000 });
}

async function tab(screen: Screen, name: string) {
  const tabs = screen.getByRole('tablist', 'Tab Bar', { exact: true });
  const control = tabs.getByRole('tab', name, { exact: true });
  await (await control.count() ? control : tabs.getByRole('button', name, { exact: true })).tap();
}

async function root(screen: Screen, name: string) {
  await tab(screen, name);
  for (let step = 0; step < 5 && await back(screen).isVisible(); step += 1) {
    await back(screen).tap();
  }
  await expect(button(screen, 'Profile')).toBeVisible();
}

async function menu(screen: Screen, name: string) {
  const popup = screen.getByRole('pop-up-button', name, { exact: true });
  await (await popup.count() ? popup : button(screen, name)).tap();
}

async function openProject(screen: Screen, title: string) {
  await root(screen, 'My Brand');
  const archived = screen.getByText('Show archived projects', { exact: true });
  if (!await archived.count()) await tapVisibleControl(screen, screen.getByText('All Reels', { exact: true }).first());
  const row = screen.getByRole('button', { visible: true }).filter({ hasText: title }).first();
  if (await row.count()) await tapVisibleControl(screen, row);
  else await tapVisibleControl(screen, screen.getByText(title, { exact: true }).first());
}

function todayTitle() {
  const title = recorded().findLast(entry => entry.action === 'selected Today project')?.title;
  test.skip(!title, 'The Today scenario has no selected live project.');
  return title!;
}

async function fit(screen: Screen, locator: Locator, direction: 'up' | 'down' = 'down') {
  await scrollToControl(screen, locator, direction);
  await expect(locator).toBeVisible();
}

async function selectShots(screen: Screen) {
  const tab = screen.getByRole('tab', 'Shots', { exact: true });
  await tapVisibleControl(screen, await tab.count() ? tab.first() : button(screen, 'Shots').first());
}

async function waitForOutput(screen: Screen, output: Locator, message: string, limit = timeout) {
  await expect.poll(async () => {
    const failure = screen.getByText(/^(Mira could not finish\.|Could not check this idea\.|Allow AI to write ideas first\.|The network connection was lost\.)/, { visible: true });
    if (await screen.getByRole('alert', 'Mira', { exact: true }).isVisible() || await failure.isVisible()) {
      return 'Mira reported a generation failure';
    }
    return await output.count() ? 'ready' : 'waiting';
  }, { timeout: limit, interval: 3_000, message }).not.toBe('waiting');
  await expect(output).toHaveCount(1);
}

async function todayKeyboard(app: App, screen: Screen) {
  await root(screen, 'Home');
  const field = screen.getByTestId('mira.today.request');
  const make = screen.getByTestId('mira.today.make');
  const keyboard = keyboardWindow(screen);
  await expect(make).toBeVisible();
  const prompt = 'At the gym, sled push';
  await field.fill(prompt);
  await expect(keyboard).toBeVisible();
  const keyboardBox = await keyboard.boundingBox();
  expect(keyboardBox).not.toBeNull();
  for (const done of await button(screen, 'Done').all()) {
    const box = await done.boundingBox();
    expect(box!.y).toBeGreaterThanOrEqual(keyboardBox!.y);
  }
  await app.screenshot('keyboard-open');
  await field.press('Enter');
  await expect(keyboard).not.toBeVisible();
  expect(await field.inputValue()).toBe(prompt);
  await app.screenshot('keyboard-closed');
  const gym = screen.getByTestId('mira.today.chip.gym');
  const ten = screen.getByTestId('mira.today.chip.10min');
  await expect(gym).toBeSelected();
  await field.tap();
  await expect(keyboard).toBeVisible();
  await tapVisibleControl(screen, ten);
  await expect(ten).toBeSelected();
  await expect(keyboard).not.toBeVisible();
  expect(await field.inputValue()).toBe(`${prompt}, 10 minutes`);
  await expect(make).toBeEnabled();
  const makeBox = await make.boundingBox();
  const pageBox = await screen.getByRole('scroll-view', { visible: true }).first().boundingBox();
  const tabBox = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  expect(makeBox!.y).toBeGreaterThanOrEqual(pageBox!.y);
  expect(makeBox!.y + makeBox!.height).toBeLessThanOrEqual(Math.min(pageBox!.y + pageBox!.height, tabBox!.y));
  await app.screenshot('today-chip-after-keyboard');
  return make;
}

test('1 Today keyboard only keeps the request and the Make button reachable', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await todayKeyboard(app, screen);
});

test('E1 live Home makes ideas and opens Words and the one-page shot list', { timeout: 720_000 }, async ({ app, screen, device }) => {
  await launch(app, screen, device);
  const prior = recorded().find(entry => entry.scenario === 1 && entry.calls);
  let started = prior?.at ? Date.parse(prior.at) : Date.now();
  if (!prior) {
    await root(screen, 'Home');
    await app.screenshot('e1-live-home');
    const insights = screen.getByText("How you're doing", { exact: true });
    await expect(insights).toBeAttached({ timeout: 45_000 });
    await fit(screen, insights);
    for (const label of ['Followers', 'Reach', 'Saves']) {
      await expect(screen.getByText(label, { exact: true })).toBeAttached();
    }
    await app.screenshot('e1-live-home-insights');
    const idea = screen.getByText('Nothing planned today. Want an idea?', { exact: true });
    if (await idea.count()) {
      await fit(screen, idea, 'up');
      const make = await todayKeyboard(app, screen);
      await app.screenshot('e1-live-idea-card');
      started = Date.now();
      await request(1, "Make today's Reel", 3, () => make.tap());
    } else {
      const field = screen.getByTestId('mira.ask.bar');
      await field.fill('At home, 10 minutes to film a breakfast Reel');
      const send = button(screen, 'Send to Mira');
      await expect(send).toBeVisible();
      await app.screenshot('e1-live-ask-for-idea');
      started = Date.now();
      await request(1, 'Send a Home idea request', 3, () => send.tap());
    }
  } else {
    const step = screen.getByTestId('mira.task.step');
    const screenStep = await step.count() ? await step.textContent() : undefined;
    if (screenStep === '2 / 6' || screenStep === '3 / 6') {
      await captureE1Plan(app, screen);
      return;
    }
    expect(await screen.getByTestId('mira.today.page.1').count(),
      'The first live batch must still be open before retrying without another request.').toBe(1);
  }
  const deadline = Date.now() + timeout;
  const ready = screen.getByRole('button', /^Idea [1-3] of 3, ready$/);
  const failed = screen.getByRole('button', /^Idea [1-3] of 3, (did not load|needs an update)$/);
  const steps = ['Writing your words, now', 'Planning 3 shots, now', 'Planning 3 shots, done'];
  const observed = new Map<string, number>();
  await expect.poll(async () => {
    if (await failed.count() || await screen.getByRole('alert', 'Mira', { exact: true }).isVisible()
      || await screen.getByTestId('mira.today.aiPermissionNeeded').isVisible()) return 'failed';
    if (await ready.count() === 3) return 'ready';
    for (const [index, step] of steps.entries()) {
      if (!await screen.getByLabel(step, { exact: true, visible: true }).isVisible()) continue;
      const page = await screen.getByText(/^[1-3] of 3$/, { visible: true }).first().textContent();
      const key = page ?? 'current card';
      const previous = observed.get(key) ?? -1;
      expect(index).toBeGreaterThanOrEqual(previous);
      if (index > previous) {
        observed.set(key, index);
        record({ scenario: 1, action: step, card: Number(page?.[0]) || undefined, milliseconds: Date.now() - started });
        await app.screenshot(`live-wait-${key[0]}-${index + 1}`);
      }
      break;
    }
    return 'waiting';
  }, { timeout: Math.max(1, deadline - Date.now()), interval: 1_000 }).not.toBe('waiting');
  await expect(ready).toHaveCount(3);
  await app.screenshot('cards-ready');

  const titles: string[] = [];
  const pictureCounts: number[] = [];
  const pictureDeadline = Date.now() + 300_000;
  const aiPictures = /^AI picture for shot [1-5]$/;
  for (let card = 1; card <= 3; card += 1) {
    await screen.getByTestId(`mira.today.page.${card}`).tap();
    await expect(text(screen, `${card} of 3`)).toBeVisible();
    const makeCard = screen.getByTestId(`mira.today.makeCard.${card}`);
    const cardView = screen.getByRole('scroll-view').filter({ has: makeCard }).last();
    const heading = cardView.getByRole('text', { visible: true }).first();
    await expect(heading).toBeVisible();
    const title = (await heading.textContent())?.trim() ?? '';
    expect(title.length).toBeGreaterThan(0);
    titles.push(title);
    const shots = await cardView.getByTestId(/^mira\.shot\.picture\.[1-5]$/).count();
    expect(shots).toBeGreaterThanOrEqual(3);
    const pictures = cardView.getByRole('image', aiPictures, { visible: true });
    if (Date.now() < pictureDeadline) {
      await expect(pictures).toHaveCount(shots, { timeout: pictureDeadline - Date.now() }).catch(async error => {
        if (!(error instanceof Error && 'code' in error && error.code === 'ASSERTION_FAILED')) throw error;
      });
    }
    const count = await pictures.count();
    pictureCounts.push(count);
    record({ scenario: 1, action: 'Today card pictures', card, title, pictures: count, shots,
      milliseconds: Date.now() - started });
    await app.screenshot(`card-${card}`);
  }

  const chosenIndex = pictureCounts[2] > 0 ? 2 : pictureCounts.findIndex(count => count > 0);
  expect(chosenIndex).toBeGreaterThanOrEqual(0);
  const chosen = titles[chosenIndex];
  await screen.getByTestId(`mira.today.page.${chosenIndex + 1}`).tap();
  await tapVisibleControl(screen, screen.getByTestId(`mira.today.makeCard.${chosenIndex + 1}`));
  record({ scenario: 1, action: 'selected Today project', title: chosen, calls: 0 });
  expect(pictureCounts.reduce((total, count) => total + count, 0)).toBeLessThanOrEqual(15);
  await captureE1Plan(app, screen);
});

async function captureE1Plan(app: App, screen: Screen) {
  const aiPictures = /^AI picture for shot [1-5]$/;
  const step = screen.getByTestId('mira.task.step');
  if (await approve(screen).count()) {
    await expect(step).toHaveText('2 / 6');
    await app.screenshot('e1-live-words');
    await tapVisibleControl(screen, approve(screen));
  }
  await expect(step).toHaveText('3 / 6');
  await fit(screen, screen.getByText('Your filming plan', { exact: true }));
  await app.screenshot('e1-live-shot-list-summary');
  const firstPicture = screen.getByRole('image', aiPictures).first();
  await fit(screen, firstPicture);
  await app.screenshot('e1-live-shot-list-picture');
  const shoot = screen.getByTestId('mira.shots.film');
  await fit(screen, shoot);
  await expect(shoot).toHaveAccessibleName("Got it, I'll go shoot");
  await app.screenshot('e1-live-shot-list-action');
}

test('2 Your words opens filming and reaches Done', async ({ app, screen, device }) => {
  const title = todayTitle();
  await launch(app, screen, device);
  await root(screen, 'Home');
  const resume = screen.getByTestId('mira.today.continue');
  await fit(screen, resume);
  expect(await resume.textContent()).toContain(title);
  await tapVisibleControl(screen, resume);
  await fit(screen, approve(screen));
  await app.screenshot('words-gate');
  await tapVisibleControl(screen, approve(screen));
  const first = text(screen, /^Shot 1 of [1-9]\d*$/);
  await expect(first).toBeVisible();
  await app.screenshot('words-approved');
  const count = Number((await first.textContent())?.split(' ').at(-1));
  const mark = button(screen, 'Mark filmed');
  for (let shot = 1; shot <= count; shot += 1) {
    await fit(screen, text(screen, `Shot ${shot} of ${count}`), 'up');
    await tapVisibleControl(screen, mark);
    await expect(button(screen, 'Mark not filmed')).toBeVisible();
    if (shot < count) await tapVisibleControl(screen, button(screen, 'Next'));
  }
  await tapVisibleControl(screen, screen.getByTestId('mira.filming.finish'));
  await expect(text(screen, count === 1 ? '1 clip filmed' : `${count} clips filmed`)).toBeVisible();
  await expect(text(screen, 'Your caption')).toBeVisible();
  await app.screenshot('done');
});

test('3 S1 B1–B3 gate the shot list, open filming and Continue', async ({ app, screen, device }) => {
  const title = todayTitle();
  await launch(app, screen, device);
  const currentShot = text(screen, /^Shot \d+ of \d+$/);
  if (await text(screen, 'Your caption').isVisible()) await back(screen).tap();
  const resume = screen.getByTestId('mira.today.continue');
  if (!await currentShot.isVisible()) {
    await root(screen, 'Home');
    await fit(screen, resume);
    expect(await resume.textContent()).toContain(title);
    await tapVisibleControl(screen, resume);
  }
  if (await approve(screen).count()) {
    await tapVisibleControl(screen, approve(screen));
  }
  await fit(screen, currentShot, 'up');
  const filming = button(screen, /^(Start|Continue) filming$/);
  await openProject(screen, title);
  if (await currentShot.isVisible()) await back(screen).tap();
  if (!await screen.getByRole('pop-up-button', 'Plan options', { exact: true }).count()
    && !await button(screen, 'Plan options').count()) await selectShots(screen);
  await menu(screen, 'Plan options');
  await button(screen, 'Undo last content change').tap();
  await tab(screen, 'Home');
  await expect(screen.getByTestId('mira.approveFirst.message')).toBeVisible();
  await expect(button(screen, 'Mark filmed')).not.toBeVisible();
  await expect(text(screen, /^Shot \d+ of \d+$/)).not.toBeVisible();
  await app.screenshot('b2-filming-closed');

  await tab(screen, 'My Brand');
  const shotGate = screen.getByTestId('mira.shots.approve');
  await fit(screen, shotGate, 'up');
  await expect(filming).not.toBeVisible();
  await app.screenshot('b1-shot-list-approval');
  await tapVisibleControl(screen, shotGate);
  await fit(screen, approve(screen));
  await root(screen, 'Home');
  await fit(screen, resume);
  expect(await resume.textContent()).toContain(title);
  await expect(text(screen, 'Approve your words')).toBeVisible();
  await expect(text(screen, 'Start filming')).not.toBeVisible();
  await app.screenshot('b3-continue-approval');
  await tapVisibleControl(screen, resume);
  await tapVisibleControl(screen, approve(screen));
  await expect(text(screen, /^Shot \d+ of \d+$/)).toBeVisible();
  await root(screen, 'Home');
  await fit(screen, resume);
  expect(await resume.textContent()).toContain(title);
  await expect(text(screen, 'Continue filming')).toBeVisible();
  await app.screenshot('b3-continue-filming');
});

test('4 Make it simpler returns one live revision', async ({ app, screen, device }) => {
  const title = todayTitle();
  await launch(app, screen, device);
  await openProject(screen, title);
  const simpler = screen.getByTestId('mira.words.simpler');
  const opening = screen.getByText('Your opening line', { exact: true });
  while (!await opening.count() && await back(screen).isVisible()) await back(screen).tap();
  if (!await opening.count()) {
    await openProject(screen, title);
    await selectShots(screen);
    const shotGate = screen.getByTestId('mira.shots.approve');
    if (!await shotGate.count()) {
      await menu(screen, 'Plan options');
      await button(screen, 'Undo last content change').tap();
    }
    await tapVisibleControl(screen, shotGate);
  }
  const proposal = screen.getByText("Mira's new version", { exact: true });
  const use = screen.getByTestId('mira.words.use');
  const requested = recorded().some(entry => entry.scenario === 4 && entry.action === 'Make it simpler' && entry.calls);
  const words = screen.getByRole('scroll-view', { visible: true }).first().getByRole('text');
  const wordsAfter = async (heading: string, count: number) => {
    const lines = await words.allTextContents();
    const index = lines.indexOf(heading);
    expect(index).toBeGreaterThanOrEqual(0);
    const copy = lines.slice(index + 1, index + 1 + count);
    expect(copy).toHaveLength(count);
    for (const line of copy) expect(line.trim().length).toBeGreaterThan(0);
    return copy;
  };
  await fit(screen, opening, 'up');
  if (!requested && await proposal.count()) {
    await tapVisibleControl(screen, use);
    await fit(screen, opening, 'up');
    await expect(proposal).toHaveCount(0);
  }
  const oldOpening = await wordsAfter('Your opening line', 1);
  const oldSpoken = await wordsAfter('What you say', 1);
  if (!requested) {
    await fit(screen, simpler);
    await request(4, 'Make it simpler', 1, () => tapVisibleControl(screen, simpler));
  }
  await fit(screen, opening, 'up');
  await waitForOutput(screen, proposal, 'Wait for the simpler live revision.');
  await fit(screen, proposal);
  const [newOpening, newSpoken] = await wordsAfter("Mira's new version", 2);
  expect([newOpening, newSpoken]).not.toEqual([...oldOpening, ...oldSpoken]);
  await app.screenshot('change-result');
  await tapVisibleControl(screen, use);
  await fit(screen, opening, 'up');
  await expect(proposal).toHaveCount(0);
  expect(await wordsAfter('Your opening line', 1)).toEqual([newOpening]);
  expect(await wordsAfter('What you say', 1)).toEqual([newSpoken]);
  record({ scenario: 4, action: 'simpler revision applied', title });
  await app.screenshot('change-applied');
});

async function startStepByStep(screen: Screen) {
  await root(screen, 'My Brand');
  await button(screen, 'Profile').tap();
  await tapVisibleControl(screen, screen.getByTestId('mira.profile.stepByStep'));
  await expect(text(screen, 'Choosing an idea')).toBeVisible();
}

async function closeWithDone(app: App, screen: Screen, field: Locator, value: string, label: string) {
  const keyboard = keyboardWindow(screen);
  await expect(keyboard).toBeVisible();
  await app.screenshot(`${label}-open`);
  await field.press('Enter');
  await expect(keyboard).not.toBeVisible();
  expect(await field.inputValue()).toBe(value);
  await app.screenshot(`${label}-closed`);
}

test('5 Projects Plan step by step makes a live filming plan', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  const field = screen.getByRole('textbox', 'Tell Mira', { exact: true });
  const prompt = 'At home, show the first step of making my morning chai.';
  const projectName = screen.getByRole('textbox', 'Project name', { exact: true });
  const generate = async (label: string, result: Locator, returnToProject = false) => {
    const action = button(screen, label);
    await fit(screen, action);
    await request(5, label, 1, () => tapVisibleControl(screen, action));
    if (returnToProject) await fit(screen, projectName, 'up');
    await waitForOutput(screen, result, `Wait for the result of ${label}.`, 150_000);
  };
  const moreIdeas = button(screen, 'More ideas');
  const history = recorded().filter(entry => entry.scenario === 5);
  const alreadyRequested = (action: string) => history.some(entry => entry.action === action && entry.calls);
  const selectedTitle = history.findLast(entry => entry.action === 'selected step-by-step project')?.title;
  if (selectedTitle) {
    await openProject(screen, selectedTitle);
  } else if (alreadyRequested('Show three ideas')) {
    await fit(screen, field, 'up');
    expect(await field.inputValue()).toBe(prompt);
    await fit(screen, moreIdeas);
  } else {
    await startStepByStep(screen);
    await fit(screen, field);
    await field.fill(prompt);
    await closeWithDone(app, screen, field, prompt, 'step-by-step-tell-mira-keyboard');
    const initialTitle = await projectName.inputValue();
    await projectName.tap();
    const keyboard = keyboardWindow(screen);
    await expect(keyboard).toBeVisible();
    await app.screenshot('step-by-step-project-name-keyboard-open');
    const heading = await text(screen, 'What do you have time for?').boundingBox();
    expect(heading).not.toBeNull();
    await screen.tapAt({ x: heading!.x + heading!.width / 2, y: heading!.y + heading!.height / 2 });
    await expect(keyboard).not.toBeVisible();
    expect(await projectName.inputValue()).toBe(initialTitle);
    await app.screenshot('step-by-step-project-name-keyboard-closed');
    await generate('Show three ideas', moreIdeas);
  }
  if (!selectedTitle) {
    const pick = button(screen, 'Use this idea').first();
    await fit(screen, pick);
    await app.screenshot('step-by-step-live-idea');
    await tapVisibleControl(screen, pick);
  }
  await fit(screen, projectName, 'up');
  const title = await projectName.inputValue();
  expect(title.trim().length).toBeGreaterThan(0);
  expect(title).not.toBe('Untitled Reel');
  if (selectedTitle) expect(title).toBe(selectedTitle);
  else record({ scenario: 5, action: 'selected step-by-step project', title });
  const script = screen.getByRole('textbox', 'Hook · spoken opening', { exact: true });
  if (alreadyRequested('Draft hook, script and caption')) {
    if (!await script.count()) {
      const recheck = button(screen, 'Check again');
      await fit(screen, recheck);
      record({ scenario: 5, action: 'Recheck the saved script job', calls: 0 });
      await tapVisibleControl(screen, recheck);
      await waitForOutput(screen, script, 'Wait for the saved script job.', 150_000);
      await app.screenshot('step-by-step-saved-script-recovered');
    }
  } else {
    await generate('Draft hook, script and caption', script);
  }
  const shots = screen.getByText('Your filming plan', { exact: true });
  await generate('Make shot list', shots, true);
  await fit(screen, shots, 'up');
  await expect(screen.getByText(/^About \d+ seconds edited · [1-9]\d* shots?$/)).toHaveCount(1);
  await app.screenshot('step-by-step-filming-plan');
  await launch(app, screen, device);
  await fit(screen, shots, 'up');
  const lastDetail = screen.getByText('More filming details', { exact: true }).last();
  await fit(screen, lastDetail);
  const detailBox = await lastDetail.boundingBox();
  const tabBar = screen.getByRole('tablist', 'Tab Bar', { exact: true });
  const tabBox = await tabBar.boundingBox();
  expect(detailBox!.y + detailBox!.height).toBeLessThanOrEqual(tabBox!.y - 8);
  await app.screenshot('step-by-step-first-shot-after-relaunch');
  await fit(screen, projectName, 'up');
  expect(await projectName.inputValue()).toBe(title);
});

test('Keyboard Profile closes with Done without editing the saved name', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await root(screen, 'Home');
  await button(screen, 'Profile').tap();
  const field = screen.getByRole('textbox', 'Your name', { exact: true });
  await fit(screen, field);
  const value = await field.inputValue();
  await field.tap();
  await closeWithDone(app, screen, field, value, 'profile-name-keyboard');
});

test('Keyboard manual idea closes with Done and keeps the title', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await startStepByStep(screen);
  await tapVisibleControl(screen, button(screen, 'Add my own idea'));
  const field = screen.getByRole('textbox', 'Idea title', { exact: true });
  const title = 'Morning chai';
  await field.fill(title);
  await closeWithDone(app, screen, field, title, 'manual-idea-keyboard');
  await fit(screen, button(screen, 'Use my idea'));
  await button(screen, 'Cancel').tap();
});

test('6 Profile changes Look from Dark to Light and shows Problem reports', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await root(screen, 'Home');
  await button(screen, 'Profile').tap();
  const look = screen.getByTestId('mira.profile.look');
  await expect(look).toBeVisible();
  for (const appearance of ['Dark', 'Light']) {
    const choice = look.getByRole('button', appearance, { exact: true });
    await choice.tap();
    await expect(choice).toBeSelected();
    await app.screenshot(`look-${appearance.toLowerCase()}`);
  }
  const reports = screen.getByTestId('mira.profile.problemReports');
  const reportTitle = reports.getByText('Problem reports', { exact: true });
  await fit(screen, reportTitle);
  await app.screenshot('problem-reports');
});


test('S2 saved live plan scrolls the final shot above the tab bar', async ({ app, screen, device }) => {
  const title = recorded().findLast(entry => entry.action === 'selected step-by-step project')?.title;
  test.skip(!title, 'The live step-by-step project is required.');
  await launch(app, screen, device);
  await root(screen, 'My Brand');
  const savedPlan = screen.getByRole('button').filter({ hasText: title! })
    .filter({ hasText: /Start filming|Continue filming/ }).first();
  await tapVisibleControl(screen, savedPlan);
  if (await text(screen, /^Shot \d+ of \d+$/).isVisible()) await back(screen).tap();
  await selectShots(screen);
  const summary = screen.getByText(/^About \d+ seconds edited · [1-9]\d* shots?$/);
  await fit(screen, summary, 'up');
  const shotCount = (await summary.textContent()).match(/ · (\d+) shots?$/)?.[1];
  expect(shotCount).toBeTruthy();
  await fit(screen, screen.getByText(`Shot ${shotCount}`, { exact: true }));

  const page = await screen.getByRole('scroll-view', { visible: true }).first().boundingBox();
  const tabs = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  expect(page).not.toBeNull();
  expect(tabs).not.toBeNull();
  const x = page!.x + page!.width / 2;
  const swipe = () => screen.swipe({
    from: { x, y: tabs!.y - 36 },
    to: { x, y: page!.y + 70 },
  });
  for (let step = 0; step < 4; step += 1) await swipe();
  const detail = screen.getByText('More filming details', { exact: true, visible: true }).last();
  await expect(detail).toBeVisible();
  const bottom = async () => {
    const box = await detail.boundingBox();
    return box!.y + box!.height;
  };
  const settledBottom = await bottom();
  await swipe();
  await expect.poll(bottom).toBeCloseTo(settledBottom, 0);
  expect(settledBottom).toBeLessThanOrEqual(tabs!.y - 8);
  await app.screenshot('final-shot-above-tab-bar');

  await launch(app, screen, device);
  const start = button(screen, /^(Start|Continue) filming$/);
  await fit(screen, start, 'up');
  await tapVisibleControl(screen, start);
  const currentShot = text(screen, new RegExp(`^Shot \\d+ of ${shotCount}$`));
  await expect(currentShot).toBeVisible();
  const filming = text(screen, (await currentShot.textContent())!);
  await expect(filming).toBeVisible();
  await launch(app, screen, device);
  await expect(filming).toBeVisible();
  const footer = text(screen, 'Mira does not record or analyse footage. Filmed is progress you report yourself.');
  await fit(screen, footer);
  const footerBox = await footer.boundingBox();
  const filmingTabs = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  expect(footerBox!.y + footerBox!.height).toBeLessThanOrEqual(filmingTabs!.y - 8);
  await app.screenshot('filming-bottom-after-relaunch');
});

test('S2 Projects list scrolls its final row above the tab bar', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await root(screen, 'My Brand');
  const page = await screen.getByRole('scroll-view', { visible: true }).first().boundingBox();
  const tabs = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  expect(page).not.toBeNull();
  expect(tabs).not.toBeNull();
  const x = page!.x + page!.width / 2;
  const swipe = () => screen.swipe({
    from: { x, y: tabs!.y - 36 },
    to: { x, y: page!.y + 70 },
  });
  const lastDelete = screen.getByRole('button', 'Delete', { exact: true, visible: true }).last();
  const rowPosition = async () => {
    const box = await lastDelete.boundingBox();
    return box!.y + box!.height;
  };
  for (let step = 0; step < 16; step += 1) await swipe();
  const settledPosition = await rowPosition();
  await swipe();
  await expect.poll(rowPosition).toBeCloseTo(settledPosition, 0);
  expect(settledPosition).toBeLessThanOrEqual(tabs!.y - 8);
  await app.screenshot('projects-final-row-above-tab-bar');
});

test('Astra live smoke opens filming from approved Today words within three requests', async ({ app, screen, device }) => {
  expect(process.env.MIRA_E2E_LIVE_REQUEST_LIMIT).toBe('3');
  await launch(app, screen, device);
  const make = await todayKeyboard(app, screen);
  await request(28, 'Make one Today batch', 3, () => make.tap());
  await expect(screen.getByRole('button', /^Idea [1-3] of 3, ready$/).first()).toBeVisible({ timeout });
  let card = 0;
  for (const index of [1, 2, 3]) {
    const ready = button(screen, `Idea ${index} of 3, ready`);
    if (!await ready.count()) continue;
    await ready.tap();
    card = index;
    break;
  }
  expect(card).toBeGreaterThan(0);
  await app.screenshot('live-today-card');
  await tapVisibleControl(screen, screen.getByTestId(`mira.today.makeCard.${card}`));
  await expect(text(screen, 'What you say')).toBeVisible();
  await app.screenshot('live-your-words');
  await tapVisibleControl(screen, approve(screen));
  const shoot = screen.getByTestId('mira.shots.film');
  await expect(shoot).toBeAttached({ timeout: 45_000 });
  await tapVisibleControl(screen, shoot);
  await expect(text(screen, /^Shot 1 of [3-5]$/)).toBeVisible({ timeout: 45_000 });
  await expect(text(screen, 'Mira needs to update the shots')).not.toBeAttached();
  await app.screenshot('live-approved-shots-filming');
});

const e3DealLink = (screen: Screen) => button(screen, 'Open deal for Peak Sip').first();

async function e3Request(operation: 'dealBrief' | 'pickIdea', tap: () => Promise<void>) {
  const cap = operation === 'dealBrief' ? 3 : 2;
  const spent = recorded().filter(entry => entry.action === operation)
    .reduce((total, entry) => total + (entry.calls ?? 0), 0);
  expect(spent + 1).toBeLessThanOrEqual(cap);
  await request(operation === 'dealBrief' ? 31 : 32, operation, 1, tap);
}

test('E3 live brief reads, confirms and opens the deal from Home', async ({ app, screen, device }) => {
  test.skip(process.env.MIRA_E2E_E3_LIVE !== '1', 'Enable only after the Keep checks and signed install.');
  await launch(app, screen, device);
  await root(screen, 'Deals');

  const review = button(screen, 'Looks right');
  if (!await review.count() && !await e3DealLink(screen).count()) {
    const reconnect = button(screen, 'Reconnect');
    if (await reconnect.count()) {
      expect(recorded().some(entry => entry.action === 'dealBrief')).toBe(true);
      await tapVisibleControl(screen, reconnect);
    } else {
      const paste = button(screen, 'Paste a brief');
      if (await paste.count()) await tapVisibleControl(screen, paste);
      const draft = screen.getByRole('textbox', 'Brand brief', { exact: true });
      const current = await draft.inputValue();
      expect(current === '' || current === e3Brief).toBe(true);
      if (current !== e3Brief) {
        await device.setClipboard(e3Brief);
        await tapVisibleControl(screen, screen.getByTestId('mira.deals.paste'));
      }
      expect(await draft.inputValue()).toBe(e3Brief);
      await app.screenshot('e3-live-pasted');
      await e3Request('dealBrief', () => tapVisibleControl(screen, button(screen, 'Read this brief')));
    }
    await expect(review).toBeAttached({ timeout });
  }
  if (await review.count()) {
    await expect(screen.getByText('₹25,000 + GST', { exact: true })).toBeAttached();
    await expect(screen.getByText('Due 8 December 2026.', { exact: true })).toBeAttached();
    for (const excerpt of e3Deliverables) {
      await expect(screen.getByText(excerpt, { exact: true })).toBeAttached();
    }
    await app.screenshot('e3-live-deal-review');
    await fit(screen, screen.getByText('Check with the brand', { exact: true }));
    await app.screenshot('e3-live-unresolved');
    await tapVisibleControl(screen, review);
    await expect(screen.getByText('Peak Sip', { exact: true })).toBeVisible();
    await app.screenshot('e3-live-confirmed');
    await button(screen, 'Close').tap();
  }
  await root(screen, 'Home');
  await fit(screen, e3DealLink(screen));
  await expect(screen.getByText('₹25,000 + GST', { exact: true }).first()).toBeVisible();
  await expect(screen.getByText('Due 8 December 2026.', { exact: true }).first()).toBeVisible();
  await app.screenshot('e3-live-home-deal');
  await tapVisibleControl(screen, e3DealLink(screen));
  await expect(button(screen, 'Mark as posted')).toBeAttached();
});

test('E3 live pick uses the active reviewed deal after E2 integration', async ({ app, screen, device }) => {
  test.skip(process.env.MIRA_E2E_E3_LIVE !== '1' || process.env.MIRA_E2E_E3_PICK_READY !== '1',
    'Enable only after E2 sends the active deal checklist in pickIdea.');
  await launch(app, screen, device);
  await root(screen, 'Home');
  await expect(e3DealLink(screen)).toBeAttached();
  const bar = screen.getByTestId('mira.ask.bar');
  await bar.fill('Make an idea I can film at home for my latest deal.');
  await e3Request('pickIdea', () => button(screen, 'Send to Mira').tap());
  await expect(text(screen, 'My pick for you')).toBeVisible({ timeout });
  await app.screenshot('e3-live-pick');
  const code = screen.getByText(/SIP20/).first();
  if (!await code.count()) await tapVisibleControl(screen, button(screen, 'Make this one'));
  await expect(code).toBeAttached({ timeout: 45_000 });
  await fit(screen, code);
  await app.screenshot('e3-live-pick-deal-code');
});
