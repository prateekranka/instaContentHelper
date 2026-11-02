import { resolve } from 'node:path';
import type { E2EConfig } from 'e2e';
import base from './e2e.config';

export default {
  ...base,
  tests: 'tests/journey-tour.e2e.ts',
  output: resolve('work/tour'),
  video: 'off',
} satisfies E2EConfig;
