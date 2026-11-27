import { expect, type Screen, type Locator } from 'e2e';

export async function waitForMobileApp(screen: Screen) {
  await expect.poll(async () => {
    try {
      await screen.getByTestId('BackButton').count();
      return true;
    } catch (error) {
      if (error instanceof Error && /is not running/.test(error.message)) return false;
      throw error;
    }
  }, { timeout: 20_000, interval: 1_000 }).toBe(true);
}

export async function tapVisibleControl(screen: Screen, locator: Locator) {
  const scrolledBox = await scrollToControl(screen, locator);
  await expect(locator).toBeVisible();
  await expect(locator).toBeEnabled();
  const next = await controlBox(locator);
  const box = next && sameBox(next, scrolledBox) ? next : await stableBox(locator);
  await screen.tapAt({ x: box.x + box.width / 2, y: box.y + box.height / 2 });
}

export function mobileKeyboard(screen: Screen) {
  return screen.getByTestId('UIKeyboardLayoutStar Preview', { visible: true });
}

export async function closeKeyboard(screen: Screen, field: Locator) {
  const keyboard = mobileKeyboard(screen);
  if (await keyboard.isVisible()) await field.press('Enter');
  await expect(keyboard).not.toBeVisible();
}

async function floatingBoxes(screen: Screen, scrollView: Locator, role: 'button' | 'link') {
  const everyLocator = screen.getByRole(role, { visible: true });
  const contentLocator = scrollView.getByRole(role, { visible: true });
  const every = await everyLocator.allTextContents();
  const content = await contentLocator.allTextContents();
  const starts: number[] = [];
  for (let start = 0; start + content.length <= every.length; start += 1) {
    if (content.every((text, index) => every[start + index] === text)) starts.push(start);
  }
  const controls = await everyLocator.all();
  if (controls.length === every.length && content.length === 0) return readBoxes(controls);
  if (controls.length === every.length && starts.length === 1) {
    const outside = controls.filter((_, index) => index < starts[0] || index >= starts[0] + content.length);
    return readBoxes(outside);
  }
  const contentBoxes = await readBoxes(await contentLocator.all());
  const boxes = await readBoxes(controls);
  return boxes.filter(box => !contentBoxes.some(other => sameBox(other, box)));
}

async function readBoxes(controls: Locator[]) {
  const boxes: Box[] = [];
  for (const control of controls) boxes.push(await control.boundingBox());
  return boxes;
}

type Box = Awaited<ReturnType<Locator['boundingBox']>>;

function sameBox(first: Box, second: Box) {
  return first !== null && second !== null && first.x === second.x && first.y === second.y
    && first.width === second.width && first.height === second.height;
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
  const keyboard = mobileKeyboard(screen);
  const keyboardTop = (await controlBox(keyboard))?.y ?? tabBar.y;
  const viewportBottom = Math.min(tabBar.y - 8, keyboardTop - 8, bottom ?? tabBar.y);
  let visibleBottom = Math.min(viewportBottom, scrollBox.y + scrollBox.height - 2);
  const safeBottom = Math.min(visibleBottom, (visibleTop + viewportBottom) / 2 - 8);
  const inSafeArea = (box: Box) => box !== null && box.width > 0 && box.height > 0
    && box.y >= targetTop && box.y + box.height <= safeBottom;
  if (inSafeArea(initialBox)) {
    const box = await stableBox(locator, initialBox);
    if (inSafeArea(box)) return box;
  }
  for (const role of ['button', 'link'] as const) {
    for (const box of await floatingBoxes(scope, scrollView, role)) {
      if (box && box.width > 0 && box.height > 0
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
      if (box.width > 0 && box.height > 0 && box.y >= targetTop && box.y + box.height <= targetBottom) return box;
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
  return box;
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

async function stableBox(locator: Locator, initialBox?: Box) {
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
