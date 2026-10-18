import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';

const scenario = process.env.POCKET_E2E_SCENARIO ?? 'onboarding';

test(`optional onboarding reaches Today (${scenario})`, { timeout: 180_000 }, async ({ app, screen }) => {
  await app.open();
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeVisible();
  const skip = await screen.getByTestId('onboarding.setUpLater').boundingBox();
  expect(skip.height).toBeGreaterThanOrEqual(44);
  await app.screenshot(`pocket-onboarding-${scenario}`);
  if (scenario === 'onboarding') {
    for (let i = 0; i < 4; i += 1) {
      await screen.getByTestId('onboarding.startingPoint.just_starting').tap();
      await expect(screen.getByTestId('onboarding.startingPoint.just_starting')).toBeSelected();
      await screen.getByTestId('onboarding.startingPoint.already_posting').tap();
      await expect(screen.getByTestId('onboarding.startingPoint.already_posting')).toBeSelected();
    }
    for (let i = 0; i < 4; i += 1) {
      await screen.getByTestId('onboarding.interest.books').tap();
      await expect(screen.getByTestId('onboarding.interest.books')).toBeSelected();
      await screen.getByTestId('onboarding.interest.books').tap();
      await expect(screen.getByTestId('onboarding.interest.books')).not.toBeSelected();
    }
    await screen.getByTestId('onboarding.interest.fitness-wellness').tap();
    await app.screenshot('pocket-onboarding-selections');
  }
  await screen.getByTestId(scenario === 'onboarding'
    ? 'onboarding.generateFirstDay' : 'onboarding.setUpLater').tap();
  if (scenario === 'retry') {
    await expect(screen.getByTestId('onboarding.retryFirstIdea')).toBeVisible();
    await app.screenshot('pocket-onboarding-retry');
    await screen.getByTestId('onboarding.retryFirstIdea').tap();
  }
  if (scenario === 'slow') {
    await expect(screen.getByTestId('onboarding.setUpLater')).toBeDisabled();
    await expect(screen.getByTestId('onboarding.generateFirstDay')).toBeDisabled();
  }
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByTestId('today.package.title')).toBeVisible();
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeHidden();
  await app.screenshot(`pocket-first-idea-${scenario}`);
});
