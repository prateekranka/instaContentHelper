import type { E2EConfig } from 'e2e';
import fixture from './e2e.mira.config';

export default {
  ...fixture,
  tests: 'tests/mira-e2-keep.e2e.ts',
  targets: fixture.targets.map(target => ({
    ...target,
    name: 'mira-profile-ios',
    app: { bundleId: target.app.bundleId },
  })),
  video: 'off',
} satisfies E2EConfig;
