import { test } from '@e2e-dev/mobile';
import { expect, type Screen } from 'e2e';
import type { Device } from '@e2e-dev/mobile';
import {
  selectTab, tapEditorControl, tapVisibleControl, scrollToControl, clearThenType,
  dismissKeyboard, openLoopSession, relaunchLoopSession,
  openLoopEditor, saveLoopEditor, finishLoopFilming, openLoopPlanDay,
  requestLoopReplacement, approveLoopPackage,
} from './pocket-support';

async function ready(screen: Screen, device: Device, flags: Record<string, string> = {}) {
  const session = await openLoopSession(device, 'ready', flags);
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop ready package');
  return session;
}

async function editScript(screen: Screen, device: Device, transform: (script: string) => string) {
  await openLoopEditor(screen);
  await screen.getByRole('button', 'Script', { exact: true }).tap();
  const editor = screen.getByTestId('shootFolio.script.editor');
  await expect(editor).toBeVisible();
  const original = await editor.inputValue();
  await clearThenType(screen, editor, transform(original));
  await saveLoopEditor(screen, device);
  return original;
}

async function archiveHas(screen: Screen, title: string) {
  await selectTab(screen, 'You');
  await screen.scrollUntilVisible(screen.getByText(title, { exact: true }));
  await expect(screen.getByText(title, { exact: true })).toHaveCount(1);
}

async function copyPlanCaption(screen: Screen) {
  const tab = screen.getByTestId('plan.package.tab.caption');
  await scrollToControl(screen, tab, 'up');
  await tapVisibleControl(screen, tab);
  await expect(tab).toBeSelected();
  await tapVisibleControl(screen, screen.getByRole('button', 'Copy caption', { exact: true }));
}

test('loop R1-1: renaming a filmed scene keeps its mark after relaunch', async ({ app, screen, device }) => {
  const session = await ready(screen, device);
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('shoot.complete').tap();
  await expect(screen.getByTestId('shoot.complete')).toBeDisabled();
  await app.back();
  await openLoopEditor(screen);
  await clearThenType(screen, screen.getByTestId('shootFolio.scene.1.title'), 'Renamed opening scene');
  await saveLoopEditor(screen, device);
  await app.back();
  await relaunchLoopSession(device, session);
  await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 2 of');
  await screen.getByTestId('shoot.previous').tap();
  await expect(screen.getByText('Renamed opening scene', { exact: true })).toBeVisible();
  await expect(screen.getByTestId('shoot.complete')).toBeDisabled();
});

for (const decision of ['shot', 'posted'] as const) {
  test(`loop R1-2: easier backups stay hidden after ${decision}`, { timeout: 240_000 }, async ({ app, screen, device }) => {
    const session = await ready(screen, device);
    await finishLoopFilming(screen);
    if (decision === 'posted') {
      await screen.getByTestId('post.markPosted').tap();
      await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
    }
    await app.back();
    await expect(screen.getByTestId('today.notEasier')).toBeHidden();
    await relaunchLoopSession(device, session, { MCO_DYNAMIC_TYPE_ACCESSIBILITY5: '1' });
    await expect(screen.getByTestId('today.startFilming')).toBeVisible();
    await expect(screen.getByTestId('today.notEasier')).toBeHidden();
    await screen.getByTestId('today.overflow').tap();
    await expect(screen.getByRole('button', 'Need something easier?', { exact: true })).toBeHidden();
    await app.screenshot(`loop-${decision}-no-backup`);
  });
}

test('loop R1-3: script and caption copy exactly the saved text', async ({ screen, device }) => {
  await ready(screen, device);
  await openLoopEditor(screen);
  await screen.getByRole('button', 'Script', { exact: true }).tap();
  const script = await screen.getByTestId('shootFolio.script.editor').inputValue();
  expect(script.length).toBeGreaterThan(0);
  await screen.getByTestId('shootFolio.cancelEdit').tap();
  await tapVisibleControl(screen, screen.getByRole('button', 'Copy full script', { exact: true }));
  expect(await device.clipboard()).toBe(script);
  await openLoopPlanDay(screen, 1);
  await scrollToControl(screen, screen.getByTestId('daily.ready.edit.caption'));
  const caption = await screen.getByTestId('daily.ready.edit.caption').inputValue();
  expect(caption.length).toBeGreaterThan(0);
  await copyPlanCaption(screen);
  expect(await device.clipboard()).toBe(caption);
});

