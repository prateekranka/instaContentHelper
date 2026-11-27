import type { E2EConfig } from 'e2e';
import { resolve } from 'node:path';
import fixture, { launchArguments } from './e2e.mira.config';

export default {
  ...fixture,
  tests: 'tests/mira-live.e2e.ts',
  targets: fixture.targets.map(target => ({
    ...target,
    name: 'mira-live-ios',
    app: { ...target.app, launchArguments },
  })),
  output: process.env.MIRA_E2E_OUTPUT ?? resolve('work/evidence/t1b-phone/live'),
} satisfies E2EConfig;
