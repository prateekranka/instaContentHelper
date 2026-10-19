import { test } from '@e2e-dev/mobile';
import { expect } from 'e2e';
import { relaunch, selectTab, startFromOnboarding, tapEditorControl, writePiece } from './pocket-support';

test('a date holds several pieces, approved by piece or reviewed group, with edits that keep the approved version', { timeout: 420_000 }, async ({ app, screen, device }) => {
  if (process.env.POCKET_E2E_INSTALL === '1') await device.installApp();
  await startFromOnboarding(app, screen);
  await expect(screen.getByTestId('today.summary')).toHaveText('Day approved · 1 piece');

  await screen.getByTestId('today.addContent').tap();
  await writePiece(screen, 'Recovery routine');
  await expect(screen.getByTestId('today.summary')).toHaveText('2 pieces · 1 approved · 1 needs review');
  await screen.getByTestId('today.addContent').tap();
  await writePiece(screen, 'A small win');
  await expect(screen.getByTestId('today.summary')).toHaveText('3 pieces · 1 approved · 2 need review');
  await expect(screen.getByTestId('today.piece.0')).toContainText('Approved');
  await expect(screen.getByTestId('today.piece.1')).toContainText('Recovery routine');
  await expect(screen.getByTestId('today.piece.2')).toContainText('A small win');
  await app.screenshot('pieces-today-three');

  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Review day');
  await screen.getByTestId('today.primaryAction').tap();
  await expect(screen.getByTestId('reviewDay.title')).toBeVisible();
  await expect(screen.getByTestId('reviewDay.approve')).toHaveText('Approve 2 pieces');
  await app.screenshot('pieces-review-day');
  await screen.getByTestId('reviewDay.approve').tap();
  await expect(screen.getByTestId('reviewDay.approve')).toBeDisabled();
  await app.back();
  await expect(screen.getByTestId('today.summary')).toHaveText('Day approved · 3 pieces');
  await expect(screen.getByTestId('today.dayApproved')).toBeVisible();

  await screen.getByTestId('today.piece.1').tap();
  await expect(screen.getByTestId('piece.status')).toContainText('Approved · version 1');
  await screen.getByTestId('piece.edit.script').tap();
  await expect(screen.getByTestId('editor.script')).toBeVisible();
  await screen.getByTestId('editor.script').pressSequentially('Slow breaths, then stretch.');
  await screen.getByTestId('editor.keyboardDone').tap();
  await tapEditorControl(screen, 'editor.save');
  await expect(screen.getByTestId('piece.draftBadge')).toContainText('Draft version 2');
  await expect(screen.getByTestId('piece.status')).toContainText('Approved · version 1');
  await expect(screen.getByTestId('piece.approve')).toHaveText('Approve new version');
  await app.screenshot('pieces-draft-revision');
  await app.back();
  await expect(screen.getByTestId('today.summary')).toHaveText('3 pieces · 2 approved · 1 needs review');
  await expect(screen.getByTestId('today.piece.1')).toContainText('New draft to review');

  await screen.getByTestId('today.piece.1').tap();
  await screen.scrollUntilVisible(screen.getByTestId('piece.versions'));
  await screen.getByTestId('piece.versions').tap();
  await expect(screen.getByTestId('versions.version.2')).toContainText('Draft');
  await expect(screen.getByTestId('versions.version.1')).toContainText('Approved');
  await app.screenshot('pieces-versions');
  await screen.getByTestId('versions.reviewChanges').tap();
  await expect(screen.getByTestId('changes.summary')).toContainText('Script updated');
  await screen.getByTestId('changes.approve').tap();
  await app.back();
  await expect(screen.getByTestId('versions.version.2')).toContainText('Approved');
  await expect(screen.getByTestId('versions.version.1')).toContainText('Approved earlier');
  await app.back();
  await expect(screen.getByTestId('piece.status')).toContainText('Approved · version 2');
  await app.back();
  await expect(screen.getByTestId('today.summary')).toHaveText('Day approved · 3 pieces');

  await relaunch(device);
  await expect(screen.getByTestId('today.summary')).toHaveText('Day approved · 3 pieces');
  await expect(screen.getByTestId('today.piece.1')).toContainText('Recovery routine');
  await app.screenshot('pieces-after-relaunch');
});

