import { expect, test } from 'e2e';
import { appendFile, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';

test('Smoke returns three ideas from one live QA job', {
  timeout: 300_000, tags: ['@reel', '@d2', '@phone-smoke'],
}, async () => {
  test.skip(process.env.MIRA_E2E_SMOKE_LIVE_IDEAS !== '1', 'Use the isolated live QA workspace for this smoke check.');
  const creatorID = process.env.MCO_LIVE_CREATOR_ID;
  const deviceToken = process.env.MCO_LIVE_DEVICE_TOKEN;
  const publishableKey = process.env.MCO_SUPABASE_PUBLISHABLE_KEY;
  const ledgerDir = process.env.MIRA_E2E_LIVE_LEDGER_DIR;
  if (!creatorID || !deviceToken || !publishableKey || !ledgerDir) {
    throw new Error('Supply the live QA credentials and smoke ledger directory.');
  }
  expect(process.env.MIRA_E2E_LIVE_REQUEST_LIMIT).toBe('3');
  expect(process.env.MIRA_E2E_LIVE_PICTURE_LIMIT).toBe('0');

  const id = crypto.randomUUID();
  const ledger = resolve(ledgerDir, 'live-requests.jsonl');
  const input = {
    operation: 'ideas',
    profile: { name: 'Example creator', themes: 'Food', audience: 'Friends', language: 'English',
      writingSystem: 'Romanised', tone: 'Warm', avoid: 'Claims', samples: '', solo: true },
    constraints: { filmingMinutes: 15, location: 'Home', style: 'Either', reelSeconds: 30, equipment: 'Phone' },
    request: 'At home, show the first step of making morning chai.',
    recentIdeas: [],
  };
  async function request(action: 'start' | 'status') {
    const response = await fetch('https://zogvvrxhiwozjmufvddu.supabase.co/functions/v1/mira-generation', {
      method: 'POST',
      redirect: 'error',
      signal: AbortSignal.timeout(10_000),
      headers: {
        'content-type': 'application/json', 'x-mco-device-token': deviceToken!,
        apikey: publishableKey!, authorization: `Bearer ${publishableKey}`,
      },
      body: JSON.stringify({ action, id, creatorID, pictures: false,
        ...(action === 'start' ? { inputRevision: 1, consentVersion: 1, input } : {}) }),
    });
    if (!response.ok) throw new Error(`Mira ${action} returned HTTP ${response.status}.`);
    const { job } = await response.json();
    expect(job.id).toBe(id);
    expect(job.input.operation).toBe('ideas');
    return job;
  }

  const reservation = { at: new Date().toISOString(), id, operation: 'ideas', calls: 3, pictureSlots: 0 };
  await writeFile(ledger, JSON.stringify(reservation) + '\n', { flag: 'wx', mode: 0o600 });
  let job = await request('start');
  if (job.state === 'working') {
    await expect.poll(async () => {
      job = await request('status');
      return job.state;
    }, { timeout: 260_000, interval: 3_000 }).not.toBe('working');
  }
  expect(job.state).toBe('succeeded');
  const ideas = job.output?.ideas;
  expect(ideas).toHaveLength(3);
  expect(new Set(ideas.map((idea: { title: string }) => idea.title.trim().toLowerCase())).size).toBe(3);
  expect(job.output?.script ?? null).toBeNull();
  expect(job.output?.storyboard ?? null).toBeNull();
  expect(job.pictures ?? []).toHaveLength(0);
  await appendFile(ledger, JSON.stringify({ at: new Date().toISOString(), id, ideas: 3, pictures: 0 }) + '\n');
});
