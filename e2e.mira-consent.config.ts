import type { E2EConfig } from 'e2e';
import { resolve } from 'node:path';
import fixture, { launchArguments } from './e2e.mira.config';

export default {
  ...fixture,
  tests: 'tests/mira-consent.e2e.ts',
  targets: fixture.targets.map(target => ({
    ...target,
    name: 'mira-consent-ios',
    app: { bundleId: target.app.bundleId, launchArguments },
  })),
  video: 'off',
  output: process.env.MIRA_E2E_OUTPUT ?? resolve('work/evidence/t1b-phone/consent-ui'),
} satisfies E2EConfig;
