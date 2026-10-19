import { expect, type App, type Screen, type Locator } from 'e2e';
import type { Device } from '@e2e-dev/mobile';

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
  await expect(screen.getByTestId('today.piece.0')).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByTestId('today.primaryAction')).toBeVisible();
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeHidden();
}

export async function relaunch(device: Device) {
  await device.openApp('com.prateekranka.creatorcontenthelper', {
    relaunch: true,
    launchArguments: ['-MCO_FORCE_FIXTURE_UI', '1', '-MCO_FORCE_APP_MODE', 'creator',
      '-MCO_QA_SESSION', process.env.POCKET_E2E_SESSION!, '-MCO_FORCE_ONBOARDING', '0'],
  });
}

// Writes a piece without AI from the open composer and returns to the day.
export async function writePiece(screen: Screen, topic: string) {
  await expect(screen.getByTestId('composer.topic')).toBeVisible();
  await screen.getByTestId('composer.topic').pressSequentially(topic);
  await screen.getByTestId('composer.writeMyself').tap();
  await expect(screen.getByTestId('piece.title')).toHaveText(topic);
  await expect(screen.getByTestId('piece.status')).toContainText('Draft');
  await screen.getByTestId('composer.cancel').tap();
  await expect(screen.getByTestId('composer.cancel')).toBeHidden();
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
      const box = await locator.boundingBox();
      if (box.y >= visibleTop && box.y + box.height <= visibleBottom) return;
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