test('filming resumes after Pause and relaunch, then each platform keeps its own manual result', { timeout: 420_000 }, async ({ app, screen, device }) => {
  await startFromOnboarding(app, screen);
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Start filming');
  await screen.getByTestId('today.primaryAction').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 1 OF');
  const progress = await screen.getByTestId('filming.progress').textContent();
  const count = Number(progress.match(/OF\s+([\d,]+)/)?.[1]?.replace(/,/g, ''));
  expect(count).toBeGreaterThan(1);
  await expect(screen.getByTestId('filming.previous')).toBeDisabled();
  for (const id of ['filming.markCaptured', 'filming.previous', 'filming.pause']) {
    const box = await screen.getByTestId(id).boundingBox();
    expect(box.height).toBeGreaterThanOrEqual(44);
  }
  await app.screenshot('pieces-filming-first');
  await screen.getByTestId('filming.markCaptured').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 2 OF');
  await screen.getByTestId('filming.pause').tap();
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Continue filming');
  await expect(screen.getByTestId('today.piece.0')).toContainText(`Filming · 1 of ${count} shots`);

  await relaunch(device);
  await expect(screen.getByTestId('today.primaryAction')).toHaveText('Continue filming');
  await screen.getByTestId('today.primaryAction').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 2 OF');
  await screen.getByTestId('filming.previous').tap();
  await expect(screen.getByTestId('filming.progress')).toContainText('SHOT 1 OF');
  await expect(screen.getByTestId('filming.unmark')).toBeVisible();
  await screen.getByTestId('filming.next').tap();
  for (let shot = 2; shot <= count; shot += 1) {
    await expect(screen.getByTestId('filming.progress')).toContainText(`SHOT ${shot} OF`);
    await screen.getByTestId('filming.markCaptured').tap();
  }
  await expect(screen.getByTestId('filming.reviewShots')).toBeVisible();
  await screen.getByTestId('filming.reviewShots').tap();
  await expect(screen.getByTestId('shots.title')).toHaveText(`All ${count} shots captured`);
  await app.screenshot('pieces-all-shots');
  await screen.getByTestId('shots.markShot').tap();
  await screen.getByTestId('shots.preparePost').tap();
  await expect(screen.getByTestId('ready.status')).toContainText('Shot');
  await expect(screen.getByTestId('ready.finalMedia')).toContainText('Choose final video');
  await app.screenshot('pieces-ready-to-post');
  await screen.getByTestId('ready.preparePost').tap();
  await screen.getByTestId('post.target.instagram').tap();
  await screen.getByTestId('post.target.tiktok').tap();
  await expect(screen.getByTestId('post.target.instagram')).toBeSelected();
  await expect(screen.getByTestId('post.review')).toHaveText('Review Instagram');
  await app.screenshot('pieces-post-options');
  await screen.getByTestId('post.review').tap();
  await expect(screen.getByTestId('finish.caption')).toBeVisible();
  await screen.getByTestId('finish.link').pressSequentially('https://www.instagram.com/p/example');
  await screen.getByTestId('finish.markPosted').tap();
  await expect(screen.getByTestId('results.instagram')).toContainText('Marked posted by you');
  await expect(screen.getByTestId('results.tiktok')).toContainText('Not posted');
  await app.screenshot('pieces-post-results');
  await screen.getByTestId('results.backToToday').tap();
  await expect(screen.getByTestId('today.piece.0')).toContainText('Instagram marked posted · TikTok not posted');

  await relaunch(device);
  await expect(screen.getByTestId('today.piece.0')).toContainText('Instagram marked posted · TikTok not posted');
  await screen.getByTestId('today.piece.0').tap();
  await expect(screen.getByTestId('piece.note')).toContainText('do not update the live post');
  await screen.getByTestId('piece.makeChanges').tap();
  await screen.getByRole('button', 'Create a new version to post again', { exact: true }).tap();
  await expect(screen.getByTestId('piece.status')).toContainText('Draft');
  await app.back();
  await app.back();
  await expect(screen.getByTestId('today.summary')).toContainText('2 pieces');
  await expect(screen.getByTestId('today.piece.0')).toContainText('Instagram marked posted');
  await app.screenshot('pieces-new-version-after-post');
});

