import type { E2EConfig } from 'e2e';
import {web} from '@e2e-dev/web';
export default {
 tests:'tests/**/*.e2e.ts',
 targets:[{name:'tracker',engine:web(),app:{url:process.env.TRACKER_URL ?? 'http://127.0.0.1:3000'}}],
 workers:1,retries:0,timeout:60000,actionTimeout:5000,trace:'on',
 output:'work/e2e',
} satisfies E2EConfig;
