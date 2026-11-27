import { test, type Device } from '@e2e-dev/mobile';
import { expect, type App, type Locator, type Screen } from 'e2e';
import { appendFileSync, mkdirSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { scrollToControl, tapVisibleControl } from './mobile-support';

const evidence = resolve('work/evidence/t1b-phone/live-journey');
const ledgerPath = resolve(evidence, 'live-requests.jsonl');
const timeout = 240_000;
const recorded = () => {
  try {
    return readFileSync(ledgerPath, 'utf8').trim().split('\n').filter(Boolean).map(line => JSON.parse(line) as Entry);
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'ENOENT') return [];
    throw error;
  }
};

type Entry = { scenario: number; action: string; calls?: number; title?: string };

function record(entry: Entry) {
  mkdirSync(evidence, { recursive: true });
  appendFileSync(ledgerPath, `${JSON.stringify({ at: new Date().toISOString(), ...entry })}\n`, { mode: 0o600 });
}

async function request(scenario: number, action: string, calls: number, tap: () => Promise<void>) {
  const prior = recorded();
  expect(prior.reduce((total, entry) => total + (entry.calls ?? 0), 0) + calls).toBeLessThanOrEqual(40);
  expect(prior.filter(entry => entry.action === action && entry.calls)).toHaveLength(0);
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
  await root(screen, 'Projects');
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
    const failure = screen.getByText(/^(Mira could not finish\.|Could not check this idea\.|Allow AI to write ideas first\.)/, { visible: true });
    if (await screen.getByRole('alert', 'Mira', { exact: true }).isVisible() || await failure.isVisible()) {
      return 'Mira reported a generation failure';
    }
    return await output.count() ? 'ready' : 'waiting';
  }, { timeout: limit, interval: 3_000, message }).not.toBe('waiting');
  await expect(output).toHaveCount(1);
}

test('1 Today brings back three live cards and opens the chosen filming plan', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await root(screen, 'Today');
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
  const gym = screen.getByTestId('mira.today.chip.gym');
  const ten = screen.getByTestId('mira.today.chip.10min');
  await expect(gym).toBeSelected();
  if (!await screen.getByRole('button', '10 min', { exact: true, selected: true }).isVisible()) await ten.tap();
  await expect(ten).toBeSelected();
  expect(await field.inputValue()).toBe(`${prompt}, 10 minutes`);
  await expect(make).toBeEnabled();
  const makeBox = await make.boundingBox();
  const pageBox = await screen.getByRole('scroll-view', { visible: true }).first().boundingBox();
  const tabBox = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  expect(makeBox!.y).toBeGreaterThanOrEqual(pageBox!.y);
  expect(makeBox!.y + makeBox!.height).toBeLessThanOrEqual(Math.min(pageBox!.y + pageBox!.height, tabBox!.y));
  await app.screenshot('keyboard-closed');

  const deadline = Date.now() + timeout;
  await request(1, "Make today's Reel", 3, () => make.tap());
  const ready = screen.getByRole('button', /^Idea [1-3] of 3, ready$/);
  const failed = screen.getByRole('button', /^Idea [1-3] of 3, (did not load|needs an update)$/);
  await expect.poll(async () => {
    if (await failed.count() || await screen.getByRole('alert', 'Mira', { exact: true }).isVisible()
      || await screen.getByTestId('mira.today.aiPermissionNeeded').isVisible()) return 'failed';
    return await ready.count() === 3 ? 'ready' : 'waiting';
  }, { timeout: Math.max(1, deadline - Date.now()), interval: 3_000 }).not.toBe('waiting');
  await expect(ready).toHaveCount(3);
  await app.screenshot('cards-ready');

  const firstPage = screen.getByTestId('mira.today.page.1');
  await firstPage.tap();
  const titles: string[] = [];
  for (let card = 1; card <= 3; card += 1) {
    await expect(text(screen, `${card} of 3`)).toBeVisible();
    const makeCard = screen.getByTestId(`mira.today.makeCard.${card}`);
    const cardView = screen.getByRole('scroll-view').filter({ has: makeCard }).last();
    const heading = cardView.getByRole('text', { visible: true }).first();
    await expect(heading).toBeVisible();
    const title = (await heading.textContent())?.trim() ?? '';
    expect(title.length).toBeGreaterThan(0);
    titles.push(title);
    record({ scenario: 1, action: `Today card ${card}`, title });
    await app.screenshot(`card-${card}`);
    if (card < 3) {
      const box = await heading.boundingBox();
      const area = await cardView.boundingBox();
      const y = box!.y + box!.height / 2;
      await screen.swipe({ from: { x: area!.x + area!.width * 0.88, y }, to: { x: area!.x + area!.width * 0.12, y } });
    }
  }

  const chosen = titles[2];
  await tapVisibleControl(screen, screen.getByTestId('mira.today.makeCard.3'));
  record({ scenario: 1, action: 'selected Today project', title: chosen, calls: 0 });
  await fit(screen, approve(screen));
  await openProject(screen, chosen);
  await fit(screen, approve(screen));
  await back(screen).tap();
  const projectName = screen.getByRole('textbox', 'Project name', { exact: true });
  expect(await projectName.inputValue()).toBe(chosen);
  await selectShots(screen);
  await fit(screen, text(screen, 'Your filming plan'));
  await app.screenshot('chosen-plan');
});

