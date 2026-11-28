import { test, type Device } from '@e2e-dev/mobile';
import { expect, type Screen } from 'e2e';
import { launchArguments } from '../e2e.mira.config';
import { scrollToControl, tapVisibleControl, waitForMobileApp } from './mobile-support';

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

async function tapMake(screen: Screen, expectedStatus: string) {
  const status = screen.getByText(expectedStatus, { exact: true });
  await scrollToControl(screen, status);
  await expect(status).toBeVisible();
  await screen.getByRole('button', 'Done', { exact: true }).tap();
  const make = screen.getByTestId('mira.today.make');
  if (await make.count()) {
    await tapVisibleControl(screen, make);
  } else {
    await screen.getByTestId('mira.ask.bar').fill('Film something at home');
    await screen.getByRole('button', 'Send to Mira', { exact: true }).tap();
  }
}

test('Undecided AI permission opens the question from Home', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device, 'unknown');
  await tapMake(screen, 'Not decided yet');
  await expect(screen.getByText('AI data permission', { exact: true })).toBeVisible();
  await app.screenshot('ai-permission-question');
});

test('Declined AI permission shows a message and opens review from Home', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device, 'declined');
  await tapMake(screen, 'Not allowed yet');
  const message = screen.getByTestId('mira.today.aiPermissionNeeded');
  const review = screen.getByRole('button', 'Review AI permission', { exact: true });
  await expect(message).toBeVisible();
  await expect(review).toBeVisible();
  await app.screenshot('ai-permission-needed');
  await tapVisibleControl(screen, review);
  await expect(screen.getByText('AI data permission', { exact: true })).toBeVisible();
  await app.screenshot('ai-permission-review');
});

test('Saved AI permission is allowed on a normal launch', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device);
  const allowed = screen.getByText('Allowed', { exact: true });
  await scrollToControl(screen, allowed);
  await expect(allowed).toBeVisible();
  await app.screenshot('profile-ai-permission-allowed');
});

test('S3 allowed override shows Allowed in Profile', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device, 'allowed');
  const allowed = screen.getByText('Allowed', { exact: true });
  await scrollToControl(screen, allowed);
  await expect(allowed).toBeVisible();
  await app.screenshot('consent-allowed-override');
});

test('S3 earlier permission requires review again', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device, 'out-of-date');
  await tapMake(screen, 'Review needed');
  await expect(screen.getByText('AI data permission', { exact: true })).toBeVisible();
  await app.screenshot('consent-out-of-date');
});
