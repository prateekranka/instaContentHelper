import type { E2EConfig } from 'e2e';
import { resolve } from 'node:path';

export default {
  tests: 'tests/mira-provider-system.e2e.ts',
  targets: [{ name: 'mira-api', platform: 'api' }],
  workers: 1,
  retries: 0,
  timeout: 60_000,
  output: process.env.MIRA_API_E2E_OUTPUT ?? resolve('work/evidence/mira-api-e2e'),
} satisfies E2EConfig;
