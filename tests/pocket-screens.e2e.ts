import { test as mobileTest, type Device } from '@e2e-dev/mobile';
import { expect, type App } from 'e2e';
import type { EngineSnapshot, SemanticNode } from 'e2e/engine';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { selectTab, scrollToControl, tapEditorControl, tapVisibleControl } from './pocket-support';

async function scrollBackupConfirmationIntoView(screen: Screen) {
  const scroller = screen.getByRole('scroll-view').nth(0);
  const bounds = await scroller.boundingBox();
  if (!bounds) throw new Error('Backup sheet scroll view has no visible bounds');

  const confirmation = screen.getByTestId('backup.confirmPosted');
  const x = bounds.x + bounds.width / 2;
  for (let attempt = 0; attempt < 4 && await confirmation.count() === 0; attempt += 1) {
    await screen.swipe({
      from: { x, y: bounds.y + bounds.height * 0.84 },
      to: { x, y: bounds.y + bounds.height * 0.38 },
    });
  }
  await expect(confirmation).toBeVisible();
}

const bundleId = 'com.prateekranka.creatorcontenthelper';
const test = mobileTest.extend<{ catalogSnapshot: { read(): Promise<EngineSnapshot> } }>();
let readSnapshot: () => Promise<EngineSnapshot>;
test.beforeEach(async ({ catalogSnapshot }) => { readSnapshot = () => catalogSnapshot.read(); });
const output = resolve(process.env.POCKET_E2E_OUTPUT ?? 'work/evidence/pocket-screens');
const session = process.env.POCKET_E2E_SESSION ?? `catalog-${Date.now()}`;
const isFoldable = (process.env.POCKET_E2E_DEVICE ?? '').startsWith('E00E0899')
  || (process.env.POCKET_E2E_DEVICE ?? '').startsWith('AE5652E6');

async function launch(device: Device, suffix: string, flags: Record<string, string> = {}) {
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US',
      ...Object.entries({ MCO_FORCE_FIXTURE_UI: '1', MCO_FORCE_APP_MODE: 'creator',
        MCO_QA_SESSION: `${session}-${suffix}`, ...flags })
        .flatMap(([key, value]) => [`-${key}`, value])],
  });
}

// Retain editable text and control geometry alongside every e2e screenshot.
// This describes the observed app, rather than guessing a canvas layout later.
async function capture(app: App, device: Device, name: string, layoutLimit = 160) {
  const screenshot = await app.screenshot(name);
  const snapshot = await readSnapshot();
  const flattened: { node: SemanticNode; parentRef?: string; depth: number }[] = [];
  function visit(node: SemanticNode, parentRef?: string, depth = 0) {
    if (node.states?.hidden) return;
    flattened.push({ node, parentRef, depth });
    for (const child of node.children ?? []) visit(child, node.ref.id, depth + 1);
  }
  visit(snapshot.root);
  const viewport = flattened.find(({ node }) => node.role === 'application')?.node.rect
    ?? { x: 0, y: 0, ...snapshot.viewport };
  const roleNames: Record<string, string> = { other: 'Other', text: 'StaticText', button: 'Button',
    tab: 'Button', textbox: 'TextView', image: 'Image', switch: 'Switch', progressbar: 'ProgressIndicator' };
  const counts: Record<string, number> = {};
  const elements = [];
  for (const { node, parentRef, depth } of flattened) {
    const box = node.rect;
    if (!box || box.width <= 0 || box.height <= 0 || box.x + box.width <= viewport.x
      || box.y + box.height <= viewport.y || box.x >= viewport.x + viewport.width
      || box.y >= viewport.y + viewport.height) continue;
    const role = node.role === 'tablist' ? /tab\s?bar/i.test(node.name ?? '') ? 'TabBar' : 'SegmentedControl'
      : roleNames[node.role ?? ''] ?? node.role ?? 'Other';
    if ((counts[role] ?? 0) >= layoutLimit) continue;
    counts[role] = (counts[role] ?? 0) + 1;
    // Observations cap long values. A field's public input read preserves its
    // complete editable value when it reaches that cap.
    const value = role === 'TextView' && node.value && node.value.length >= 512 && node.testId
      ? await device.locator(`id=${JSON.stringify(node.testId)}`).inputValue() : node.value;
    elements.push({ role, text: node.text ?? node.name ?? null, box, value,
      enabled: !node.states?.disabled, checked: !!node.states?.checked, selected: !!node.states?.selected,
      testId: node.testId, ref: node.ref.id, parentRef, depth });
  }
  await mkdir(resolve(output, 'screen-layouts'), { recursive: true });
  await writeFile(resolve(output, 'screen-layouts', `${name}.json`), JSON.stringify({
    name, screenshotRelativeToAttempt: screenshot, elements, layoutLimit, viewport,
    treeTruncated: !!snapshot.truncated, captureMethod: 'e2e engine observation',
  }, null, 2));
}

