import { expect, type App, type Screen, type Locator } from 'e2e';
import type { Device } from '@e2e-dev/mobile';
import { randomUUID } from 'node:crypto';

export async function selectTab(screen: Screen, name: 'Today' | 'Plan' | 'You') {
  const bar = screen.getByRole('tablist', 'Tab Bar', { exact: true });
  await expect(bar).toBeVisible();
  const tab = bar.getByRole('tab', name, { exact: true });
  // Native iOS snapshots expose the same UITabBar item as tab or button.
  if (await tab.count() === 1) await tab.tap();
  else await bar.getByRole('button', name, { exact: true }).tap();
}

export async function startFromOnboarding(app: App, screen: Screen) {
  await app.open();
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeVisible();
  await app.screenshot('onboarding-start');
  await screen.getByTestId('onboarding.setUpLater').tap();
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeHidden();
}

// Use a fresh e2e rectangle when the visible target is known but mobile
// hit-testing reports an overlapping accessibility element.
export async function tapVisibleControl(screen: Screen, locator: Locator) {
  await scrollToControl(screen, locator);
  await expect(locator).toBeVisible();
  await expect(locator).toBeEnabled();
  const box = await stableBox(locator);
  await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
}

// iOS can invalidate an element as its editor disappears during a tap.
export async function tapEditorControl(screen: Screen, id: string) {
  await tapVisibleControl(screen, screen.getByTestId(id));
}

// Scroll through the actual app scroll view. A screen-wide synthesized scroll
// can land on the fixed command bar when Dynamic Type makes that bar tall.
export async function scrollToControl(screen: Screen, locator: Locator, direction: 'up' | 'down' = 'down', bottom?: number) {
  const scrollView = screen.getByRole('scroll-view').nth(0);
  if (await locator.count() === 0) await scrollView.scrollUntilVisible(locator, { direction });
  const scrollBox = await scrollView.boundingBox();
  const tabBar = await screen.getByRole('tablist', 'Tab Bar', { exact: true }).boundingBox();
  const visibleTop = scrollBox.y + 2;
  const keyboard = screen.getByTestId('UIKeyboardLayoutStar Preview', { visible: true });
  const keyboardTop = await keyboard.count() === 1 ? (await keyboard.boundingBox()).y : tabBar.y;
  const viewportBottom = Math.min(tabBar.y - 8, keyboardTop - 8, bottom ?? tabBar.y);
  const visibleBottom = Math.min(viewportBottom, scrollBox.y + scrollBox.height - 2);
  const swipeBottom = Math.min(visibleBottom - 20, scrollBox.y + scrollBox.height * 0.76);
  const swipeTop = Math.max(scrollBox.y + 48, scrollBox.y + scrollBox.height * 0.30);
  const swipeMid = (swipeBottom + swipeTop) / 2;
  const swipeDelta = Math.min(88, Math.max(24, (swipeBottom - swipeTop) * 0.34));
  const swipeFrom = swipeMid + swipeDelta / 2;
  const swipeTo = swipeMid - swipeDelta / 2;
  const x = scrollBox.x + scrollBox.width / 2;
  let lastDirection: 'up' | 'down' = direction;
  for (let attempt = 0; attempt < 24; attempt += 1) {
    if (await locator.count() > 0) {
      const box = await stableBox(locator);
      const inScrollView = await scrollView.filter({ has: locator }).count() > 0;
      const targetBottom = inScrollView ? visibleBottom : viewportBottom;
      if (box.y >= visibleTop && box.y + box.height <= targetBottom) return;
      lastDirection = box.y < visibleTop ? 'up' : 'down';
    }
    if (lastDirection === 'up') await screen.swipe({ from: { x, y: swipeTo }, to: { x, y: swipeFrom } });
    else await screen.swipe({ from: { x, y: swipeFrom }, to: { x, y: swipeTo } });
  }
  await expect(locator).toBeVisible();
  const box = await locator.boundingBox();
  expect(box.y).toBeGreaterThanOrEqual(visibleTop);
  expect(box.y + box.height).toBeLessThanOrEqual(visibleBottom);
}

async function stableBox(locator: Locator) {
  let box = await locator.boundingBox();
  let stableSamples = 0;
  await expect.poll(async () => {
    const next = await locator.boundingBox();
    const stable = next.x === box.x && next.y === box.y
      && next.width === box.width && next.height === box.height;
    box = next;
    stableSamples = stable ? stableSamples + 1 : 0;
    return stableSamples >= 3;
  }).toBe(true);
  return box;
}

export async function dismissKeyboard(screen: Screen, id?: string) {
  const keyboard = screen.getByTestId('UIKeyboardLayoutStar Preview', { visible: true });
  const done = screen.getByTestId(id ?? /\.keyboardDone$/, { visible: true });
  if (await done.count() === 1) {
    const box = await stableBox(done);
    await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
    await expect(done).toBeHidden();
    await expect(keyboard).toBeHidden();
    return;
  }
  if (await keyboard.count() === 0) return;
  if (await screen.getByTestId('shootFolio.cancelEdit').count() === 1) {
    const section = await screen.getByTestId('shootFolio.script.editor').count() === 1 ? 'Scenes' : 'Script';
    await scrollToControl(screen, screen.getByRole('button', section, { exact: true }), 'up');
    await tapVisibleControl(screen, screen.getByRole('button', section, { exact: true }));
  }
  await expect(keyboard).toBeHidden();
}

