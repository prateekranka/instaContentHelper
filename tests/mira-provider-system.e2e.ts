import { afterAll, beforeAll, expect, test } from 'e2e';
import { spawn, type ChildProcess } from 'node:child_process';
import { createServer } from 'node:net';

let server: ChildProcess;
let base: string;
const creatorID = '10000000-0000-4000-8000-000000000002';
const input = {
  operation: 'ideas',
  profile: { name: 'Example creator', themes: 'Food', audience: 'Friends', language: 'English',
    writingSystem: 'Romanised', tone: 'Warm', avoid: 'Claims', samples: '', solo: true },
  constraints: { filmingMinutes: 15, location: 'Home', style: 'Either', reelSeconds: 30, equipment: 'Phone' },
  request: 'A simple idea', recentIdeas: [],
};

beforeAll(async () => {
  const port = await new Promise<number>((resolve, reject) => {
    const probe = createServer();
    probe.once('error', reject);
    probe.listen(0, '127.0.0.1', () => {
      const address = probe.address();
      if (!address || typeof address === 'string') return reject(new Error('port_unavailable'));
      probe.close(() => resolve(address.port));
    });
  });
  base = `http://127.0.0.1:${port}`;
  server = spawn('deno', ['run', '--allow-net=127.0.0.1', '--allow-env=MIRA_FIXTURE_PORT',
    'tests/fixtures/mira-provider-server.ts'], {
    env: { ...process.env, MIRA_FIXTURE_PORT: String(port) }, stdio: ['ignore', 'pipe', 'pipe'],
  });
  await new Promise<void>((resolve, reject) => {
    const deadline = setTimeout(() => reject(new Error('fixture_server_timeout')), 30_000);
    server.stderr?.on('data', (chunk) => {
      if (String(chunk).includes('Listening on')) { clearTimeout(deadline); resolve(); }
    });
    server.once('error', reject);
    server.once('exit', (code) => { clearTimeout(deadline); reject(new Error(`fixture_server_exit:${code}`)); });
  });
});

afterAll(async () => { if (server && server.exitCode === null) server.kill('SIGTERM'); });

async function call(
  id: string, action: 'start' | 'status', provider: string,
  mode = 'ok', consent = true, token = true, jobInput: object = input,
) {
  const response = await fetch(`${base}/mira-generation`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-fixture-provider': provider, 'x-fixture-mode': mode,
      ...(token ? { 'x-mco-device-token': 'fixture-device-token' } : {}) },
    body: JSON.stringify({ action, id, creatorID, ...(action === 'start' ? {
      inputRevision: 1, input: jobInput, ...(consent ? { consentVersion: 1 } : {}),
    } : {}) }),
  });
  return { status: response.status, body: await response.json() };
}

async function observations() {
  return await (await fetch(`${base}/observations`)).json() as {
    calls: { url: string; model: string; mode: string }[];
    jobs: { id: string; status: string; error?: string }[];
  };
}

test('rejects unsigned and non-consented requests without calling a provider', async () => {
  const before = (await observations()).calls.length;
  expect((await call(crypto.randomUUID(), 'start', 'deepseek', 'ok', true, false)).status).toBe(401);
  expect((await call(crypto.randomUUID(), 'start', 'deepseek', 'ok', false, true)).status).toBe(400);
  expect((await observations()).calls.length).toBe(before);
});

for (const provider of ['deepseek', 'openai', 'gemini']) {
  test(`${provider} returns a validated idea job through the same endpoint`, async () => {
    const id = crypto.randomUUID();
    expect((await call(id, 'start', provider)).status).toBe(200);
    const result = await call(id, 'status', provider);
    expect(result.status).toBe(200);
    expect(result.body.job.state).toBe('succeeded');
    expect(result.body.job.output.ideas).toHaveLength(3);
    const seen = await observations();
    const last = seen.calls.at(-1)!;
    expect(last.url).toContain(provider === 'gemini' ? 'generativelanguage.googleapis.com' : `api.${provider}.com`);
    expect(last.model).toBe('fixture-model');
  });
}

test('a provider outage is queued for retry and invalid output fails closed', async () => {
  const retry = crypto.randomUUID();
  expect((await call(retry, 'start', 'gemini', 'unavailable')).status).toBe(200);
  let seen = await observations();
  expect(seen.jobs.find((job) => job.id === retry)?.status).toBe('queued');
  expect(seen.jobs.find((job) => job.id === retry)?.error).toContain('Retrying is bounded');
  const invalid = crypto.randomUUID();
  expect((await call(invalid, 'start', 'openai', 'invalid')).status).toBe(200);
  seen = await observations();
  expect(seen.jobs.find((job) => job.id === invalid)?.status).toBe('failed');
});

test('a storyboard has filming fields and revising one shot preserves a legacy shot', async () => {
  const script = {
    id: crypto.randomUUID(), hook: 'Here is my breakfast.', spoken: 'Add fruit to the bowl.',
    caption: 'My breakfast', durationSeconds: 20, language: 'English',
  };
  const storyboardInput = { ...input, operation: 'storyboard', script };
  async function run(jobInput: object, mode = 'ok') {
    const id = crypto.randomUUID();
    const start = await call(id, 'start', 'openai', mode, true, true, jobInput);
    expect(start.status).toBe(200);
    const result = await call(id, 'status', 'openai', mode);
    expect(result.status).toBe(200);
    return result.body.job;
  }

  const invalid = await run(storyboardInput, 'blank-distance');
  expect(invalid.state).toBe('failed');

  const generated = await run(storyboardInput);
  expect(generated.state).toBe('succeeded');
  const board = generated.output.storyboard;
  expect(board.shots).toHaveLength(2);
  expect(board.shots[0].distance).toBe('One arm’s length');
  expect(board.shots[0].framing).toBe('Head and shoulders');

  const legacyShot = { ...board.shots[1] };
  delete legacyShot.distance;
  delete legacyShot.framing;
  const revision = {
    ...storyboardInput, operation: 'reviseShot', targetShotID: board.shots[0].id,
    storyboard: { ...board, shots: [board.shots[0], legacyShot] },
  };
  expect((await run(revision, 'wrong-target')).state).toBe('failed');
  const revised = await run(revision);
  expect(revised.state).toBe('succeeded');
  const shots = revised.output.storyboard.shots;
  expect(shots).toHaveLength(2);
  expect(shots[0].id).toBe(revision.targetShotID);
  expect(shots[0].distance).toBe('Two big steps');
  expect(shots[0].framing).toBe('Waist up');
  expect(JSON.stringify(shots[1])).toBe(JSON.stringify(legacyShot));
});
