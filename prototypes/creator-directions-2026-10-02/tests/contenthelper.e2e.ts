import { test } from '@e2e-dev/web';
import { expect } from 'e2e';
import type { App, Screen } from 'e2e';

const variants = [
  ['A', 'Start filming'],
  ['B', 'Let’s make this'],
  ['C', 'Start take one'],
  ['D', 'Show me the shots'],
] as const;

const readyContentSelectors: Record<string, { title: string; openingLine: string; effort: string }> = {
  A: { title: '.pocket-hero-copy h2', openingLine: '.pocket-hero-copy .hook', effort: '.pocket-hero-copy .meta-row' },
  B: { title: '.daybook-title h2', openingLine: '.daybook-quote p', effort: '.daybook-title .meta-row' },
  C: { title: '.studio-heading h2', openingLine: '.studio-script p', effort: '.studio-heading .meta-row' },
  D: { title: '.cue-title', openingLine: '.cue-main blockquote', effort: '.cue-task .meta-row' },
};

const assertReadyGeometry = async (browser: { evaluate: Function }, variant: string) => {
  const geometry = await browser.evaluate((selectors: { title: string; openingLine: string; effort: string }) => {
    const bounds = (selector: string) => {
      const node = document.querySelector(selector);
      if (!node) return null;
      const rect = node.getBoundingClientRect();
      return { left: rect.left, right: rect.right, top: rect.top, bottom: rect.bottom, width: rect.width, height: rect.height };
    };
    const phone = bounds('#phone');
    const appScroll = bounds('#app .app-scroll');
    const cta = bounds('#app .stage-dock .primary');
    const title = bounds(selectors.title);
    const openingLine = bounds(selectors.openingLine);
    const effort = bounds(selectors.effort);
    const contains = (outer: ReturnType<typeof bounds>, inner: ReturnType<typeof bounds>) => Boolean(
      outer && inner && inner.left >= outer.left && inner.right <= outer.right && inner.top >= outer.top && inner.bottom <= outer.bottom,
    );
    const windowBounds = { left: 0, right: window.innerWidth, top: 0, bottom: window.innerHeight };
    return {
      ctaInsidePhone: contains(phone, cta),
      ctaInsideViewport: contains(windowBounds, cta),
      titleVisibleWithoutScroll: contains(appScroll, title),
      openingLineVisibleWithoutScroll: contains(appScroll, openingLine),
      effortVisibleWithoutScroll: contains(appScroll, effort),
      selectorsPresent: Boolean(phone && appScroll && cta && title && openingLine && effort),
      phone,
      appScroll,
      cta,
      title,
      openingLine,
      effort,
    };
  }, readyContentSelectors[variant]);

  expect(geometry.selectorsPresent).toBe(true);
  expect(geometry.ctaInsidePhone).toBe(true);
  expect(geometry.ctaInsideViewport).toBe(true);
  expect(geometry.titleVisibleWithoutScroll).toBe(true);
  expect(geometry.openingLineVisibleWithoutScroll).toBe(true);
  expect(geometry.effortVisibleWithoutScroll).toBe(true);
};

const openVariant = async (app: App, variant: string) => {
  await app.open(`/index.html?variant=${variant}`);
};

const openOnboarding = async (screen: Screen) => {
  await screen.getByRole('button', 'Onboarding').tap();
  await expect(screen.getByRole('button', 'Sign in with Apple')).toBeVisible();
};

const openSetup = async (screen: Screen) => {
  await screen.getByRole('button', 'Sign in with Apple').tap();
  await expect(screen.getByRole('heading', 'What do you love sharing?')).toBeVisible();
};

for (const [variant, filmingCta] of variants) {
  test(`variant ${variant} onboarding reaches a ready idea`, { tags: ['onboarding'] }, async ({ app, screen, browser }) => {
    await openVariant(app, variant);
    await openOnboarding(screen);
    await app.screenshot(`variant-${variant}-welcome`);

    await openSetup(screen);
    await screen.getByRole('button', 'Books').tap();
    await app.screenshot(`variant-${variant}-setup`);

    await screen.getByRole('button', 'Show my first idea').tap();
    await expect(screen.getByRole('heading', 'The book I almost put down')).toBeVisible({ timeout: 10_000 });
    await expect(screen.getByRole('button', filmingCta)).toBeVisible();
    await assertReadyGeometry(browser, variant);
    if (variant === 'A') {
      const viewport = await browser.evaluate(() => ({
        clientWidth: document.documentElement.clientWidth,
        scrollWidth: document.documentElement.scrollWidth,
      }));
      expect(viewport.scrollWidth).toBeLessThanOrEqual(viewport.clientWidth);
    }
    await app.screenshot(`variant-${variant}-ready`);
  });
}

