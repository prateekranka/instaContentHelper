import type { E2EConfig } from 'e2e';
import { mobile } from '@e2e-dev/mobile';
import { resolve } from 'node:path';

const scenario = process.env.POCKET_E2E_SCENARIO ?? 'ready';
const evidence = resolve('work/pocket-native-build/20261002T181853Z.kT7Urb');
const fixtureSession = process.env.POCKET_E2E_SESSION ?? `pocket-${scenario}-${Date.now()}`;
// Keep the same fixture namespace in the runner and its test worker on relaunch.
process.env.POCKET_E2E_SESSION = fixtureSession;
const flags: Record<string, string> = {
  MCO_FORCE_FIXTURE_UI: '1',
  MCO_LEGACY_POCKET_UI: '1',
  MCO_FORCE_APP_MODE: 'creator',
  MCO_QA_SESSION: fixtureSession,
};
if (!['welcome', 'empty'].includes(scenario)) {
  flags.MCO_FORCE_ONBOARDING = '1';
  flags.MCO_FORCE_EMPTY_TODAY = '1';
}
if (scenario === 'retry') flags.MCO_FAIL_FIRST_IDEA_ONCE = '1';
if (scenario === 'slow') flags.MCO_SLOW_FIRST_IDEA = '1';
if (scenario === 'empty') flags.MCO_FORCE_EMPTY_TODAY = '1';
if (scenario === 'long') flags.MCO_LONG_CONTENT = '1';
if (scenario === 'large') flags.MCO_DYNAMIC_TYPE_ACCESSIBILITY5 = '1';
if (scenario === 'motion') flags.MCO_REDUCED_MOTION = '1';
if (scenario === 'sync-error') flags.MCO_FAIL_TODAY_DECISION_SYNC_ONCE = '1';
if (scenario === 'welcome') flags.MCO_FORCE_SIGN_IN = '1';

const suite = ['onboarding', 'retry', 'slow'].includes(scenario) ? 'onboarding'
  : ['large', 'long', 'motion', 'empty', 'welcome'].includes(scenario) ? 'accessibility'
  : scenario === 'plan' ? 'plan' : scenario === 'alternatives' ? 'alternatives' : 'today';

// Deterministic native tests. No AI model, provider, account credentials, or live generation.
export default {
  tests: `tests/pocket-${suite}.e2e.ts`,
  targets: [{
    name: 'contenthelper-ios',
    engine: mobile({
      platform: 'ios',
      device: process.env.POCKET_E2E_DEVICE ?? '7AEFF457-CBA5-4485-A13D-896E75169E07',
      session: 'contenthelper-pocket',
      snapshot: 'full',
      transition: 600,
      videoTouches: false,
    }),
    app: {
      bundleId: 'com.prateekranka.creatorcontenthelper',
      ...(process.env.POCKET_E2E_INSTALL === '1' ? {
        appPath: process.env.POCKET_E2E_APP ?? resolve(evidence, 'DerivedData/Build/Products/Debug-iphonesimulator/ContentHelper.app'),
      } : {}),
      launchArguments: ['-AppleLanguages', '(en)', '-AppleLocale', 'en_US',
        ...Object.entries(flags).flatMap(([key, value]) => [`-${key}`, value])],
    },
  }],
  workers: 1,
  retries: 0,
  timeout: 240_000,
  actionTimeout: 25_000,
  assertionTimeout: 20_000,
  cleanupTimeout: 45_000,
  // Bind the exact device by installing first; record subsequent behavior runs.
  video: process.env.POCKET_E2E_INSTALL === '1' ? 'off' : 'on',
  output: process.env.POCKET_E2E_OUTPUT ?? resolve(evidence, `e2e-${scenario}`),
} satisfies E2EConfig;
