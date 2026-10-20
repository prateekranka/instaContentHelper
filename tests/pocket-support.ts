import { expect, type App, type Screen, type Locator } from 'e2e';

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