test('catalog onboarding, Today states, filming, post text, and backup sheets', async ({ app, screen, device }) => {
  if (process.env.POCKET_E2E_INSTALL === '1') await device.installApp();
  await launch(device, 'journey', { MCO_FORCE_ONBOARDING: '1', MCO_FORCE_EMPTY_TODAY: '1', MCO_SLOW_FIRST_IDEA: '1' });
  await device.setOrientation('portrait');
  if (isFoldable) await device.fold('closed');
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeVisible();
  await capture(app, device, '01-onboarding-empty');
  await screen.getByTestId('onboarding.startingPoint.already_posting').tap();
  await screen.getByTestId('onboarding.interest.books').tap();
  await capture(app, device, '02-onboarding-selected');
  await screen.getByTestId('onboarding.generateFirstDay').tap();
  await expect(screen.getByTestId('onboarding.preparing')).toBeVisible();
  await capture(app, device, '03-onboarding-preparing');
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await capture(app, device, '04-today-ready-no-progress');
  await screen.getByTestId('today.overflow').tap();
  await capture(app, device, '05-today-menu');
  await screen.getByTestId('today.editScenesScript').tap();
  await expect(screen.getByTestId('shootFolio.saveEdits')).toBeVisible();
  await capture(app, device, '05b-edit-scenes-and-script');
  await tapEditorControl(screen, 'shootFolio.cancelEdit');
  await capture(app, device, '05c-shoot-plan');
  await app.back();
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of');
  await capture(app, device, '06-filming-first-shot');
  await screen.getByTestId('shoot.complete').tap();
  await expect(screen.getByTestId('shoot.complete')).toBeDisabled();
  await capture(app, device, '07-filming-shot-complete');
  await app.back();
  await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  await capture(app, device, '08-today-continue-filming');
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('shoot.previous').tap();
  const progress = await screen.getByTestId('shoot.progress').textContent();
  const count = Number(progress?.match(/of\s+(\d+)/)?.[1]);
  expect(count).toBeGreaterThan(1);
  for (let shot = 1; shot <= count; shot++) {
    await capture(app, device, `filming-shot-${shot}-of-${count}`);
    if (await screen.getByTestId('shoot.complete').isEnabled()) await screen.getByTestId('shoot.complete').tap();
    if (shot < count) await screen.getByTestId('shoot.next').tap();
  }
  await expect(screen.getByTestId('post.markPosted')).toBeVisible();
  await capture(app, device, '09-post-ready');
  await screen.getByTestId('post.edit').tap();
  await expect(screen.getByTestId('post.script.editor')).toBeVisible();
  await capture(app, device, '10-post-edit');
  await screen.getByTestId('post.script.editor').tap();
  await expect(screen.getByTestId('post.keyboardDone')).toBeVisible();
  await capture(app, device, '11-post-edit-keyboard');
  await screen.getByTestId('post.keyboardDone').tap();
  try {
    await tapEditorControl(screen, 'post.cancel');
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    if (!message.includes('runner session was invalidated')) throw error;
    await readSnapshot();
  }
  await expect(screen.getByTestId('post.markPosted')).toBeVisible();
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await capture(app, device, '12-posted');
  await app.back();
  await expect(screen.getByTestId('today.startFilming')).toContainText('View posted content');
  await capture(app, device, '13-today-posted');
  await screen.getByTestId('today.notEasier').tap();
  await expect(screen.getByText('Other ideas', { exact: true })).toBeVisible();
  await capture(app, device, '14-other-ideas');
  await screen.getByRole('button', /10-second story/).tap();
  await screen.scrollUntilVisible(screen.getByTestId('backup.confirmPosted'));
  await expect(screen.getByTestId('backup.confirmPosted')).toBeVisible();
  await capture(app, device, '15-story-backup');
  const cancel = await screen.getByRole('button', 'Cancel', { exact: true }).boundingBox();
  await screen.tapAt({ x: cancel.x + cancel.width / 2, y: cancel.y + cancel.height / 2 });
  await screen.getByRole('button', /Caption-only post/).tap();
  await scrollBackupConfirmationIntoView(screen);
  await expect(screen.getByTestId('backup.confirmPosted')).toBeVisible();
  await capture(app, device, '16-caption-backup');
});

