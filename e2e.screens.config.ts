import base from './e2e.config';
import { resolve } from 'node:path';
import { copyFile, mkdir, readFile, writeFile } from 'node:fs/promises';
import type { E2EConfig, Reporter } from 'e2e';
import { defineEngine } from 'e2e/engine';

// Reuse the mobile engine's public observation API. One tree capture retains
// hierarchy and geometry without hundreds of individual locator reads.
const targets = base.targets.map(target => {
  const mobileEngine = target.engine!;
  const { capabilities: _capabilities, ...spec } = mobileEngine;
  return {
    ...target,
    engine: defineEngine({
      ...spec,
      version: `${mobileEngine.version}+screen-catalog.1`,
      fixtures: {
        ...mobileEngine.fixtures,
        catalogSnapshot: context => context.fixture('catalogSnapshot', {
          read: () => mobileEngine.observe!(context.operation()),
        }, { read: { kind: 'resource' } }),
      },
    }),
  };
});

const catalog: Reporter = {
  name: 'screen-catalog',
  async onRunFinished(run) {
    if (!run.reportPath) return;
    const output = resolve(run.reportPath!, '..');
    const entries = [];
    await mkdir(resolve(output, 'screen-layouts'), { recursive: true });
    const screenshotDirectory = resolve(output, 'screenshots');
    await mkdir(screenshotDirectory, { recursive: true });
    const diagnosticDirectory = resolve(output, 'diagnostics');
    await mkdir(diagnosticDirectory, { recursive: true });
    for (const result of run.report.run.results) {
      for (const attempt of result.attempts) {
        for (const artifact of attempt.artifacts) {
          if (!artifact.path) continue;
          const sourceTest = result.titlePath?.at(-1) ?? result.testId;
          const testSlug = String(sourceTest).toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '').slice(0, 52) || 'test';
          const artifactName = artifact.path.split('/').at(-1)!;
          if (artifact.kind === 'log' && artifact.path.includes('/failure/')) {
            const diagnosticName = `${testSlug}-attempt-${attempt.index}-${artifactName}`;
            await copyFile(resolve(run.artifactsRoot, artifact.path), resolve(diagnosticDirectory, diagnosticName));
            continue;
          }
          if (artifact.kind !== 'screenshot' || !artifact.path.includes('/screenshots/')) continue;
          const name = artifactName.replace(/^\d+-/, '').replace(/\.png$/, '');
          const captureId = `${testSlug}-attempt-${attempt.index}-${artifactName.replace(/\.png$/, '')}`;
          const screenshot = resolve(run.artifactsRoot, artifact.path);
          const png = await readFile(screenshot);
          const durableScreenshot = resolve(screenshotDirectory, `${captureId}.png`);
          await copyFile(screenshot, durableScreenshot);
          const layoutPath = resolve(output, 'screen-layouts', `${name}.json`);
          let layout: Record<string, unknown> = {};
          try { layout = JSON.parse(await readFile(layoutPath, 'utf8')); }
          catch (error) { if ((error as NodeJS.ErrnoException).code !== 'ENOENT') throw error; }
          if (!Array.isArray(layout.elements) || !layout.viewport) continue;
          const entry = { ...layout, name: `${sourceTest} · ${name}`, screenName: name,
            captureId, sourceTest, screenshot: durableScreenshot, pixelWidth: png.readUInt32BE(16),
            pixelHeight: png.readUInt32BE(20), sha256: artifact.sha256, testStatus: result.status };
          await writeFile(resolve(output, 'screen-layouts', `${captureId}.json`), JSON.stringify(entry, null, 2));
          entries.push(entry);
        }
      }
    }
    await writeFile(resolve(output, 'screen-catalog.json'), JSON.stringify(entries, null, 2));
  },
};

// Separate catalog runs so the existing regression suites and evidence stay intact.
export default {
  ...base,
  targets,
  tests: 'tests/pocket-screens.e2e.ts',
  timeout: 600_000,
  output: process.env.POCKET_E2E_OUTPUT ?? resolve('work/evidence/pocket-screens'),
  // Each test captures its own e2e screenshot at every named UI state. The
  // device-wide video recorder cannot inherit the engine's pinned UDID when
  // other simulators are booted, so leave this screenshot catalog video-free.
  video: 'off',
  reporters: ['list', catalog],
} satisfies E2EConfig;