test('loop R1-3: audio copy contains only the displayed audio notes', async ({ screen, device }) => {
  await ready(screen, device);
  await openLoopEditor(screen);
  await screen.getByTestId('shootFolio.cancelEdit').tap();
  await screen.getByRole('button', 'Audio', { exact: true }).tap();
  const audio = screen.getByText('Use a calm but driving audio bed under the voiceover.', { exact: true });
  await expect(audio).toBeVisible();
  const text = await audio.textContent();
  expect((text ?? '').length).toBeGreaterThan(0);
  await screen.getByRole('button', 'Copy', { exact: true }).tap();
  expect(await device.clipboard()).toBe(text);
});

for (const section of ['Script', 'Caption', 'Audio'] as const) {
  test(`loop R1-3: missing ${section.toLowerCase()} never copies placeholder text`, async ({ screen, device }) => {
    await openLoopSession(device, 'blank-copy');
    await expect(screen.getByTestId('today.package.title')).toHaveText('Loop blank-copy package');
    await device.setClipboard('Keep this clipboard value');
    await openLoopEditor(screen);
    await screen.getByTestId('shootFolio.cancelEdit').tap();
    await screen.getByRole('button', section, { exact: true }).tap();
    await expect(screen.getByRole('button', /^(Copy|Copy full script)$/)).toBeHidden();
    expect(await device.clipboard()).toBe('Keep this clipboard value');
  });
}

test('loop R1-6: an established creator stays out of onboarding on relaunch', async ({ screen, device }) => {
  const session = await ready(screen, device);
  await relaunchLoopSession(device, session);
  await expect(screen.getByTestId('today.startFilming')).toBeVisible();
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeHidden();
});

test('loop R1-7: Plan keeps the tapped day across navigation and relaunch', async ({ screen, device }) => {
  const session = await ready(screen, device);
  await openLoopPlanDay(screen, 2);
  const header = await screen.getByTestId('plan.date.header').textContent();
  expect((header ?? '').length).toBeGreaterThan(0);
  await selectTab(screen, 'You');
  await selectTab(screen, 'Plan');
  await expect(screen.getByTestId(/^plan\.sevenDaySelector\.day\./).nth(2)).toBeSelected();
  await expect(screen.getByTestId('plan.date.header')).toHaveText(header!);
  await relaunchLoopSession(device, session);
  await selectTab(screen, 'Plan');
  await expect(screen.getByTestId(/^plan\.sevenDaySelector\.day\./).nth(2)).toBeSelected();
  await expect(screen.getByTestId('plan.date.header')).toHaveText(header!);
});

test('loop R1-7: an async generation stays on the day that started it', { timeout: 240_000 }, async ({ screen, device }) => {
  await ready(screen, device, { MCO_SLOW_FIRST_IDEA: '1' });
  await openLoopPlanDay(screen, 2);
  await tapVisibleControl(screen, screen.getByTestId('plan.daygen.idea.0'));
  await expect(screen.getByTestId('plan.generation.progress').filter({ hasText: /^Drafting / })).toBeVisible();
  await openLoopPlanDay(screen, 3);
  await expect(screen.getByTestId('plan.generation.backgroundHint')).toBeVisible();
  await expect(screen.getByTestId('plan.package.title')).toBeHidden();
  await openLoopPlanDay(screen, 2);
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  const title = await screen.getByTestId('plan.package.title').textContent();
  await openLoopPlanDay(screen, 3);
  await expect(screen.getByTestId('plan.package.title')).toBeHidden();
  await expect(screen.getByTestId('daily.availableOnToday')).toBeHidden();
  await openLoopPlanDay(screen, 2);
  await expect(screen.getByTestId('plan.package.title')).toHaveText(title!);
});

test('loop R1b-1: a failed posted decision stays on the phone and retries on relaunch', { timeout: 240_000 }, async ({ screen, device }) => {
  const session = await ready(screen, device);
  await finishLoopFilming(screen);
  await archiveHas(screen, 'Loop ready package');
  await relaunchLoopSession(device, session, { MCO_FAIL_TODAY_DECISION_SYNC_ONCE: '1' });
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.syncError')).toBeVisible();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await relaunchLoopSession(device, session, { MCO_FAIL_TODAY_DECISION_SYNC_ONCE: '0' });
  await expect(screen.getByTestId('today.startFilming')).toContainText('View posted content');
  await archiveHas(screen, 'Loop ready package');
  await relaunchLoopSession(device, session);
  await archiveHas(screen, 'Loop ready package');
});