test('catalog You and each creator preference screen', async ({ app, screen, device }) => {
  await launch(device, 'preferences');
  await selectTab(screen, 'You');
  await expect(screen.getByTestId('you.preferences.toggle')).toBeVisible();
  await capture(app, device, '20-you-collapsed');
  await screen.getByTestId('you.preferences.toggle').tap();
  await capture(app, device, '21-you-expanded');
  for (const [row, destination, name] of [
    ['account', 'account', '22-account'],
    ['interests', 'interests', '23-interests'],
    ['production', 'production', '24-content-preferences'],
    ['context', 'context', '25-current-context'],
    ['voice', 'voice', '26-creator-voice'],
    ['references', 'references', '27-references-empty'],
  ]) {
    await scrollToControl(screen, screen.getByTestId(`you.row.${row}`));
    await screen.getByTestId(`you.row.${row}`).tap();
    await expect(screen.getByTestId(`you.screen.${destination}`)).toBeVisible();
    await capture(app, device, name);
    await screen.getByRole('button', 'Back to You', { exact: true }).tap();
    await expect(screen.getByTestId('you.preferences.toggle')).toBeVisible();
  }
  // The archive link appears only when there are more than five saved entries.
  await launch(device, 'archive', { MCO_BREAK_UI_DATA: 'worst' });
  await selectTab(screen, 'You');
  await scrollToControl(screen, screen.getByTestId('you.archive.seeMore'));
  await screen.getByTestId('you.archive.seeMore').tap();
  await capture(app, device, '28-archive-populated');
  await screen.getByRole('button', 'Backups', { exact: true }).tap();
  await capture(app, device, '29-archive-filter-empty');
  await screen.getByRole('button', 'All', { exact: true }).tap();
  await screen.getByRole('button', /Đặng Thị Ngọc Hân/).tap();
  await capture(app, device, '29b-archive-detail');
});

test('catalog empty, welcome, retry, and long data states', async ({ app, screen, device }) => {
  await launch(device, 'empty', { MCO_FORCE_EMPTY_TODAY: '1' });
  await expect(screen.getByTestId('today.emptyCard')).toBeVisible();
  await capture(app, device, '30-today-empty');
  await launch(device, 'welcome', { MCO_FORCE_SIGN_IN: '1' });
  await expect(screen.getByTestId('sign-in.welcome')).toBeVisible();
  await capture(app, device, '31-welcome');
  await launch(device, 'retry', { MCO_FORCE_ONBOARDING: '1', MCO_FORCE_EMPTY_TODAY: '1', MCO_FAIL_FIRST_IDEA_ONCE: '1' });
  await screen.getByTestId('onboarding.setUpLater').tap();
  await expect(screen.getByTestId('onboarding.retryFirstIdea')).toBeVisible();
  await capture(app, device, '32-onboarding-error');
  await screen.getByTestId('onboarding.retryFirstIdea').tap();
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await capture(app, device, '33-today-retry-recovered');
  await launch(device, 'long', { MCO_LONG_CONTENT: '1' });
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  await capture(app, device, '34-today-long-content');
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toBeVisible();
  await capture(app, device, '35-filming-long-content');
});

