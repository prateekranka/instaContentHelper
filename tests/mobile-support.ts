import { expect, type Screen, type Locator } from 'e2e';

export async function tapVisibleControl(screen: Screen, locator: Locator) {
  await scrollToControl(screen, locator);
  await expect(locator).toBeVisible();
  await expect(locator).toBeEnabled();
  const box = await stableBox(locator);
  await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
}

// Scroll through the actual app scroll view. A screen-wide synthesized scroll
// can land on the fixed command bar when Dynamic Type makes that bar tall.
export async function scrollToControl(screen: Screen, locator: Locator, direction: 'up' | 'down' = 'down', bottom?: number) {
  const scope = screen;
  const containingScrollView = screen.getByRole('scroll-view', { visible: true }).filter({ has: locator }).first();
  const scrollView = await containingScrollView.count() === 1
    ? containingScrollView : screen.getByRole('scroll-view', { visible: true }).first();
  let initialBox = await controlBox(locator);
  if (!initialBox) {
    await scrollView.scrollUntilVisible(locator, { direction });
    initialBox = await locator.boundingBox();
  }
  const scrollBox = await scrollView.boundingBox();
  const tabs = screen.getByRole('tablist', 'Tab Bar', { exact: true, visible: true });
  const tabBar = await controlBox(tabs)
    ?? { x: scrollBox.x, y: scrollBox.y + scrollBox.height, width: scrollBox.width, height: 0 };
  const visibleTop = Math.max(8, scrollBox.y + 2);
  const targetTop = Math.max(8, scrollBox.y - 0.5);
  const keyboard = screen.getByTestId('UIKeyboardLayoutStar Preview', { visible: true });
  const keyboardTop = (await controlBox(keyboard))?.y ?? tabBar.y;
  const viewportBottom = Math.min(tabBar.y - 8, keyboardTop - 8, bottom ?? tabBar.y);
  let visibleBottom = Math.min(viewportBottom, scrollBox.y + scrollBox.height - 2);
  for (const role of ['button', 'link'] as const) {
    const controls = scope.getByRole(role, { visible: true });
    const contentControls = await scrollView.getByRole(role, { visible: true }).all();
    const contentBoxes = await Promise.all(contentControls.map(control => control.boundingBox()));
    for (const control of await controls.all()) {
      const box = await control.boundingBox();
      if (contentBoxes.some(content => content.x === box.x && content.y === box.y
        && content.width === box.width && content.height === box.height)) continue;
      if (box.width > 0 && box.height > 0
        && box.x < scrollBox.x + scrollBox.width && box.x + box.width > scrollBox.x
        && box.y >= (visibleTop + viewportBottom) / 2 && box.y < viewportBottom) {
        visibleBottom = Math.min(visibleBottom, box.y - 8);
      }
    }
  }
  const swipeMid = (visibleBottom + visibleTop) / 2;
  const swipeDelta = Math.min(88, Math.max(0, (visibleBottom - visibleTop) * 0.34));
  const swipeFrom = swipeMid + swipeDelta / 2;
  const swipeTo = swipeMid - swipeDelta / 2;
  const swipeLeft = Math.max(tabBar.x + 8, scrollBox.x + 8);
  const swipeRight = Math.min(tabBar.x + tabBar.width - 8, scrollBox.x + scrollBox.width - 8);
  const x = (swipeLeft + swipeRight) / 2;
  let lastDirection: 'up' | 'down' = direction;
  for (let attempt = 0; attempt < 24; attempt += 1) {
    const candidate = attempt === 0 ? initialBox : await controlBox(locator);
    if (candidate) {
      const box = await stableBox(locator, candidate);
      let targetBottom = visibleBottom;
      if (box.y + box.height > visibleBottom) {
        const inScrollView = await scrollView.filter({ has: locator }).count() > 0;
        targetBottom = inScrollView ? visibleBottom : viewportBottom;
      }
      if (box.width > 0 && box.height > 0 && box.y >= targetTop && box.y + box.height <= targetBottom) return;
      lastDirection = box.y < targetTop ? 'up' : 'down';
    }
    expect(visibleBottom).toBeGreaterThan(visibleTop);
    expect(swipeRight).toBeGreaterThan(swipeLeft);
    if (lastDirection === 'up') await screen.swipe({ from: { x, y: swipeTo }, to: { x, y: swipeFrom } });
    else await screen.swipe({ from: { x, y: swipeFrom }, to: { x, y: swipeTo } });
  }
  await expect(locator).toBeVisible();
  const box = await stableBox(locator);
  expect(box.width).toBeGreaterThan(0);
  expect(box.height).toBeGreaterThan(0);
  expect(box.y).toBeGreaterThanOrEqual(targetTop);
  const inScrollView = await scrollView.filter({ has: locator }).count() > 0;
  expect(box.y + box.height).toBeLessThanOrEqual(inScrollView ? visibleBottom : viewportBottom);
}

async function controlBox(locator: Locator) {
  try {
    const box = await locator.boundingBox();
    expect(box).not.toBeNull();
    return box;
  } catch (error) {
    if (error instanceof Error && 'code' in error && error.code === 'LOCATOR_NOT_FOUND') return null;
    throw error;
  }
}

async function stableBox(locator: Locator, initialBox?: Awaited<ReturnType<Locator['boundingBox']>>) {
  let box = initialBox ?? await locator.boundingBox();
  let stableSamples = 0;
  await expect.poll(async () => {
    const next = await controlBox(locator);
    const stable = box !== null && next !== null && next.width > 0 && next.height > 0
      && next.x === box.x && next.y === box.y
      && next.width === box.width && next.height === box.height;
    box = next;
    stableSamples = stable ? stableSamples + 1 : 0;
    return stableSamples >= 3;
  }).toBe(true);
  return box!;
}