test('loop R1b-3: the Script tab uses the creator lines before timed voiceover', async ({ screen, device }) => {
  await openLoopSession(device, 'line-script');
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop line-script package');
  await openLoopEditor(screen);
  await screen.getByTestId('shootFolio.cancelEdit').tap();
  await screen.getByRole('button', 'Script', { exact: true }).tap();
  for (let line = 1; line <= 10; line += 1) {
    const dialogue = screen.getByTestId('shoot.script.timeline').filter({ hasText: `Creator line ${line}.` });
    await scrollToControl(screen, dialogue);
    await expect(dialogue).toHaveText(`Creator line ${line}.`);
  }
});

test('loop R2-1: an older pending decision replays against its own card', async ({ screen, device }) => {
  const session = await openLoopSession(device, 'old-decision');
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop old-decision package');
  await archiveHas(screen, "Yesterday's loop package");
  await relaunchLoopSession(device, session);
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop old-decision package');
  await expect(screen.getByTestId('today.startFilming')).toContainText('Start filming');
  await archiveHas(screen, "Yesterday's loop package");
});

test('loop R3-F1: a new decision cannot erase an older failed decision', { timeout: 240_000 }, async ({ screen, device }) => {
  const session = await openLoopSession(device, 'old-decision', { MCO_FAIL_TODAY_DECISION_SYNC_ONCE: '1' });
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop old-decision package');
  await expect(screen.getByText(/Not saved to your account yet\./)).toBeVisible();
  await finishLoopFilming(screen);
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await relaunchLoopSession(device, session, { MCO_FAIL_TODAY_DECISION_SYNC_ONCE: '0' });
  await archiveHas(screen, "Yesterday's loop package");
  await screen.scrollUntilVisible(screen.getByText('Loop old-decision package', { exact: true }));
  await expect(screen.getByText('Loop old-decision package', { exact: true })).toHaveCount(1);
});

test('loop R1b-4 R2-4: failed replacement restores the title and filmed scene', { timeout: 240_000 }, async ({ app, screen, device }) => {
  const session = await ready(screen, device, { MCO_FAIL_FIRST_IDEA: '1' });
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('shoot.complete').tap();
  await app.back();
  await openLoopPlanDay(screen, 0);
  await requestLoopReplacement(screen);
  await expect(screen.getByText(/fixture_first_idea_generation_failed/)).toBeVisible();
  await selectTab(screen, 'Today');
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop ready package');
  await expect(screen.getByTestId('today.startFilming')).toContainText('Continue filming');
  await relaunchLoopSession(device, session);
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.progress')).toContainText('Shot 2 of');
  await screen.getByTestId('shoot.previous').tap();
  await expect(screen.getByTestId('shoot.complete')).toBeDisabled();
});

test('loop R2-4: a failed replacement restores a posted decision', { timeout: 240_000 }, async ({ app, screen, device }) => {
  const session = await ready(screen, device, { MCO_FAIL_FIRST_IDEA: '1' });
  await finishLoopFilming(screen);
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await app.back();
  await openLoopPlanDay(screen, 0);
  await requestLoopReplacement(screen);
  await expect(screen.getByText(/fixture_first_idea_generation_failed/)).toBeVisible();
  await selectTab(screen, 'Today');
  await expect(screen.getByTestId('today.startFilming')).toContainText('View posted content');
  await relaunchLoopSession(device, session);
  await expect(screen.getByTestId('today.startFilming')).toContainText('View posted content');
  await archiveHas(screen, 'Loop ready package');
});

test('loop R1b-5 R3-C6: a failed first idea retries on the next launch', { timeout: 180_000 }, async ({ screen, device }) => {
  const session = await openLoopSession(device, 'initial', {
    MCO_FORCE_ONBOARDING: '1', MCO_FORCE_EMPTY_TODAY: '1', MCO_FAIL_FIRST_IDEA_ONCE: '1',
  });
  await screen.getByTestId('onboarding.interest.books').tap();
  await screen.getByTestId('onboarding.generateFirstDay').tap();
  await expect(screen.getByTestId('onboarding.retryFirstIdea')).toBeVisible();
  await relaunchLoopSession(device, session, { MCO_FORCE_ONBOARDING: '0', MCO_FAIL_FIRST_IDEA_ONCE: '0' });
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await expect(screen.getByTestId('onboarding.setUpLater')).toBeHidden();
});