test('from onboarding, create and restore four Story, Reel, and photo packages through Plan', { timeout: 900_000 }, async ({ app, screen, device }) => {
  await launch(device, 'onboarding-plan', {
    MCO_FORCE_ONBOARDING: '1',
    MCO_FORCE_EMPTY_TODAY: '1',
    MCO_SLOW_FIRST_IDEA: '1',
  });
  await device.setOrientation('portrait');
  if (isFoldable) await device.fold('closed');
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeVisible();
  await capture(app, device, '39-onboarding-empty');
  await screen.getByTestId('onboarding.startingPoint.already_posting').tap();
  await screen.getByTestId('onboarding.interest.books').tap();
  await capture(app, device, '39b-onboarding-selected');
  await screen.getByTestId('onboarding.generateFirstDay').tap();
  await expect(screen.getByTestId('onboarding.preparing')).toBeVisible();
  await capture(app, device, '39c-onboarding-preparing');
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await capture(app, device, '39d-today-after-onboarding');
  await selectTab(screen, 'Plan');
  await expect(screen.getByTestId('plan.title')).toBeVisible();
  await capture(app, device, '40-plan-initial');
  const days = screen.getByTestId(/^plan\.sevenDaySelector\.day\./);
  await days.nth(1).tap();
  const voiceGate = screen.getByTestId('plan.voiceGate.setup');
  if (await voiceGate.count() > 0) {
    await scrollToControl(screen, voiceGate);
    await capture(app, device, '41-plan-voice-required');
    await voiceGate.tap();
    await screen.getByTestId('you.voice.positioning').pressSequentially('Small, useful moments from my everyday life.');
    await screen.getByTestId('you.voice.keyboardDone').tap();
    await scrollToControl(screen, screen.getByTestId('you.voice.rules'));
    await screen.getByTestId('you.voice.rules').pressSequentially('Use direct sentences and a calm voice.');
    await screen.getByTestId('you.voice.keyboardDone').tap();
    await scrollToControl(screen, screen.getByTestId('you.voice.save'));
    await screen.getByTestId('you.voice.save').tap();
    await expect(screen.getByTestId('you.voice.save')).toBeDisabled();
    await capture(app, device, '42-creator-voice-saved');
    const backToPlan = screen.getByRole('button', 'Back to Plan', { exact: true });
    await scrollToControl(screen, backToPlan, 'up');
    await backToPlan.tap();
  } else {
    await expect(screen.getByTestId('plan.daygen.panel')).toBeVisible();
    await capture(app, device, '41-plan-idea-launcher-ready');
  }
  await screen.getByTestId('plan.date.header').tap();
  await capture(app, device, '43-plan-calendar');
  await screen.getByRole('button', 'Done', { exact: true }).tap();
  const cases = [
    { day: 1, format: 'Story', duration: '10 sec edit', brief: 'A 10-second Story about the book on my nightstand.', name: '44-story-10-seconds' },
    { day: 2, format: 'Reel', duration: '30 sec edit', brief: 'A 30-second voiceover Reel about my morning coffee routine.', name: '45-reel-30-seconds' },
    { day: 3, format: 'Reel', duration: '60 sec edit', brief: 'A 60-second talking-to-camera Reel about a movie scene I keep thinking about.', name: '46-reel-60-seconds' },
    { day: 4, format: 'Post', duration: 'Photo / carousel', brief: 'A photo carousel about the small details I noticed on my walk. No filming.', name: '47-photo-carousel' },
  ];
  const titles = [];
  for (const item of cases) {
    await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
    await days.nth(item.day).tap();
    await scrollToControl(screen, screen.getByTestId('plan.daygen.other'));
    await screen.getByTestId('plan.daygen.other').tap();
    await scrollToControl(screen, screen.getByTestId('plan.daygen.other.text'));
    await capture(app, device, `${item.name}-direction-empty`);
    await screen.getByTestId('plan.daygen.other.text').pressSequentially(item.brief);
    await capture(app, device, `${item.name}-direction-keyboard`);
    const submitDirection = screen.getByTestId('plan.daygen.other.submit');
    const keyboard = screen.getByTestId('UIKeyboardLayoutStar Preview');
    if (await keyboard.count() > 0) {
      const keyboardBox = await keyboard.boundingBox();
      if (!keyboardBox) throw new Error('Could not measure the onscreen keyboard');
      await scrollToControl(screen, submitDirection, 'down', keyboardBox.y - 8);
      const visibleKeyboardBox = await keyboard.boundingBox();
      const submitBox = await submitDirection.boundingBox();
      if (!visibleKeyboardBox || !submitBox) throw new Error('Could not measure the Generate for this day control and keyboard after scrolling');
      expect(submitBox.y + submitBox.height).toBeLessThanOrEqual(visibleKeyboardBox.y - 8);
    }
    await submitDirection.tap();
    await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
    await scrollToControl(screen, screen.getByTestId('plan.package.title'), 'up');
    titles.push(await screen.getByTestId('plan.package.title').textContent());
    await expect(screen.getByTestId('plan.package.format')).toHaveText(item.format);
    await expect(screen.getByTestId('plan.package.duration')).toHaveText(item.duration);
    await capture(app, device, `${item.name}-draft`);
    for (const tab of ['storyboard', 'script', 'caption']) {
      await scrollToControl(screen, screen.getByTestId(`plan.package.tab.${tab}`));
      await screen.getByTestId(`plan.package.tab.${tab}`).tap();
      await expect(screen.getByTestId(`plan.package.tab.${tab}`)).toBeSelected();
      await capture(app, device, `${item.name}-${tab}`);
    }
    await scrollToControl(screen, screen.getByTestId('daily.availableOnToday'));
    await screen.getByTestId('daily.availableOnToday').tap();
    await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
    await capture(app, device, `${item.name}-saved`);
  }
  expect(new Set(titles).size).toBe(4);
  for (const item of cases) {
    await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
    await days.nth(item.day).tap();
    await expect(screen.getByTestId('plan.package.format')).toHaveText(item.format);
    await expect(screen.getByTestId('plan.package.duration')).toHaveText(item.duration);
    await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  }
  await capture(app, device, '48-plan-packages-saved');

  // Relaunch with the same fixture namespace, then prove Plan restores each saved package.
  await launch(device, 'onboarding-plan');
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  await capture(app, device, '49-today-after-plan-relaunch');
  await selectTab(screen, 'Plan');
  await expect(screen.getByTestId('plan.title')).toBeVisible();
  await capture(app, device, '50-plan-after-relaunch');
  const restoredDays = screen.getByTestId(/^plan\.sevenDaySelector\.day\./);
  for (const item of cases) {
    await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
    await restoredDays.nth(item.day).tap();
    if (item.day === 1) await capture(app, device, '51-plan-first-package-after-relaunch');
    await expect(screen.getByTestId('plan.package.title')).toHaveText(titles[item.day - 1] ?? '');
    await expect(screen.getByTestId('plan.package.format')).toHaveText(item.format);
    await expect(screen.getByTestId('plan.package.duration')).toHaveText(item.duration);
    await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  }
  await capture(app, device, '52-plan-packages-restored-after-relaunch');
});