test('a date with an AI package takes a second AI draft and a written piece, and Your content and Plan show all three', { timeout: 300_000 }, async ({ app, screen }) => {
  await startFromOnboarding(app, screen);
  await screen.getByTestId('today.addContent').tap();
  await screen.getByTestId('composer.topic').pressSequentially('A second idea for today');
  await screen.getByTestId('composer.format.story').tap();
  await expect(screen.getByTestId('composer.format.story')).toBeSelected();
  await screen.getByTestId('composer.createDraft').tap();
  await expect(screen.getByTestId('piece.status')).toContainText('Draft', { timeout: 45_000 });
  await expect(screen.getByTestId('piece.approve')).toHaveText('Approve content');
  await app.screenshot('pieces-second-ai-draft');
  await screen.getByTestId('composer.cancel').tap();
  await expect(screen.getByTestId('today.summary')).toHaveText('2 pieces · 1 approved · 1 needs review');
  await expect(screen.getByTestId('today.piece.0')).toContainText('Approved');

  await screen.getByTestId('today.addContent').tap();
  await writePiece(screen, 'Evening stretch');
  await expect(screen.getByTestId('today.summary')).toHaveText('3 pieces · 1 approved · 2 need review');

  await selectTab(screen, 'You');
  await screen.scrollUntilVisible(screen.getByTestId('you.yourContent'));
  await screen.getByTestId('you.yourContent').tap();
  await expect(screen.getByTestId('content.piece.Evening stretch')).toBeVisible();
  await screen.getByTestId('content.filter.posted').tap();
  await expect(screen.getByTestId('content.empty')).toBeVisible();
  await screen.getByTestId('content.filter.draft').tap();
  await expect(screen.getByTestId('content.piece.Evening stretch')).toBeVisible();
  await app.screenshot('pieces-your-content');

  await selectTab(screen, 'Plan');
  await expect(screen.getByTestId('plan.pieces')).toBeVisible();
  await expect(screen.getByTestId('plan.pieces.summary')).toHaveText('3 pieces · 1 approved · 2 need review');
  await expect(screen.getByTestId('plan.pieces.piece.2')).toContainText('Evening stretch');
  await screen.getByTestId('plan.pieces.openDay').tap();
  await expect(screen.getByTestId('day.title')).toBeVisible();
  await expect(screen.getByTestId('day.piece.2')).toContainText('Evening stretch');
  await app.screenshot('pieces-plan-day');

  await screen.getByTestId('day.piece.2').tap();
  await screen.getByTestId('piece.options').tap();
  await screen.getByRole('button', 'Move earlier in the day', { exact: true }).tap();
  await screen.getByTestId('piece.options').tap();
  await screen.getByRole('button', 'Remove from day', { exact: true }).tap();
  await screen.getByRole('button', 'Remove from day', { exact: true }).tap();
  await expect(screen.getByTestId('piece.restore')).toBeVisible();
  await expect(screen.getByTestId('piece.note')).toContainText('Archived');
  await app.back();
  await expect(screen.getByTestId('day.title')).toContainText('2 pieces');
  await selectTab(screen, 'You');
  await screen.getByTestId('content.filter.archived').tap();
  await expect(screen.getByTestId('content.piece.Evening stretch')).toBeVisible();
  await screen.getByTestId('content.piece.Evening stretch').tap();
  await screen.getByTestId('piece.restore').tap();
  await expect(screen.getByTestId('piece.restore')).toBeHidden();
  await selectTab(screen, 'Today');
  await expect(screen.getByTestId('today.summary')).toHaveText('3 pieces · 1 approved · 2 need review');
  await app.screenshot('pieces-archive-restore');
});