test('loop R2-6: an unedited script keeps all ten timed dialogue rows', async ({ screen, device }) => {
  await ready(screen, device);
  await openLoopEditor(screen);
  await screen.getByTestId('shootFolio.cancelEdit').tap();
  await screen.getByRole('button', 'Script', { exact: true }).tap();
  const lines = [
    'The biggest lie women are told after 40?',
    'That getting stronger is not for them anymore.',
    'I believed that too.',
    'I was scared of the gym.',
    'I started small and wondered if I belonged there.',
    'But here is what I learned.',
    'Your muscles do not know how old you are.',
    'They only know whether you use them.',
    'I feel stronger in my 60s than I did in my 40s.',
    'Do not let your age decide what your body is capable of.',
  ];
  for (const [index, line] of lines.entries()) {
    const timecode = `${index * 3}-${(index + 1) * 3} sec`;
    const time = screen.getByTestId('shoot.script.timeline').filter({ hasText: new RegExp(`^${timecode}$`) });
    await scrollToControl(screen, time);
    await expect(time).toHaveText(timecode);
    const dialogue = screen.getByTestId('shoot.script.timeline').filter({ hasText: line });
    await scrollToControl(screen, dialogue);
    await expect(dialogue).toHaveText(line);
  }
});

test('loop R3-L1 R2-7: posting a replacement retains two distinct archive records', { timeout: 360_000 }, async ({ screen, device }) => {
  const session = await ready(screen, device);
  await finishLoopFilming(screen);
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await archiveHas(screen, 'Loop ready package');
  await openLoopPlanDay(screen, 0);
  await requestLoopReplacement(screen);
  await expect(screen.getByTestId('daily.availableOnToday')).toBeVisible({ timeout: 45_000 });
  const replacement = await screen.getByTestId('plan.package.title').textContent();
  expect(replacement).not.toBe('Loop ready package');
  await approveLoopPackage(screen);
  await relaunchLoopSession(device, session);
  await archiveHas(screen, 'Loop ready package');
  await selectTab(screen, 'Today');
  await expect(screen.getByTestId('today.package.title')).toHaveText(replacement!);
  await finishLoopFilming(screen);
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await relaunchLoopSession(device, session);
  await archiveHas(screen, 'Loop ready package');
  await screen.scrollUntilVisible(screen.getByText(replacement!, { exact: true }));
  await expect(screen.getByText(replacement!, { exact: true })).toHaveCount(1);
});

test('loop R3-L3: one word changes only its shot dialogue', async ({ app, screen, device }) => {
  const session = await ready(screen, device);
  await editScript(screen, device, text => text.replace('biggest', 'loudest'));
  await app.back();
  await relaunchLoopSession(device, session);
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.scene.1').filter({ hasText: /loudest lie/ })).toContainText('loudest lie');
  await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.scene.2').filter({ hasText: /^That getting stronger is not for them anymore\.$/ })).toHaveText('That getting stronger is not for them anymore.');
  for (let shot = 3; shot <= 10; shot += 1) await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.scene.10').filter({ hasText: /^Do not let your age decide what your body is capable of\.$/ })).toHaveText('Do not let your age decide what your body is capable of.');
});

test('loop R3-L3: a paragraph edit cannot silently erase later shot dialogue', async ({ app, screen, device }) => {
  await ready(screen, device);
  await editScript(screen, device, text => text.replace('biggest', 'loudest').replace(/\n/g, ' '));
  await app.back();
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.scene.2').filter({ hasText: /^That getting stronger is not for them anymore\.$/ })).toHaveText('That getting stronger is not for them anymore.');
  for (let shot = 3; shot <= 10; shot += 1) await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.scene.10').filter({ hasText: /^Do not let your age decide what your body is capable of\.$/ })).toHaveText('Do not let your age decide what your body is capable of.');
});