test('skipping optional setup produces a usable routine idea', { tags: ['onboarding'] }, async ({ app, screen }) => {
  await openVariant(app, 'A');
  await openOnboarding(screen);
  await openSetup(screen);
  await screen.getByRole('button', 'Set up later').tap();

  await expect(screen.getByRole('heading', 'The little pause that resets my day')).toBeVisible({ timeout: 10_000 });
  await expect(screen.getByRole('button', 'Start filming')).toBeVisible();
  await app.screenshot('skip-setup-routine-ready');
});

test('three shots support caption editing, posting, undo, and recent history', { tags: ['daily-flow'] }, async ({ app, screen, browser }) => {
  const editedCaption = 'Edited caption from the deterministic e2e flow.';
  await openVariant(app, 'A');
  await expect(screen.getByRole('button', 'Start filming')).toBeVisible();
  await screen.getByRole('button', 'Start filming').tap();
  await expect(screen.getByRole('heading', 'Shot 1 of 3')).toBeVisible();

  await screen.getByRole('button', 'Shot done · next shot').tap();
  await expect(screen.getByRole('heading', 'Shot 2 of 3')).toBeVisible();
  await screen.getByRole('button', 'Shot done · next shot').tap();
  await expect(screen.getByRole('heading', 'Shot 3 of 3')).toBeVisible();
  await screen.getByRole('button', 'Shot done · get post text').tap();
  await expect(screen.getByRole('heading', 'Ready to post')).toBeVisible();

  await screen.getByRole('button', 'Edit caption').tap();
  await expect(screen.getByRole('heading', 'Your words, your way')).toBeVisible();
  await screen.getByLabel('Caption').fill(editedCaption);
  await screen.getByRole('button', 'Save caption').tap();
  await expect(browser.locator('#app .copy-card').getByText(editedCaption)).toBeVisible();

  await screen.getByRole('button', 'Edit caption').tap();
  await screen.getByLabel('Caption').fill('Temporary unsaved caption.');
  await screen.getByRole('button', 'Close sheet').tap();
  await expect(browser.locator('#app .copy-card').getByText(editedCaption)).toBeVisible();
  await expect(screen.getByText('Temporary unsaved caption.')).not.toBeVisible();

  await screen.getByRole('button', 'Preview').tap();
  await expect(screen.getByRole('heading', 'Instagram preview')).toBeVisible();
  await expect(browser.locator('.social-copy').getByText(editedCaption)).toBeVisible();
  await screen.getByRole('button', 'Back to the caption').tap();

  await screen.getByRole('button', 'I’ve posted this').tap();
  await expect(browser.locator('#app .success-content').getByText('Today · Posted')).toBeVisible();
  await screen.getByRole('button', 'Undo posted status').tap();
  await expect(screen.getByRole('heading', 'Ready to post')).toBeVisible();
  await screen.getByRole('button', 'I’ve posted this').tap();
  await expect(browser.locator('#app .success-content').getByText('Today · Posted')).toBeVisible();

  await screen.getByRole('button', 'You').tap();
  await expect(screen.getByRole('heading', 'You')).toBeVisible();
  await app.screenshot('you-after-posted');
  await screen.getByRole('button', /Recent posts/).tap();
  await expect(screen.getByRole('heading', 'Your recent posts')).toBeVisible();
  await screen.getByRole('button', /The book I almost put down/).tap();
  await expect(screen.getByRole('heading', 'A post to keep')).toBeVisible();
  await expect(browser.locator('#sheet .instruction-block').getByText(editedCaption)).toBeVisible();
});

test('plan saves tomorrow, preserves a collision, and prepares an empty future day', { tags: ['plan'] }, async ({ app, screen }) => {
  await openVariant(app, 'A');
  await screen.getByRole('button', 'Save for later').tap();
  await expect(screen.getByRole('heading', 'Leave an idea ready')).toBeVisible();
  await screen.getByRole('button', /^Tomorrow · 3 October/).tap();
  await screen.getByRole('button', /Save for tomorrow/i).tap();
  await expect(screen.getByRole('heading', 'Room for another day.')).toBeVisible();

  await screen.getByRole('button', 'Find a lighter idea for today').tap();
  await screen.getByRole('button', /^A different Reel/).tap();
  await expect(screen.getByRole('heading', 'The little pause that resets my day')).toBeVisible();
  await screen.getByRole('button', 'Save for later').tap();
  await screen.getByRole('button', /^Tomorrow · 3 October/).tap();
  await expect(screen.getByText('This day already has an idea. Choose another day to keep both.')).toBeVisible();
  await screen.getByRole('button', 'Close sheet').tap();

  await screen.getByRole('button', 'Weekly plan').tap();
  await expect(screen.getByRole('heading', 'Plan')).toBeVisible();
  await screen.getByRole('button', /^Sat 3 October/).tap();
  await expect(screen.getByRole('button', /^Sat 3 October/)).toHaveAttribute('aria-pressed', 'true');
  await expect(screen.getByRole('heading', 'The book I almost put down')).toBeVisible();
  await app.screenshot('plan-tomorrow-saved');

  await screen.getByRole('button', /^Sun 4 October/).tap();
  await expect(screen.getByRole('heading', 'A little room for inspiration.')).toBeVisible();
  await screen.getByRole('button', 'Prepare an idea for this day').tap();
  await expect(screen.getByRole('heading', 'The book I almost put down')).toBeVisible();
  await app.screenshot('plan-future-day-prepared');
});

