import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

test('Install the signed E4 build over the existing Mira app', async ({ device }) => {
  const appPath = process.env.MIRA_E2E_APP;
  if (!appPath) throw new Error('Set MIRA_E2E_APP to the signed E4 build.');
  const installed = await device.installApp(appPath, { reinstall: false });
  expect(installed.bundleId ?? installed.app).toBe('com.prateekranka.creatorcontenthelper');
});