test('loop R3-L4: a saved scene duration changes this and following filming timecodes', async ({ app, screen, device }) => {
  const session = await ready(screen, device);
  await openLoopEditor(screen);
  await clearThenType(screen, screen.getByTestId('shootFolio.scene.1.duration'), '8 sec');
  await saveLoopEditor(screen, device);
  await app.back();
  await relaunchLoopSession(device, session);
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByTestId('shoot.scene.1').filter({ hasText: /^0-8 sec, pending$/ })).toContainText('0-8 sec');
  await expect(screen.getByTestId('shoot.scene.1').filter({ hasText: /^Use your usual camera app\./ })).toContainText('8 sec');
  await screen.getByTestId('shoot.next').tap();
  await expect(screen.getByTestId('shoot.scene.2').filter({ hasText: /^8-11 sec, pending$/ })).toContainText('8-11 sec');
});

test('loop R3-C1: an old pending-decision cache keeps filming completion and replays its decision', async ({ screen, device }) => {
  const session = await openLoopSession(device, 'legacy-cache');
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop legacy-cache package');
  await expect(screen.getByTestId('today.startFilming')).toContainText('Get post text');
  await archiveHas(screen, 'Loop legacy-cache package');
  await relaunchLoopSession(device, session);
  await expect(screen.getByTestId('today.startFilming')).toContainText('Get post text');
  await archiveHas(screen, 'Loop legacy-cache package');
});

test('loop R3-C3: edit, unpublish, and make ready never resurrect Posted', { timeout: 240_000 }, async ({ screen, device }) => {
  const session = await ready(screen, device);
  await finishLoopFilming(screen);
  await screen.getByTestId('post.markPosted').tap();
  await expect(screen.getByTestId('post.undoPosted')).toBeVisible();
  await openLoopPlanDay(screen, 0);
  await clearThenType(screen, screen.getByTestId('daily.ready.edit.caption'), 'An edited caption for the same revision.');
  await tapVisibleControl(screen, screen.getByTestId('daily.ready.edit.save'));
  await expect(screen.getByTestId('daily.ready.edit.save')).toHaveText('Save caption');
  await expect(screen.getByTestId('daily.ready.edit.save')).toBeDisabled();
  await tapVisibleControl(screen, screen.getByTestId('daily.unpublish'));
  await screen.getByRole('group', 'Unpublish this day?', { exact: true })
    .getByRole('button', 'Unpublish', { exact: true }).tap();
  await approveLoopPackage(screen);
  await relaunchLoopSession(device, session);
  await archiveHas(screen, 'Loop ready package');
  await selectTab(screen, 'Today');
  await expect(screen.getByTestId('today.startFilming')).not.toContainText('View posted content');
});

test('loop R3-C4: a stale fixture pointer resolves to the ready package for today', async ({ screen, device }) => {
  const session = await openLoopSession(device, 'stale-pointer', { MCO_FORCE_EMPTY_TODAY: '1' });
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop stale-pointer package');
  await expect(screen.getByText("Yesterday's loop package", { exact: true })).toBeHidden();
  await relaunchLoopSession(device, session);
  await expect(screen.getByTestId('today.package.title')).toHaveText('Loop stale-pointer package');
});

test('loop R3-C5: the initial ready fixture can save its first scene edit', async ({ app, screen, device }) => {
  const session = await openLoopSession(device, 'initial');
  await openLoopEditor(screen);
  await clearThenType(screen, screen.getByTestId('shootFolio.scene.1.title'), 'Saved initial fixture edit');
  await saveLoopEditor(screen, device);
  await app.back();
  await relaunchLoopSession(device, session);
  await screen.getByTestId('today.startFilming').tap();
  await expect(screen.getByText('Saved initial fixture edit', { exact: true })).toBeVisible();
});

test('loop R3-C6: onboarding interests survive the same fixture session relaunch', { timeout: 180_000 }, async ({ screen, device }) => {
  const session = await openLoopSession(device, 'initial', { MCO_FORCE_ONBOARDING: '1', MCO_FORCE_EMPTY_TODAY: '1' });
  await screen.getByTestId('onboarding.interest.books').tap();
  await expect(screen.getByTestId('onboarding.interest.books')).toBeSelected();
  await screen.getByTestId('onboarding.generateFirstDay').tap();
  await expect(screen.getByTestId('today.startFilming')).toBeVisible({ timeout: 45_000 });
  await relaunchLoopSession(device, session, { MCO_FORCE_ONBOARDING: '0' });
  await selectTab(screen, 'You');
  await screen.getByTestId('you.preferences.toggle').tap();
  await screen.getByTestId('you.row.interests').tap();
  await expect(screen.getByTestId('you.interests.chip.books')).toBeSelected();
});