test('preferences shape the next prepared photo idea and references can be removed', { tags: ['preferences'] }, async ({ app, screen }) => {
  await openVariant(app, 'A');
  await screen.getByRole('button', 'Creator profile').tap();
  await expect(screen.getByRole('heading', 'You')).toBeVisible();
  await app.screenshot('you-preferences');

  await screen.getByRole('button', /Interests & style/).tap();
  await screen.getByRole('button', 'Books').tap();
  await screen.getByRole('button', 'Food').tap();
  await screen.getByRole('button', 'Save preferences').tap();

  await screen.getByRole('button', /Content preferences/).tap();
  await screen.getByRole('button', /^5 minutes/).tap();
  await screen.getByRole('button', /^No talking/).tap();
  await screen.getByRole('button', /^Photo post/).tap();
  await screen.getByRole('button', 'Save preferences').tap();

  await screen.getByRole('button', 'Daily idea').tap();
  await screen.getByRole('button', 'No idea yet').tap();
  await screen.getByRole('button', 'Prepare today’s idea').tap();
  await expect(screen.getByRole('heading', 'A small thought about food')).toBeVisible({ timeout: 10_000 });
  await expect(screen.getByText('Photo post')).toBeVisible();
  await expect(screen.getByText('No filming')).toBeVisible();

  await screen.getByRole('button', 'Creator profile').tap();
  await screen.getByRole('button', /References/).tap();
  await screen.getByLabel('A name to remember it by').fill('A creator I like');
  await screen.getByLabel('Post or profile link').fill('https://example.com/creator');
  await screen.getByRole('button', 'Add inspiration').tap();
  await expect(screen.getByRole('button', 'Remove A creator I like')).toBeVisible();
  await screen.getByRole('button', 'Remove A creator I like').tap();
  await expect(screen.getByText('A little collection starts here.')).toBeVisible();
});

test('idea retry recovers to a ready idea', { tags: ['retry'] }, async ({ app, screen }) => {
  await openVariant(app, 'A');
  await screen.getByRole('button', 'Idea retry').tap();
  await expect(screen.getByRole('heading', 'Your idea needs another moment.')).toBeVisible();
  await screen.getByRole('button', 'Try again').tap();
  await expect(screen.getByRole('heading', 'The book I almost put down')).toBeVisible({ timeout: 10_000 });
  await app.screenshot('idea-retry-recovered');
});

test('Tailscale preview renders the current onboarding route', { tags: ['tailscale'] }, async ({ app, screen, browser }) => {
  await app.open('https://macbook.taile5de76.ts.net/contenthelper/index.html?variant=A');
  await expect(screen.getByRole('button', 'Onboarding')).toBeVisible({ timeout: 15_000 });
  const blockedPaths = await browser.evaluate(async (paths: string[]) => Promise.all(paths.map(async (path) => {
    const response = await fetch(path, { cache: 'no-store' });
    return { path, status: response.status };
  })), ['/contenthelper/package.json', '/contenthelper/node_modules/e2e/package.json', '/contenthelper/.e2e/report.json']);
  expect(blockedPaths).toEqual([
    { path: '/contenthelper/package.json', status: 404 },
    { path: '/contenthelper/node_modules/e2e/package.json', status: 404 },
    { path: '/contenthelper/.e2e/report.json', status: 404 },
  ]);
  await screen.getByRole('button', 'Onboarding').tap();
  await expect(screen.getByRole('button', 'Sign in with Apple')).toBeVisible();
  await app.screenshot('tailscale-onboarding');
});

test('desktop visual review captures comparison and all welcomes', { tags: ['visual'] }, async ({ app, screen }) => {
  await openVariant(app, 'A');
  await screen.getByRole('button', 'Compare all four').tap();
  await expect(screen.getByRole('heading', 'One idea. Four ways to start.')).toBeVisible();
  await app.screenshot('desktop-comparison');

  await screen.getByRole('button', /Back to interactive preview/).tap();
  await screen.getByRole('button', 'Onboarding').tap();
  await expect(screen.getByRole('button', 'Sign in with Apple')).toBeVisible();
  await app.screenshot('desktop-welcome-A');

  for (const [variant, label] of [['B', 'B Daybook'], ['C', 'C Studio'], ['D', 'D Cue']] as const) {
    await screen.getByRole('button', label).tap();
    await expect(screen.getByRole('button', 'Sign in with Apple')).toBeVisible();
    await app.screenshot(`desktop-welcome-${variant}`);
  }
});
