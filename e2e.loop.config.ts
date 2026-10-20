import base from './e2e.config';
import type { E2EConfig } from 'e2e';

export default {
  ...base,
  tests: 'tests/pocket-loop.e2e.ts',
} satisfies E2EConfig;