test('loop R2-7: a future caption edit is displayed, copied, and restored', async ({ screen, device }) => {
  const session = await ready(screen, device);
  await openLoopPlanDay(screen, 1);
  const caption = 'Saved future loop caption.';
  await clearThenType(screen, screen.getByTestId('daily.ready.edit.caption'), caption);
  await tapVisibleControl(screen, screen.getByTestId('daily.ready.edit.save'));
  await expect(screen.getByTestId('daily.ready.edit.save')).toHaveText('Save caption');
  await expect(screen.getByTestId('daily.ready.edit.save')).toBeDisabled();
  await openLoopPlanDay(screen, 2);
  await openLoopPlanDay(screen, 1);
  await scrollToControl(screen, screen.getByTestId('daily.ready.edit.caption'));
  await expect(screen.getByTestId('daily.ready.edit.caption')).toHaveValue(caption);
  await copyPlanCaption(screen);
  expect(await device.clipboard()).toBe(caption);
  await relaunchLoopSession(device, session);
  await openLoopPlanDay(screen, 1);
  await scrollToControl(screen, screen.getByTestId('daily.ready.edit.caption'));
  await expect(screen.getByTestId('daily.ready.edit.caption')).toHaveValue(caption);
});

test('loop R3-C7: Plan blocks a blank caption save', async ({ screen, device }) => {
  await ready(screen, device);
  await openLoopPlanDay(screen, 1);
  await scrollToControl(screen, screen.getByTestId('daily.ready.edit.caption'));
  const editor = screen.getByTestId('daily.ready.edit.caption');
  const original = await editor.inputValue();
  await clearThenType(screen, editor, '   ');
  await scrollToControl(screen, screen.getByTestId('daily.ready.edit.save'));
  await expect(screen.getByTestId('daily.ready.edit.save')).toBeDisabled();
  await openLoopPlanDay(screen, 2);
  await openLoopPlanDay(screen, 1);
  await scrollToControl(screen, editor);
  await expect(editor).toHaveValue(original);
});

test('loop R3-C7: Shoot Folio blocks a blank script save', async ({ screen, device }) => {
  await ready(screen, device);
  await openLoopEditor(screen);
  await screen.getByRole('button', 'Script', { exact: true }).tap();
  await clearThenType(screen, screen.getByTestId('shootFolio.script.editor'), '');
  await dismissKeyboard(screen);
  await expect(screen.getByTestId('shootFolio.saveEdits')).toBeDisabled();
});

test('loop R3-C7: Post refuses blank script and caption without changing the saved package', { timeout: 240_000 }, async ({ screen, device }) => {
  const session = await ready(screen, device);
  await finishLoopFilming(screen);
  await screen.getByTestId('post.edit').tap();
  const script = screen.getByTestId('post.script.editor');
  const caption = screen.getByTestId('post.caption.editor');
  const save = screen.getByTestId('post.save');
  const originalScript = await script.inputValue();
  await scrollToControl(screen, caption);
  const originalCaption = await caption.inputValue();
  expect(originalScript.trim().length).toBeGreaterThan(0);
  expect(originalCaption.trim().length).toBeGreaterThan(0);
  await clearThenType(screen, script, '');
  await dismissKeyboard(screen, 'post.keyboardDone');
  await expect(save).toBeDisabled();
  await clearThenType(screen, caption, '');
  await dismissKeyboard(screen, 'post.keyboardDone');
  await expect(save).toBeDisabled();
  const error = screen.getByText('Keep some text in Script and Caption before saving.', { exact: true });
  await screen.scrollUntilVisible(error, { direction: 'up' });
  await expect(error).toBeVisible();
  await expect(screen.getByTestId('post.cancel')).toBeVisible();
  await clearThenType(screen, script, 'A valid script draft that must not be saved.');
  await dismissKeyboard(screen, 'post.keyboardDone');
  await expect(save).toBeDisabled();
  await clearThenType(screen, caption, 'A valid caption draft that must not be saved.');
  await dismissKeyboard(screen, 'post.keyboardDone');
  await expect(save).toBeEnabled();
  await tapEditorControl(screen, 'post.cancel');
  await relaunchLoopSession(device, session);
  await screen.getByTestId('today.startFilming').tap();
  await screen.getByTestId('post.edit').tap();
  await scrollToControl(screen, script, 'up');
  await expect(script).toHaveValue(originalScript);
  await scrollToControl(screen, caption);
  await expect(caption).toHaveValue(originalCaption);
});