async function editableValue(editor: Locator) {
  const placeholder = await editor.getAttribute('placeholder');
  const value = await editor.inputValue();
  return placeholder && value === placeholder ? '' : value;
}

export async function clearThenType(screen: Screen, editor: Locator, text: string) {
  await scrollToControl(screen, editor);
  let remaining = await editableValue(editor);
  while (remaining.length > 0) {
    const previousLength = remaining.length;
    try {
      await editor.clear();
    } catch (error) {
      if (!(error instanceof Error) || !error.message.includes('text entry verification failed')) throw error;
    }
    await expect.poll(async () => {
      remaining = await editableValue(editor);
      return remaining.length;
    }).toBeLessThan(previousLength);
  }
  await expect.poll(() => editableValue(editor)).toBe('');
  await typeInChunks(editor, text);
}

export async function typeInChunks(editor: Locator, text: string) {
  if (text.length > 0) {
    await editor.pressSequentially(text, { timeout: Math.max(25_000, text.length * 250) });
    await expect(editor).toHaveValue(text);
  } else {
    await expect.poll(() => editableValue(editor)).toBe('');
  }
}

export type LoopScenario = 'initial' | 'ready' | 'line-script' | 'blank-copy' | 'stale-pointer' | 'legacy-cache' | 'old-decision';

export interface LoopSession {
  id: string;
  scenario: LoopScenario;
  flags: Record<string, string>;
}

export async function openLoopSession(device: Device, scenario: LoopScenario = 'ready', flags: Record<string, string> = {}) {
  const session: LoopSession = { id: `loop-${randomUUID()}`, scenario, flags };
  await relaunchLoopSession(device, session);
  return session;
}

export async function relaunchLoopSession(device: Device, session: LoopSession, flags: Record<string, string> = {}) {
  await device.openApp('com.prateekranka.creatorcontenthelper', {
    relaunch: true,
    launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US',
      ...Object.entries({
        MCO_FORCE_FIXTURE_UI: '1', MCO_FORCE_APP_MODE: 'creator',
        MCO_FORCE_ONBOARDING: '0', MCO_FORCE_EMPTY_TODAY: '0',
        MCO_QA_SESSION: session.id, MCO_LOOP_SCENARIO: session.scenario,
        ...session.flags, ...flags,
      }).flatMap(([key, value]) => [`-${key}`, value])],
  });
}

export async function openLoopEditor(screen: Screen) {
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  await screen.getByTestId('today.overflow').tap();
  await screen.getByTestId('today.editScenesScript').tap();
  await expect(screen.getByTestId('shootFolio.cancelEdit')).toBeVisible();
}

export async function saveLoopEditor(screen: Screen, _device: Device) {
  await dismissKeyboard(screen);
  await tapEditorControl(screen, 'shootFolio.saveEdits');
  await expect(screen.getByTestId('shootFolio.edit')).toBeVisible();
}

export async function finishLoopFilming(screen: Screen) {
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 1 of');
  const progress = (await screen.getByTestId('shoot.progress').textContent()) ?? '';
  const count = Number(progress.match(/of\s+(\d+)/)?.[1]);
  expect(count).toBeGreaterThan(0);
  expect(count).toBeLessThanOrEqual(12);
  for (let shot = 1; shot <= count; shot += 1) {
    await expect(screen.getByTestId('shoot.progress')).toContainText(`Shot ${shot} of`);
    await screen.getByTestId('shoot.complete').tap();
    if (shot < count) await screen.getByTestId('shoot.next').tap();
  }
  await expect(screen.getByTestId('post.markPosted')).toBeVisible();
}

export async function openLoopPlanDay(screen: Screen, index: number) {
  await selectTab(screen, 'Plan');
  await scrollToControl(screen, screen.getByTestId('plan.title'), 'up');
  const day = screen.getByTestId(/^plan\.sevenDaySelector\.day\./).nth(index);
  await tapVisibleControl(screen, day);
  await expect(day).toBeSelected();
  return day;
}

export async function requestLoopReplacement(screen: Screen, idea = 1) {
  await tapVisibleControl(screen, screen.getByTestId('plan.package.replaceIdea'));
  await scrollToControl(screen, screen.getByTestId(`plan.daygen.idea.${idea}`), 'up');
  await tapVisibleControl(screen, screen.getByTestId(`plan.daygen.idea.${idea}`));
  await expect(screen.getByRole('button', 'Overwrite', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Overwrite', { exact: true }).tap();
}

export async function approveLoopPackage(screen: Screen) {
  const approve = screen.getByTestId('daily.availableOnToday');
  await scrollToControl(screen, approve);
  await expect(approve).toBeEnabled({ timeout: 45_000 });
  await approve.tap();
  await expect(approve).toBeHidden();
}