test('2 Your words opens filming and reaches Done', async ({ app, screen, device }) => {
  const title = todayTitle();
  await launch(app, screen, device);
  await root(screen, 'Today');
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
    await root(screen, 'Today');
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
  await tab(screen, 'Today');
  await expect(screen.getByTestId('mira.approveFirst.message')).toBeVisible();
  await expect(button(screen, 'Mark filmed')).not.toBeVisible();
  await expect(text(screen, /^Shot \d+ of \d+$/)).not.toBeVisible();
  await app.screenshot('b2-filming-closed');

  await tab(screen, 'Projects');
  const shotGate = screen.getByTestId('mira.shots.approve');
  await fit(screen, shotGate, 'up');
  await expect(filming).not.toBeVisible();
  await app.screenshot('b1-shot-list-approval');
  await tapVisibleControl(screen, shotGate);
  await fit(screen, approve(screen));
  await root(screen, 'Today');
  await fit(screen, resume);
  expect(await resume.textContent()).toContain(title);
  await expect(text(screen, 'Approve your words')).toBeVisible();
  await expect(text(screen, 'Start filming')).not.toBeVisible();
  await app.screenshot('b3-continue-approval');
  await tapVisibleControl(screen, resume);
  await tapVisibleControl(screen, approve(screen));
  await expect(text(screen, /^Shot \d+ of \d+$/)).toBeVisible();
  await root(screen, 'Today');
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
  while (!await simpler.count() && await back(screen).isVisible()) await back(screen).tap();
  if (!await simpler.count()) {
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
  if (!recorded().some(entry => entry.action === 'Make it simpler' && entry.calls)) {
    await fit(screen, simpler);
    await request(4, 'Make it simpler', 1, () => tapVisibleControl(screen, simpler));
  }
  await waitForOutput(screen, proposal, 'Wait for the simpler live revision.');
  await fit(screen, proposal);
  record({ scenario: 4, action: 'simpler revision displayed', title });
  await app.screenshot('change-result');
});

test('5 Projects Plan step by step makes a live filming plan', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await root(screen, 'Projects');
  await button(screen, 'Profile').tap();
  await tapVisibleControl(screen, screen.getByTestId('mira.profile.stepByStep'));
  await expect(text(screen, 'Choosing an idea')).toBeVisible();
  const field = screen.getByRole('textbox', 'Tell Mira', { exact: true });
  await fit(screen, field);
  await field.fill('At home, show the first step of making my morning chai.');
  const keyboard = keyboardWindow(screen);
  if (await keyboard.isVisible()) await text(screen, 'What do you have time for?').tap();
  await expect(keyboard).not.toBeVisible();

  const generate = async (label: string, result: Locator) => {
    const action = button(screen, label);
    await fit(screen, action);
    await request(5, label, 1, () => tapVisibleControl(screen, action));
    await waitForOutput(screen, result, `Wait for the result of ${label}.`, 150_000);
  };
  const pick = button(screen, 'Use this idea').first();
  await generate('Show three ideas', button(screen, 'More ideas'));
  await expect(button(screen, 'Use this idea')).toHaveCount(3);
  await tapVisibleControl(screen, pick);
  const projectName = screen.getByRole('textbox', 'Project name', { exact: true });
  const title = await projectName.inputValue();
  expect(title.trim().length).toBeGreaterThan(0);
  expect(title).not.toBe('Untitled Reel');
  record({ scenario: 5, action: 'selected step-by-step project', title });
  const makeShots = button(screen, 'Make shot list');
  await generate('Draft hook, script and caption', screen.getByRole('textbox', 'Hook · spoken opening', { exact: true }));
  const shots = screen.getByText('Your filming plan', { exact: true });
  await generate('Make shot list', shots);
  await fit(screen, shots, 'up');
  await expect(screen.getByText(/^About \d+ seconds edited · [1-9]\d* shots?$/)).toHaveCount(1);
  expect(await projectName.inputValue()).toBe(title);
  await app.screenshot('step-by-step-filming-plan');
});

test('6 Profile changes Look from Dark to Light and shows Problem reports', async ({ app, screen, device }) => {
  await launch(app, screen, device);
  await root(screen, 'Today');
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
