import { mobile } from '@e2e-dev/mobile';
import type { E2EConfig } from 'e2e';
import { resolve } from 'node:path';
import { launchArguments } from './e2e.mira.config';

export default {
  tests: 'tests/mira-live-journey.e2e.ts',
  targets: [{
    name: 'mira-live-journey-ios',
    engine: mobile({
      platform: 'ios',
      device: 'Bobby’s',
      session: process.env.MIRA_E2E_DRIVER_SESSION ?? 'mira-live-journey-2',
      snapshot: 'full',
      videoTouches: false,
    }),
    app: {
      bundleId: 'com.prateekranka.creatorcontenthelper',
      launchArguments,
    },
  }],
  workers: 1,
  retries: 0,
  timeout: 600_000,
  actionTimeout: 10_000,
  assertionTimeout: 15_000,
  cleanupTimeout: 45_000,
  video: 'off',
  output: process.env.MIRA_E2E_OUTPUT ?? resolve('work/evidence/mira-live-journey'),
} satisfies E2EConfig;
