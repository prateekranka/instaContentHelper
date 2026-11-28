import { test, type Device } from '@e2e-dev/mobile';
import { expect, type Screen } from 'e2e';
import { passiveLaunchArguments as launchArguments } from '../e2e.mira.config';
import { scrollToControl, waitForMobileApp } from './mobile-support';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';

async function openConsentStatus(screen: Screen, device: Device, override?: 'unknown' | 'allowed' | 'declined' | 'out-of-date') {
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: override ? [...launchArguments, '-MCO_AI_CONSENT_OVERRIDE', override] : launchArguments,
  });
  await waitForMobileApp(screen);
  const tabs = screen.getByRole('tablist', 'Tab Bar', { exact: true });
  await expect(tabs).toBeAttached({ timeout: 45_000 });
  const alert = screen.getByRole('alert', /Apple.Account Verification/);
  if (await alert.count() > 0) await alert.getByRole('button', 'Not Now', { exact: true }).tap();
  const today = tabs.getByRole('tab', 'Home', { exact: true });
  await (await today.count() ? today : tabs.getByRole('button', 'Home', { exact: true })).tap();
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
  await scrollToControl(screen, screen.getByText(/^(Account connected|Connect account)$/));
  await expect(screen.getByText('Account connected', { exact: true })).toBeVisible();
}

test('Saved AI permission is allowed on a normal launch', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device);
  const allowed = screen.getByText('Allowed', { exact: true });
  await scrollToControl(screen, allowed);
  await expect(allowed).toBeVisible();
  await app.screenshot('profile-ai-permission-allowed');
});

for (const override of ['unknown', 'allowed', 'declined', 'out-of-date'] as const) {
  test(`M15 live Profile uses saved consent with the debug ${override} override`, async ({ app, screen, device }) => {
    await openConsentStatus(screen, device, override);
    const allowed = screen.getByText('Allowed', { exact: true });
    await scrollToControl(screen, allowed);
    await expect(allowed).toBeVisible();
    await app.screenshot(`live-permission-ignores-${override}-override`);
  });
}
