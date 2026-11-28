import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { scrollToControl, tapVisibleControl } from './mobile-support';

test('Normal launch preserves AI permission and the connected Instagram account', async ({ app, screen, device }) => {
  await device.openApp('com.prateekranka.creatorcontenthelper', {
    relaunch: true, launchArguments: ['-MCO_QA_DISABLE_DAILY_NOTE', '1'],
  });
  await expect(screen.getByRole('tablist', 'Tab Bar', { exact: true })).toBeAttached({ timeout: 45_000 });
  const alert = screen.getByRole('alert', /Apple.Account Verification/);
  if (await alert.count() > 0) {
    await alert.getByRole('button', 'Not Now', { exact: true }).tap();
  }
  const tabs = screen.getByRole('tablist', 'Tab Bar', { exact: true });
  const controls = [
    tabs.getByRole('tab', 'Home', { exact: true }), tabs.getByRole('button', 'Home', { exact: true }),
    tabs.getByRole('tab', 'Today', { exact: true }), tabs.getByRole('button', 'Today', { exact: true }),
  ];
  for (const control of controls) {
    if (await control.count()) {
      await control.tap();
      break;
    }
  }
  const profile = screen.getByRole('button', 'Profile', { exact: true });
  const back = screen.getByTestId('BackButton');
  for (let step = 0; step < 4 && !await profile.isVisible() && await back.isVisible(); step += 1) {
    try {
      await back.tap({ timeout: 3_000 });
    } catch (error) {
      if (!(error instanceof Error && 'code' in error && error.code === 'LOCATOR_NOT_FOUND')
        || !await profile.isVisible()) throw error;
    }
  }
  await profile.tap();
  const status = screen.getByText(/^(Allowed|Not decided yet|Not allowed yet|Review needed|Connect account)$/);
  await scrollToControl(screen, status);
  await app.screenshot('profile-ai-permission');
  const allowed = await screen.getByText('Allowed', { exact: true, visible: true }).count();
  expect(allowed).toBe(1);
  const insights = screen.getByTestId('mira.profile.insights');
  await scrollToControl(screen, insights, 'up');
  await app.screenshot('profile-instagram-insights');
  await tapVisibleControl(screen, insights);
  const handle = screen.getByText(/^@prateekranka\b/);
  await expect(handle).toBeVisible({ timeout: 30_000 }).catch(async error => {
    await app.screenshot('instagram-insights-unverified');
    throw error;
  });
  const followers = screen.getByText(/^Followers(?:,|$)/).first();
  await scrollToControl(screen, followers, 'up');
  await expect(followers).toBeVisible();
  const value = await followers.textContent();
  if (!/\d/.test(value ?? '')) {
    await expect(screen.getByText(/^\d[\d,.]*[KMB]?$/).first()).toBeVisible();
  }
  await app.screenshot('instagram-live-numbers');
  await scrollToControl(screen, handle);
  await app.screenshot('instagram-connected-prateekranka');
  await expect(screen.getByText('Sample data', { exact: true })).not.toBeVisible();
});
