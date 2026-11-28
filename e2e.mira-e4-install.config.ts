import type { E2EConfig } from 'e2e';
import keep from './e2e.mira-e2-keep.config';

export default { ...keep, tests: 'tests/mira-e4-install.e2e.ts' } satisfies E2EConfig;
