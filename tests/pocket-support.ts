import { expect, type App, type Screen, type Locator } from 'e2e';
import type { Device } from '@e2e-dev/mobile';
import { randomUUID } from 'node:crypto';

export async function selectTab(screen: Screen, name: 'Today' | 'Plan' | 'You') {
  const bar = screen.getByRole('tablist');
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
  const box = await locator.boundingBox();
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
  const scrollBox = await scrollView.boundingBox();
  const tabBar = await screen.getByRole('tablist').boundingBox();
  const visibleTop = scrollBox.y + 2;
  const visibleBottom = Math.min(tabBar.y - 8, bottom ?? tabBar.y);
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
      if (box && box.y >= visibleTop && box.y + box.height <= visibleBottom) return;
      if (!box) continue;
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
  for (let settle = 0; settle < 10; settle += 1) {
    await new Promise((resolve) => setTimeout(resolve, 250));
    if (await locator.count() === 0) return undefined;
    const next = await locator.boundingBox();
    if (next.x === box.x && next.y === box.y) return next;
    box = next;
  }
  return box;
}

export async function dismissKeyboard(screen: Screen, id: string) {
  const done = screen.getByTestId(id);
  for (let attempt = 0; attempt < 4; attempt += 1) {
    if (await done.count() === 0) return;
    const box = await stableBox(done);
    if (!box) return;
    await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
    try {
      await expect(done).toBeHidden({ timeout: 3_000 });
      return;
    } catch {}
  }
  await expect(done).toBeHidden();
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

export async function saveLoopEditor(screen: Screen, device: Device) {
  await device.dismissKeyboard();
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
  await screen.scrollUntilVisible(screen.getByTestId('plan.title'), { direction: 'up' });
  const day = screen.getByTestId(/^plan\.sevenDaySelector\.day\./).nth(index);
  await day.tap();
  await expect(day).toBeSelected();
  return day;
}

export async function requestLoopReplacement(screen: Screen, idea = 1) {
  await screen.scrollUntilVisible(screen.getByTestId('plan.package.replaceIdea'));
  await screen.getByTestId('plan.package.replaceIdea').tap();
  await screen.scrollUntilVisible(screen.getByTestId(`plan.daygen.idea.${idea}`), { direction: 'up' });
  await screen.getByTestId(`plan.daygen.idea.${idea}`).tap();
  await expect(screen.getByRole('button', 'Overwrite', { exact: true })).toBeVisible();
  await screen.getByRole('button', 'Overwrite', { exact: true }).tap();
}

export async function approveLoopPackage(screen: Screen) {
  const approve = screen.getByTestId('daily.availableOnToday');
  await screen.scrollUntilVisible(approve);
  await expect(approve).toBeEnabled({ timeout: 45_000 });
  await approve.tap();
  await expect(approve).toBeHidden();
}