test('break-ui worst content, large text, and reduced motion remain usable', async ({ app, screen, device }) => {
  for (const [suffix, flags] of [
    ['worst', { MCO_BREAK_UI_DATA: 'worst' }],
    ['large', { MCO_BREAK_UI_DATA: 'worst', MCO_DYNAMIC_TYPE_ACCESSIBILITY5: '1' }],
    ['reduced-motion', { MCO_BREAK_UI_DATA: 'worst', MCO_REDUCED_MOTION: '1' }],
    ['narrow', { MCO_BREAK_UI_DATA: 'worst', MCO_BREAK_UI_320: '1' }],
    ['narrow-large', { MCO_BREAK_UI_DATA: 'worst', MCO_BREAK_UI_320: '1', MCO_DYNAMIC_TYPE_ACCESSIBILITY5: '1' }],
  ] as const) {
    await launch(device, suffix, flags);
    await expect(screen.getByTestId('today.startFilming')).toBeVisible();
    if (suffix === 'large' || suffix === 'narrow-large') {
      const action = await screen.getByTestId('today.startFilming').boundingBox();
      const title = await screen.getByTestId('today.package.title').boundingBox();
      expect(action.y + action.height).toBeLessThanOrEqual(title.y);
    }
    if (suffix.startsWith('narrow')) {
      expect((await screen.getByTestId('today.package.title').boundingBox()).width).toBeLessThanOrEqual(280);
    }
    await capture(app, device, `50-${suffix}-today`);
    const commandTop = suffix.includes('large') ? undefined
      : (await screen.getByTestId('today.startFilming').boundingBox()).y - 16;
    await scrollToControl(screen, screen.getByText('SHOT 01', { exact: true }), 'down', commandTop);
    await capture(app, device, `51-${suffix}-shot-list`);
    if (suffix === 'large' || suffix === 'narrow-large') {
      await scrollToControl(screen, screen.getByTestId('today.startFilming'), 'up');
    }
    await screen.getByTestId('today.startFilming').tap();
    await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of 4');
    const viewport = (await readSnapshot()).viewport;
    if (!viewport) throw new Error('mobile snapshot did not report viewport geometry');
    for (const id of ['shoot.complete', 'shoot.next', 'shoot.previous']) {
      const box = await screen.getByTestId(id).boundingBox();
      expect(box.height).toBeGreaterThanOrEqual(44);
      expect(box.width).toBeGreaterThanOrEqual(44);
      expect(box.x).toBeGreaterThanOrEqual(0);
      expect(box.x + box.width).toBeLessThanOrEqual(viewport.width);
      expect(box.y + box.height).toBeLessThanOrEqual(viewport.height);
    }
    await capture(app, device, `52-${suffix}-filming`);
    await screen.getByTestId('shoot.complete').tap();
    await expect(screen.getByTestId('shoot.complete')).toBeDisabled();
  }
});

