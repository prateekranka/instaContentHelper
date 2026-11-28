import { expect, type App, type Locator, type Screen } from 'e2e';
import { closeKeyboard, tapVisibleControl } from './mobile-support';

const questionLabels = [
  'What do you post about?',
  'Who watches your Reels?',
  'What do you want people to get from your Reels?',
  'What words or phrases sound like you?',
  'What do you never do in your Reels?',
  'What are your goals?',
];

export const interviewAnswers = [
  'I am 62. I post strength training and HYROX practice, including sled pushes and running.',
  'People over 50 who want to train for their first fitness event.',
  'I want them to see how to practise one movement at a time.',
  'I say start where you are and show your own pace.',
  'I do not make health promises or shame someone for needing a break.',
  'Share one simple HYROX practice Reel each week and show my progress.',
];

export async function answerBrandInterview(
  app: App, screen: Screen, submit: (next: Locator) => Promise<void>, checkDeniedSpeech = false,
) {
  const next = screen.getByTestId('mira.brand.next');
  const question = screen.getByTestId('mira.brand.question');
  const answer = screen.getByTestId('mira.brand.answer');
  await expect(question).toHaveText(questionLabels[0]);
  await expect(next).toBeDisabled();
  if (checkDeniedSpeech) {
    await screen.getByTestId('mira.brand.mic').tap();
    await expect(screen.getByText(
      'To use voice input, allow Speech Recognition and Microphone in Settings. You can still type.', { exact: true },
    )).toBeVisible();
    await expect(screen.getByTestId('mira.brand.mic')).toHaveAccessibleName('Open Settings');
    await app.screenshot('e2-interview-speech-denied');
  }

  for (const [index, value] of interviewAnswers.entries()) {
    await expect(question).toHaveText(questionLabels[index]);
    await expect(screen.getByTestId('mira.brand.questionNumber')).toHaveText(`Question ${index + 1} of 6`);
    if (checkDeniedSpeech && index === 1) {
      await tapVisibleControl(screen, screen.getByTestId('mira.brand.back'));
      await expect(question).toHaveText(questionLabels[0]);
      expect(await answer.inputValue()).toBe(interviewAnswers[0]);
      await tapVisibleControl(screen, next);
      await expect(question).toHaveText(questionLabels[index]);
    }
    await expect(next).toBeDisabled();
    await expect.poll(async () => (await answer.inputValue()) ?? '').toMatch(/^(?:Your answer)?$/);
    await answer.fill(value);
    await closeKeyboard(screen, answer);
    expect(await answer.inputValue()).toBe(value);
    if (index === 0) await app.screenshot('e2-interview');
    if (index === interviewAnswers.length - 1) await submit(next);
    else await tapVisibleControl(screen, next);
  }
}

export async function openLegacyIdeas(screen: Screen) {
  await screen.getByRole('button', 'Profile', { exact: true }).tap();
  await tapVisibleControl(screen, screen.getByTestId('mira.profile.stepByStep'));
  await screen.getByTestId('mira.project.compareIdeas').tap();
  await expect(screen.getByTestId('mira.today.make')).toBeVisible();
}

export async function openPickedShotList(app: App, screen: Screen) {
  const approve = screen.getByTestId('mira.words.approve');
  await expect(approve).toBeVisible();
  await expect(screen.getByTestId('mira.shots.film')).not.toBeAttached();
  await app.screenshot('e2-picked-words');
  await tapVisibleControl(screen, approve);
  await expect(screen.getByTestId('mira.shots.film')).toBeAttached({ timeout: 45_000 });
  await expect(screen.getByText('Your filming plan', { exact: true })).toBeAttached();
}
