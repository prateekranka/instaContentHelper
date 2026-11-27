import { test, type Device } from '@e2e-dev/mobile';
import { expect, type Screen } from 'e2e';
import { launchArguments } from '../e2e.mira.config';
import { scrollToControl, tapVisibleControl } from './mobile-support';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';

async function openConsentStatus(screen: Screen, device: Device, override?: 'unknown' | 'declined') {
  await device.openApp(bundleId, {
    relaunch: true,
    launchArguments: override ? [...launchArguments, '-MCO_AI_CONSENT_OVERRIDE', override] : launchArguments,
  });
  const today = screen.getByRole('tablist', 'Tab Bar', { exact: true })
    .getByRole('button', 'Today', { exact: true });
  await today.tap();
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
  await tapVisibleControl(screen, screen.getByTestId('mira.today.make'));
}

test('Undecided AI permission opens the question from Today', async ({ app, screen, device }) => {
  await openConsentStatus(screen, device, 'unknown');
  await tapMake(screen, 'Not decided yet');
  await expect(screen.getByText('AI data permission', { exact: true })).toBeVisible();
  await app.screenshot('ai-permission-question');
});

test('Declined AI permission shows a message and opens review from Today', async ({ app, screen, device }) => {
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