test('break-ui zero, one, and 1,284 shots preserve the primary action', async ({ app, screen, device }) => {
  await launch(device, 'zero', { MCO_BREAK_UI_DATA: 'empty' });
  await expect(screen.getByTestId('today.startFilming')).toHaveText('Get post text');
  await capture(app, device, '53-photo-without-shots');
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('post.markPosted')).toBeEnabled();
  await capture(app, device, '54-photo-post-preparation');
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await launch(device, 'zero', { MCO_BREAK_UI_DATA: 'demo' });
  await expect(screen.getByText('Post', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('today.startFilming')).toHaveText('View posted content');
  await capture(app, device, '54b-photo-post-preserved-after-relaunch');

  await launch(device, 'one', { MCO_BREAK_UI_DATA: 'one' });
  await scrollToControl(screen, screen.getByTestId('today.package.sceneProgress'));
  await expect(screen.getByTestId('today.package.sceneProgress')).toHaveText('0 of 1 shot done');
  await capture(app, device, '55-single-shot-today');
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toHaveText('Shot 1 of 1');
  await capture(app, device, '56-single-shot-filming');
  await screen.getByTestId('shoot.complete').tap();
  await expect(screen.getByTestId('post.markPosted')).toBeEnabled();
  await capture(app, device, '57-single-shot-ready-to-post');
  await launch(device, 'one', { MCO_BREAK_UI_DATA: 'demo' });
  await expect(screen.getByText('Story · 10 sec', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('today.startFilming')).toHaveText('Get post text');

  await launch(device, 'huge', { MCO_BREAK_UI_DATA: 'huge' });
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  await capture(app, device, '58-1284-shot-list', 64);
  await screen.getByTestId('today.startFilming').tap();
  await capture(app, device, '59-1284-shot-filming', 64);
  await expect(screen.getByTestId('shoot.progress')).toHaveText('Shot 1 of 1,284');
  await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.progress')).toHaveText('Shot 2 of 1,284');
});

test('break-ui uses the widest foldable window and preserves light appearance', async ({ app, screen, device }) => {
  try {
    await launch(device, 'wide', { MCO_BREAK_UI_DATA: 'worst' });
    if (isFoldable) await device.fold('open');
    await device.setOrientation('landscape-left');
    await device.setAppearance('dark');
    await expect(screen.getByTestId('today.startFilming')).toBeVisible();
    await capture(app, device, '60-wide-today');
    await tapVisibleControl(screen, screen.getByTestId('today.startFilming'));
    await expect(screen.getByTestId('shoot.progress')).toBeVisible();
    await capture(app, device, '61-wide-filming');
  } finally {
    await device.setAppearance('light');
    await device.setOrientation('portrait');
    if (isFoldable) await device.fold('closed');
  }
});
