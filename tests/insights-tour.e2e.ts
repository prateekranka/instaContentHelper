import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { selectTab, scrollToControl, tapVisibleControl } from './pocket-support';

const BUNDLE = 'com.prateekranka.creatorcontenthelper';

async function openInsights(device: any, screen: any, scenario: string) {
  await device.openApp(BUNDLE, {
    relaunch: true,
    launchArguments: [
      '-AppleLanguages', '(en)', '-AppleLocale', 'en_US',
      '-MCO_FORCE_FIXTURE_UI', '1', '-MCO_FORCE_APP_MODE', 'creator',
      '-MCO_FORCE_ONBOARDING', '0', '-MCO_FORCE_EMPTY_TODAY', '0',
      '-MCO_LOOP_SCENARIO', 'ready', '-MCO_QA_SESSION', `ins-${scenario}`,
      '-MCO_INSIGHTS_SCENARIO', scenario,
    ],
  });
  await selectTab(screen, 'You');
  const row = screen.getByTestId('you.row.insights');
  await scrollToControl(screen, row);
  await tapVisibleControl(screen, row);
  await expect(screen.getByTestId('you.screen.insights')).toBeVisible();
}

test('insights surface states', { timeout: 300_000 }, async ({ app, screen, device }) => {
  for (const scenario of ['ready', 'sample', 'notconnected', 'permission'] as const) {
    await openInsights(device, screen, scenario);
    await app.screenshot(`insights-${scenario}`);
  }
});
