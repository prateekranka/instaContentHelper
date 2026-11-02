import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';
import { resolve } from 'node:path';

const bundleId = process.env.MIRA_E2E_BUNDLE ?? 'com.prateekranka.creatorcontenthelper.codexverify';
const install = process.env.MIRA_E2E_INSTALL === '1';

export default {
  tests: 'tests/mira-journey.e2e.ts',
  targets: [{
    name: 'mira-ios',
    engine: mobile({
      platform: 'ios',
      device: process.env.MIRA_E2E_DEVICE,
      session: 'mira-journey-verification',
      snapshot: 'full',
      videoTouches: false,
    }),
    app: {
      bundleId,
      ...(install ? { appPath: process.env.MIRA_E2E_APP } : {}),
      launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US', '-MCO_FORCE_FIXTURE_UI', '1'],
    },
  }],
  workers: 1,
  retries: 0,
  timeout: 420_000,
  actionTimeout: 25_000,
  assertionTimeout: 20_000,
  cleanupTimeout: 45_000,
  video: install ? 'off' : 'on',
  output: process.env.MIRA_E2E_OUTPUT ?? resolve('work/evidence/mira-journey'),
} satisfies E2EConfig;
