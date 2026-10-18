import type { E2EConfig } from 'e2e';
import { web } from '@e2e-dev/web';

const previewUrl = process.env.CONTENTHELPER_PREVIEW_URL ?? 'http://127.0.0.1:8766';

export default {
  tests: 'tests/**/*.e2e.ts',
  targets: [{
    name: 'contenthelper-static',
    engine: web({
      browser: 'chromium',
      viewport: { width: 390, height: 844 },
    }),
    // The LaunchAgent already serves this preview on loopback port 8766.
    // Keep command unset so e2e does not start a second server.
    app: { url: previewUrl },
  }, {
    name: 'contenthelper-desktop',
    engine: web({
      browser: 'chromium',
      viewport: { width: 1440, height: 1100 },
    }),
    app: { url: previewUrl },
  }],
  output: '.e2e',
  retries: 0,
  workers: 1,
} satisfies E2EConfig;
