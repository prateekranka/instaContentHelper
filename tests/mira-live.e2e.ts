import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { scrollToControl, tapVisibleControl } from './mobile-support';

test('One live Make today’s Reel request returns three cards', async ({ app, screen, device }) => {
  if (process.env.MIRA_E2E_INSTALL === '1') await device.installApp();
  await app.open();

  const signIn = screen.getByTestId('sign-in.welcome');
  if (await signIn.isVisible()) {
    await app.screenshot('live-needs-sign-in');
    test.skip('live: needs Bobby to sign in');
  }

  const today = screen.getByRole('tablist', 'Tab Bar', { exact: true })
    .getByRole('button', 'Today', { exact: true });
  await today.tap();
  const back = screen.getByTestId('BackButton');
  for (let step = 0; step < 4 && await back.isVisible(); step += 1) await back.tap();
  await screen.getByRole('button', 'Profile', { exact: true }).tap();

  const account = screen.getByText(/^(Account connected|Connect account)$/);
  await scrollToControl(screen, account);
  const connected = screen.getByText('Account connected', { exact: true });
  if (!await connected.isVisible()) {
    await tapVisibleControl(screen, screen.getByText('Connect account', { exact: true }));
    await expect(signIn).toBeVisible();
    await app.screenshot('live-needs-sign-in');
    test.skip('live: needs Bobby to sign in');
  }

  await app.screenshot('live-account-connected');
  await screen.getByRole('button', 'Done', { exact: true }).tap();
  const make = screen.getByTestId('mira.today.make');
  await expect(make).toBeVisible();
  await app.screenshot('live-before-request');
  const deadline = Date.now() + 240_000;
  await make.tap();
  await app.screenshot('live-request-submitted');

  const permission = screen.getByText(
    /^(AI (data )?permission|Use AI to write your ideas\?)$|^Allow AI to write ideas first\./,
    { visible: true },
  );
  const cardStates = screen.getByRole('button', /^Idea [1-3] of 3, /);
  const alert = screen.getByRole('alert', 'Mira', { exact: true });
  let previous = '';
  let stateNumber = 0;
  const result = async () => {
    if (await permission.count() > 0) {
      await app.screenshot('live-ai-permission-required');
      return 'AI data permission required';
    }
    const states = await cardStates.allTextContents();
    const readyCards = states.flatMap(state => {
      const card = /^Idea ([1-3]) of 3, ready$/.exec(state);
      return card ? [card[1]] : [];
    });
    if (states.join('|') !== previous) {
      previous = states.join('|');
      const ready = readyCards.length ? `-ready-${readyCards.join('-')}` : '';
      await app.screenshot(`live-card-state-${++stateNumber}${ready}`);
    }
    if (readyCards.length === 3) return 'ready';
    if (states.some(state => /, (did not load|needs an update)$/.test(state))) return 'card failure';
    if (await alert.isVisible()) return 'app error';
    return 'waiting';
  };
  let outcome = 'waiting';
  await expect.poll(async () => {
    outcome = await result();
    return outcome !== 'waiting';
  }, { timeout: Math.max(1, deadline - Date.now()), interval: 4_000 }).toBe(true);
  expect(outcome).toBe('ready');

  for (let card = 1; card <= 3; card += 1) {
    await screen.getByRole('button', `Idea ${card} of 3, ready`, { exact: true }).tap();
    await expect(screen.getByText(`${card} of 3`, { exact: true })).toBeVisible();
    await app.screenshot(`live-card-${card}-ready`);
  }
});
