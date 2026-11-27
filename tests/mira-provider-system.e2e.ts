import { afterAll, beforeAll, expect, test } from 'e2e';
import { spawn, type ChildProcess } from 'node:child_process';
import { writeFile } from 'node:fs/promises';
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
  server = spawn('deno', ['run', '--allow-net=127.0.0.1', '--allow-env=MIRA_FIXTURE_PORT,MIRA_API_E2E_LOCAL_PORT,MIRA_API_E2E_LOCAL_SERVICE_ROLE',
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
  id: string, action: 'start' | 'status' | 'cancel', provider: string,
  mode = 'ok', consent = true, token: boolean | string = true, jobInput: object = input,
) {
  const response = await fetch(`${base}/mira-generation`, {
    method: 'POST',
    headers: { 'content-type': 'application/json', 'x-fixture-provider': provider, 'x-fixture-mode': mode, 'x-fixture-job': id,
      ...(token ? { 'x-mco-device-token': typeof token === 'string' ? token : 'fixture-device-token' } : {}) },
    body: JSON.stringify({ action, id, creatorID, ...(action === 'start' ? {
      inputRevision: 1, input: jobInput, ...(consent ? { consentVersion: 1 } : {}),
    } : {}) }),
  });
  return { status: response.status, body: await response.json(), headers: response.headers };
}

async function observations() {
  return await (await fetch(`${base}/observations`)).json() as {
    calls: { url: string; model: string; mode: string; payload?: Record<string, unknown> }[];
    stepWrites: { id: string; step: string }[];
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
    expect(result.body.job.phase).toBe('succeeded');
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
  const retryStatus = await call(retry, 'status', 'gemini');
  expect(retryStatus.body.job.state).toBe('working');
  expect(retryStatus.body.job.phase).toBe('waiting_to_retry');
  const invalid = crypto.randomUUID();
  expect((await call(invalid, 'start', 'openai', 'invalid')).status).toBe(200);
  seen = await observations();
  expect(seen.jobs.find((job) => job.id === invalid)?.status).toBe('failed');
  expect((await call(invalid, 'status', 'openai')).body.job.phase).toBe('failed');
});

test('job phase distinguishes a new, held, expired, recovered and cancelled claim', async () => {
  const held = crypto.randomUUID();
  const start = await call(held, 'start', 'deepseek', 'lost-claim');
  expect(start.body.job.state).toBe('working');
  expect(start.body.job.phase).toBe('queued');
  const active = await call(held, 'status', 'deepseek');
  expect(active.body.job.state).toBe('working');
  expect(active.body.job.phase).toBe('running');
  const cancelled = await call(held, 'cancel', 'deepseek');
  expect(cancelled.body.job.state).toBe('cancelled');
  expect(cancelled.body.job.phase).toBe('cancelled');

  const expired = crypto.randomUUID();
  expect((await call(expired, 'start', 'deepseek', 'lost-expired-claim')).status).toBe(200);
  const retry = await call(expired, 'status', 'deepseek');
  expect(retry.body.job.state).toBe('working');
  expect(retry.body.job.phase).toBe('waiting_to_retry');
  const recovered = await call(expired, 'status', 'deepseek');
  expect(recovered.body.job.phase).toBe('succeeded');
});

test('a claim with too little time left fails without starting the provider', async () => {
  const id = crypto.randomUUID();
  const before = (await observations()).calls.length;
  expect((await call(id, 'start', 'openai', 'remaining-lease-short')).status).toBe(200);
  const { body } = await call(id, 'status', 'openai');
  expect(body.job.state).toBe('failed');
  expect(body.job.phase).toBe('failed');
  expect(body.job.error).toContain('mira_insufficient_lease_budget');
  expect((await observations()).calls.length).toBe(before);
});

test('local PostgREST rejects short claims and forbidden job status changes', async () => {
  const port = process.env.MIRA_API_E2E_LOCAL_PORT;
  test.skip(!port, 'Start local Supabase and supply the local database scenario fixtures.');
  if (!port || !/^\d{1,5}$/.test(port)) throw new Error('Expected a local PostgREST port.');
  const role = process.env.MIRA_API_E2E_LOCAL_SERVICE_ROLE;
  if (!role) throw new Error('Local service role is missing.');
  const local = `http://127.0.0.1:${port}/rest/v1/`;
  const id = crypto.randomUUID();
  async function write(path: string, method: string, payload: object) {
    const response = await fetch(local + path, {
      method,
      headers: { apikey: role!, authorization: `Bearer ${role}`, 'content-type': 'application/json',
        prefer: 'return=representation' },
      body: JSON.stringify(payload),
    });
    return { status: response.status, body: await response.json() };
  }
  const row = `mira_generation_jobs?id=eq.${id}`;
  const enqueue = await write('rpc/mira_enqueue', 'POST', {
    p_id: id, p_workspace: '10000000-0000-4000-8000-000000000001', p_creator: creatorID,
    p_member: '10000000-0000-4000-8000-000000000003', p_revision: 1, p_input: input,
  });
  expect(enqueue.status).toBe(200);
  const short = await write('rpc/mira_claim', 'POST', { p_id: id, p_lease_seconds: 89 });
  expect(short.status).toBe(400);
  expect(short.body.message).toBe('mira_lease_too_short');
  const skippedClaim = await write(row, 'PATCH', { status: 'succeeded' });
  expect(skippedClaim.status).toBe(400);
  expect(skippedClaim.body.message).toBe('mira_invalid_job_transition');
  const claim = await write('rpc/mira_claim', 'POST', { p_id: id, p_lease_seconds: 120 });
  expect(claim.status).toBe(200);
  expect(claim.body[0].status).toBe('running');
  expect(claim.body[0].attempts).toBe(1);
  const saved = await write(row, 'PATCH', { status: 'succeeded' });
  expect(saved.status).toBe(200);
  expect(saved.body[0].status).toBe('succeeded');
  const reopened = await write(row, 'PATCH', { status: 'queued' });
  expect(reopened.status).toBe(400);
  expect(reopened.body.message).toBe('mira_invalid_job_transition');
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
  expect(board.shots[0].frameType).toBe('headShoulders');

  const legacyShot = { ...board.shots[1] };
  delete legacyShot.distance;
  delete legacyShot.framing;
  delete legacyShot.frameType;
  const revision = {
    ...storyboardInput, operation: 'reviseShot', targetShotID: board.shots[0].id,
    storyboard: { ...board, shots: [board.shots[0], legacyShot] },
  };
  expect((await run(revision, 'wrong-target')).state).toBe('failed');
  expect((await run(revision, 'missing-frame')).state).toBe('failed');
  const revised = await run(revision);
  expect(revised.state).toBe('succeeded');
  const shots = revised.output.storyboard.shots;
  expect(shots).toHaveLength(2);
  expect(shots[0].id).toBe(revision.targetShotID);
  expect(shots[0].distance).toBe('Two big steps');
  expect(shots[0].framing).toBe('Waist up');
  expect(JSON.stringify(shots[1])).toBe(JSON.stringify(legacyShot));
});

const todayInput = { ...input, operation: 'todayIdea', angle: 'Show my usual breakfast',
  profile: { ...input.profile, name: 'PRIVATE_PROFILE_MARKER' },
  request: 'PRIVATE_REQUEST_MARKER' };

async function until<T>(read: () => Promise<T>, ready: (value: T) => boolean): Promise<T> {
  const deadline = Date.now() + 5_000;
  let value = await read();
  while (!ready(value) && Date.now() < deadline) {
    await new Promise(resolve => setTimeout(resolve, 25));
    value = await read();
  }
  return value;
}

async function tick(id: string) {
  const result = await until(
    () => fetch(`${base}/tick`, { method: 'POST', headers: { 'x-fixture-job': id } }),
    response => response.status === 204,
  );
  expect(result.status).toBe(204);
}

test('the Today response advances on completed streamed sections and keeps its legacy fields', async () => {
  const id = crypto.randomUUID();
  const mode = 'd2-stream';
  const { body } = await call(id, 'start', 'openai', mode, true, true, todayInput);
  expect(body.job.id).toBe(id);
  expect(body.job.inputRevision).toBe(1);
  expect(body.job.input).toEqual(todayInput);
  expect(body.job.state).toBe('working');
  expect(body.job.phase).toBe('queued');
  expect(body.job.step).toBeUndefined();
  const status = async () => (await call(id, 'status', 'openai', mode)).body.job;
  for (const step of ['idea_ready', 'script_ready', 'storyboard_ready']) {
    await tick(id);
    const job = await until(status, result => result.step === step);
    expect(job.step).toBe(step);
    expect(job.state).toBe('working');
    expect(job.phase).toBe('running');
    expect(job.output).toBeUndefined();
  }
  await tick(id);
  const job = await until(status, result => result.state === 'succeeded');
  expect(job.phase).toBe('succeeded');
  expect(job.step).toBe('storyboard_ready');
  expect(job.output.ideas[0].visual).toContain('🥣');
  expect(job.output.storyboard.shots).toHaveLength(3);
  expect(job.error).toBeUndefined();
  expect(job.pictures).toBeUndefined();
  expect((await observations()).stepWrites.filter(write => write.id === id).map(write => write.step))
    .toEqual(['idea_ready', 'script_ready', 'storyboard_ready']);
});

test('a cut Today stream keeps partial text out of output and returns the existing retry phase', async () => {
  const id = crypto.randomUUID();
  const mode = 'd2-cut';
  await call(id, 'start', 'openai', mode, true, true, todayInput);
  await tick(id);
  const status = async () => (await call(id, 'status', 'openai', mode)).body.job;
  expect((await until(status, job => job.step === 'idea_ready')).step).toBe('idea_ready');
  await tick(id);
  const job = await until(status, result => result.phase === 'waiting_to_retry');
  expect(job.state).toBe('working');
  expect(job.phase).toBe('waiting_to_retry');
  expect(job.step).toBeUndefined();
  expect(job.output).toBeUndefined();
  expect(job.pictures).toBeUndefined();
});

function pictureCalls(mode: string) {
  return observations().then(result => result.calls.filter(call =>
    call.mode === mode && call.url.endsWith('/images/generations')));
}

test('a successful Today card returns independent picture states and signed URLs', async () => {
  const id = crypto.randomUUID();
  const mode = 'd2-mixed';
  await call(id, 'start', 'openai', mode, true, true, todayInput);
  const status = async (token: boolean | string = true) => call(id, 'status', 'openai', mode, true, token);
  const [first, second] = await Promise.all([status(), status()]);
  expect(first.body.job.state).toBe('succeeded');
  expect(second.body.job.state).toBe('succeeded');
  expect(first.body.job.pictures).toHaveLength(3);
  const { body } = await status();
  const pictures = body.job.pictures;
  expect(body.job.phase).toBe('succeeded');
  expect(pictures.map((picture: { shotID: string }) => picture.shotID))
    .toEqual(body.job.output.storyboard.shots.map((shot: { id: string }) => shot.id));
  expect(pictures.map((picture: { status: string }) => picture.status)).toEqual(['ready', 'failed', 'ready']);
  expect(pictures[0].url).toContain('/storage/v1/object/sign/mira-shot-pictures/');
  expect(new URL(pictures[0].url).searchParams.get('ttl')).toBe('3600');
  expect(Object.keys(pictures[0]).sort()).toEqual(['shotID', 'status', 'url']);
  expect(pictures[1].url).toBeUndefined();
  expect((await status(false)).status).toBe(401);
  expect((await status('fixture-other-member')).status).toBe(404);
  const requests = await pictureCalls(mode);
  expect(requests).toHaveLength(3);
  for (const { payload } of requests) {
    expect(payload?.model).toBe('gpt-image-2.6-flare');
    expect(payload?.size).toBe('720x1280');
    expect(payload?.n).toBe(1);
    expect(payload?.prompt).toContain('Location: Home');
    expect(payload?.prompt).not.toContain('PRIVATE_');
    expect(payload?.prompt).not.toContain('Here is my breakfast');
    expect(Object.keys(payload!).sort()).toEqual(['complexity', 'model', 'n', 'output_compression',
      'output_format', 'prompt', 'quality', 'size']);
  }
});

test('a retry recovers uploaded pictures after a lost ready update without a second provider call', async () => {
  const id = crypto.randomUUID();
  const mode = 'd2-lost-picture-write';
  await call(id, 'start', 'openai', mode, true, true, todayInput);
  const status = async () => (await call(id, 'status', 'openai', mode)).body.job;
  const pending = await status();
  expect(pending.pictures.map((picture: { status: string }) => picture.status)).toEqual(['pending', 'pending', 'pending']);
  await fetch(`${base}/expire-pictures`, { method: 'POST', headers: { 'x-fixture-job': id } });
  const recovered = await status();
  expect(recovered.pictures.map((picture: { status: string }) => picture.status)).toEqual(['ready', 'ready', 'ready']);
  expect((await pictureCalls(mode))).toHaveLength(3);
});

test('a short remaining picture lease refuses every provider call and preserves the card', async () => {
  const id = crypto.randomUUID();
  const mode = 'd2-short-picture';
  await call(id, 'start', 'openai', mode, true, true, todayInput);
  await call(id, 'status', 'openai', mode);
  const { body } = await call(id, 'status', 'openai', mode);
  expect(body.job.state).toBe('succeeded');
  expect(body.job.pictures.map((picture: { status: string }) => picture.status)).toEqual(['failed', 'failed', 'failed']);
  expect(await pictureCalls(mode)).toHaveLength(0);
});

function localSupabase() {
  const port = process.env.MIRA_API_E2E_LOCAL_PORT;
  test.skip(!port, 'Start local Supabase and supply the local database scenario fixtures.');
  const role = process.env.MIRA_API_E2E_LOCAL_SERVICE_ROLE;
  if (!port || !/^\d{1,5}$/.test(port) || !role) throw new Error('Local Supabase is missing.');
  return {
    url: `http://127.0.0.1:${port}`,
    headers: { apikey: role, authorization: `Bearer ${role}` },
  };
}

test('local Storage serves only a signed picture from the authenticated card status', async () => {
  const local = localSupabase();
  const anon = process.env.MIRA_API_E2E_LOCAL_ANON;
  if (!anon) throw new Error('Local anon key is missing.');
  const id = crypto.randomUUID();
  const mode = 'd2-local-storage';
  expect((await call(id, 'start', 'openai', mode, true, true, todayInput)).status).toBe(200);
  const status = () => call(id, 'status', 'openai', mode);
  const first = await status();
  expect(first.body.job.state).toBe('succeeded');
  expect(first.headers.get('cache-control')).toBe('no-store');
  expect(first.body.job.pictures.map((entry: { status: string }) => entry.status))
    .toEqual(['pending', 'pending', 'pending']);
  const result = await status();
  const entries = result.body.job.pictures;
  expect(entries.map((entry: { status: string }) => entry.status)).toEqual(['ready', 'failed', 'ready']);
  expect(entries[1].url).toBeUndefined();
  expect((await pictureCalls(mode))).toHaveLength(3);
  const signed = new URL(entries[0].url);
  expect(signed.origin === local.url && signed.pathname.includes('/object/sign/') &&
    signed.searchParams.has('token')).toBe(true);
  const image = await fetch(signed);
  expect(image.status).toBe(200);
  expect(image.headers.get('content-type')).toContain('image/jpeg');
  expect(new Uint8Array(await image.arrayBuffer())[0]).toBe(0xff);
  const anonymous = { apikey: anon, authorization: `Bearer ${anon}` };
  const object = signed.pathname.replace('/object/sign/', '/object/');
  const [direct, publicObject, sign, upload] = await Promise.all([
    fetch(local.url + object, { headers: anonymous }),
    fetch(local.url + object.replace('/object/', '/object/public/'), { headers: anonymous }),
    fetch(local.url + signed.pathname, { method: 'POST', headers: { ...anonymous, 'content-type': 'application/json' },
      body: JSON.stringify({ expiresIn: 3600 }) }),
    fetch(local.url + object + '.unauthorized.jpg', { method: 'POST',
      headers: { ...anonymous, 'content-type': 'image/jpeg' }, body: new Uint8Array([0xff, 0xd8, 0xff, 0xd9]) }),
  ]);
  expect([direct, publicObject, sign, upload].every(response => !response.ok)).toBe(true);

  const lostUpdate = await fetch(`${local.url}/rest/v1/mira_shot_pictures?job_id=eq.${id}&shot_id=eq.${entries[0].shotID}`, {
    method: 'PATCH', headers: { ...local.headers, 'content-type': 'application/json' },
    body: JSON.stringify({ status: 'generating', lease_until: new Date(0).toISOString() }),
  });
  expect(lostUpdate.status).toBe(204);
  expect((await status()).body.job.pictures[0].status).toBe('ready');
  expect((await pictureCalls(mode))).toHaveLength(3);
});

test('local PostgREST reserves at most 30 pictures across concurrent cards without using text slots', async () => {
  const local = localSupabase();
  async function write(path: string, method: string, payload: object) {
    const response = await fetch(`${local.url}/rest/v1/${path}`, {
      method, headers: { ...local.headers, 'content-type': 'application/json', prefer: 'return=representation' },
      body: JSON.stringify(payload),
    });
    return { status: response.status, body: await response.json() };
  }
  const member = crypto.randomUUID();
  const workspace = '10000000-0000-4000-8000-000000000001';
  expect((await write('members', 'POST', {
    id: member, workspace_id: workspace, display_name: 'D2 cap fixture', role: 'creator',
  })).status).toBe(201);
  const enqueue = (id: string, jobInput: object) => write('rpc/mira_enqueue', 'POST', {
    p_id: id, p_workspace: workspace, p_creator: creatorID, p_member: member, p_revision: 1, p_input: jobInput,
  });
  const cards: string[] = [];
  for (let card = 0; card < 7; card++) {
    const id = crypto.randomUUID();
    cards.push(id);
    expect((await enqueue(id, todayInput)).status).toBe(200);
    expect((await write('rpc/mira_claim', 'POST', { p_id: id, p_lease_seconds: 90 })).status).toBe(200);
    expect((await write(`mira_generation_jobs?id=eq.${id}`, 'PATCH', {
      status: 'succeeded', picture_count: 5, created_at: new Date(Date.now() - 120_000).toISOString(),
      output: { storyboard: { shots: Array.from({ length: 5 }, () => ({ id: crypto.randomUUID() })) } },
    })).status).toBe(200);
  }
  const jobs = await Promise.all(cards.map(p_job_id =>
    write('rpc/mira_claim_shot_pictures', 'POST', { p_job_id, p_lease_id: crypto.randomUUID(), p_lease_seconds: 125 })));
  expect(jobs.every(job => job.status === 200)).toBe(true);
  const rows = jobs.flatMap(job => job.body);
  expect(rows.filter(row => row.status === 'generating' && row.reserved_at)).toHaveLength(30);
  expect(rows.filter(row => row.status === 'failed' && row.reserved_at === null)).toHaveLength(5);
  for (let slot = 0; slot < 3; slot++) expect((await enqueue(crypto.randomUUID(), input)).status).toBe(200);
  const fourth = await enqueue(crypto.randomUUID(), input);
  expect(fourth.body.message).toBe('too_many_active_jobs');
});

test('the deployed Mira endpoint returns filming fields for a solo storyboard', async () => {
  test.skip(process.env.MIRA_API_E2E_LIVE !== '1', 'Supply credentials for an isolated live QA workspace.');
  const liveCreator = process.env.MCO_LIVE_CREATOR_ID;
  const deviceToken = process.env.MCO_LIVE_DEVICE_TOKEN;
  const publishableKey = process.env.MCO_SUPABASE_PUBLISHABLE_KEY;
  const shotPath = process.env.MIRA_API_E2E_LIVE_SHOT_PATH;
  if (!liveCreator || !deviceToken || !publishableKey || !shotPath) {
    throw new Error('Live Mira QA session or shot evidence path is missing.');
  }

  const id = crypto.randomUUID();
  async function request(action: 'start' | 'status', extra = {}) {
    const response = await fetch('https://zogvvrxhiwozjmufvddu.supabase.co/functions/v1/mira-generation', {
      method: 'POST',
      headers: {
        'content-type': 'application/json', 'x-mco-device-token': deviceToken!,
        apikey: publishableKey!, authorization: `Bearer ${publishableKey}`,
      },
      body: JSON.stringify({ action, id, creatorID: liveCreator, ...extra }),
      signal: AbortSignal.timeout(10_000),
    });
    const body = await response.json();
    if (!response.ok) throw new Error(`Mira ${action} HTTP ${response.status}: ${body.error ?? 'unknown'}`);
    return body.job;
  }

  let job = await request('start', {
    consentVersion: 1,
    inputRevision: 1,
    input: {
      ...input,
      operation: 'storyboard',
      constraints: { ...input.constraints, equipment: 'Phone, table and books', reelSeconds: 20 },
      request: 'A simple breakfast reel. I am filming alone at home. Use short, clear English.',
      script: {
        id: crypto.randomUUID(), hook: 'Here is my quick breakfast.',
        spoken: 'I put yogurt in a bowl. I add sliced banana and oats. That is all I need.',
        caption: 'A quick breakfast at home', durationSeconds: 20, language: 'English',
      },
    },
  });
  await expect.poll(async () => {
    job = await request('status');
    return job.state !== 'working' || Boolean(job.error);
  }, { timeout: 50_000, interval: 2_000 }).toBe(true);
  if (job.state !== 'succeeded') throw new Error(job.error ?? `Mira job state: ${job.state}`);
  expect(job.phase).toBe('succeeded');
  const shots = job.output.storyboard?.shots;
  expect(shots?.length ?? 0).toBeGreaterThan(0);
  for (const shot of shots) {
    expect(shot.distance.trim().length).toBeGreaterThan(0);
    expect(shot.framing.trim().length).toBeGreaterThan(0);
  }
  await writeFile(shotPath, JSON.stringify(shots[0], null, 2) + '\n', { mode: 0o600 });
});

const todayAngles = [
  'A short movement to demonstrate from HYROX training',
  'An everyday healthy Indian food idea',
  'A mindset tip for keeping up a habit',
];

test('three Today inputs go through the adapters and incomplete cards fail closed', async () => {
  const before = (await observations()).calls.length;
  const providers = ['openai', 'deepseek', 'gemini'];
  const cards = await Promise.all(todayAngles.map(async (angle, index) => {
    const id = crypto.randomUUID();
    const provider = providers[index];
    const jobInput = { ...input, operation: 'todayIdea', angle };
    expect((await call(id, 'start', provider, 'ok', true, true, jobInput)).status).toBe(200);
    const { body } = await call(id, 'status', provider);
    expect(body.job.state).toBe('succeeded');
    const card = body.job.output;
    expect(card.ideas).toHaveLength(1);
    expect(card.storyboard.sourceScriptID).toBe(card.script.id);
    expect(card.storyboard.shots).toHaveLength(3);
    return card;
  }));
  expect(new Set(cards.map(card => card.ideas[0].title)).size).toBe(3);
  expect((await observations()).calls.length - before).toBe(3);
  for (const mode of ['missing-frame', 'wrong-source', 'wrong-duration', 'repeat']) {
    const id = crypto.randomUUID();
    const angle = todayAngles[0];
    const jobInput = { ...input, operation: 'todayIdea', angle, recentIdeas: mode === 'repeat' ? [angle] : [] };
    expect((await call(id, 'start', 'openai', mode, true, true, jobInput)).status).toBe(200);
    const { body } = await call(id, 'status', 'openai');
    expect(body.job.state).toBe('failed');
    expect(body.job.output).toBeUndefined();
  }
});

test('the deployed Mira endpoint generates three Today cards in one parallel run', async () => {
  test.skip(process.env.MIRA_API_E2E_LIVE_TODAY !== '1', 'Use the isolated live QA workspace for this run.');
  const liveCreator = process.env.MCO_LIVE_CREATOR_ID;
  const deviceToken = process.env.MCO_LIVE_DEVICE_TOKEN;
  const publishableKey = process.env.MCO_SUPABASE_PUBLISHABLE_KEY;
  const evidencePath = process.env.MIRA_API_E2E_LIVE_TODAY_PATH;
  if (!liveCreator || !deviceToken || !publishableKey || !evidencePath) {
    throw new Error('Live Mira QA session or card evidence path is missing.');
  }
  const began = Date.now();
  const records = await Promise.all(todayAngles.map(async (angle) => {
    const id = crypto.randomUUID();
    async function request(action: 'start' | 'status') {
      const response = await fetch('https://zogvvrxhiwozjmufvddu.supabase.co/functions/v1/mira-generation', {
        method: 'POST',
        headers: {
          'content-type': 'application/json', 'x-mco-device-token': deviceToken!,
          apikey: publishableKey!, authorization: `Bearer ${publishableKey}`,
        },
        body: JSON.stringify({ action, id, creatorID: liveCreator, ...(action === 'start' ? {
          consentVersion: 1,
          inputRevision: 0,
          input: {
            ...input, operation: 'todayIdea', angle,
            profile: { ...input.profile, themes: 'Fitness and HYROX, healthy Indian food, mindset' },
            constraints: { ...input.constraints, equipment: 'Phone, sturdy table and books', reelSeconds: 24 },
            request: 'I am filming at home alone today. Use short, plain English.',
            recentIdeas: ['Three reasons I started training', 'My usual yogurt breakfast'],
          },
        } : {}) }),
        signal: AbortSignal.timeout(8_000),
      });
      const body = await response.json();
      if (!response.ok) throw new Error(`Mira ${action} HTTP ${response.status}: ${body.error ?? 'unknown'}`);
      return body.job;
    }
    try {
      let job = await request('start');
      const admittedAt = Date.now() - began;
      while (job.state === 'working' && !job.error && Date.now() - began < 62_000) {
        await new Promise(resolve => setTimeout(resolve, 1_000));
        job = await request('status');
      }
      const output = job.output;
      const elapsedSeconds = (Date.now() - began) / 1_000;
      return {
        id, angle, admittedAt, elapsedSeconds, state: job.state, error: job.error,
        bytes: output ? Buffer.byteLength(JSON.stringify(output)) : 0, output,
      };
    } catch (error) {
      return { id, angle, elapsedSeconds: (Date.now() - began) / 1_000, state: 'request_failed',
        error: error instanceof Error ? error.message : String(error), bytes: 0, output: undefined };
    }
  }));
  await writeFile(evidencePath, `${JSON.stringify(records, null, 2)}\n`, { mode: 0o600 });
  const frameTypes = ['face', 'headShoulders', 'halfBody', 'fullBody', 'side', 'closeUp'];
  for (const record of records) {
    expect(record.elapsedSeconds).toBeLessThanOrEqual(60);
    expect(record.state).toBe('succeeded');
    const output = record.output;
    expect(output.ideas).toHaveLength(1);
    expect(output.conflicts).toHaveLength(0);
    expect(output.storyboard.sourceScriptID).toBe(output.script.id);
    const shots = output.storyboard.shots;
    expect(shots.length).toBeGreaterThanOrEqual(3);
    expect(shots.length).toBeLessThanOrEqual(5);
    expect(Math.abs(shots.reduce((seconds: number, shot: { editedSeconds: number }) => seconds + shot.editedSeconds, 0)
      - output.script.durationSeconds)).toBeLessThanOrEqual(5);
    for (const shot of shots) {
      expect(frameTypes).toContain(shot.frameType);
      for (const field of ['distance', 'framing', 'placement']) expect(shot[field].trim().length).toBeGreaterThan(0);
    }
  }
  expect(new Set(records.map(({ output }) => output.ideas[0].title.trim().toLowerCase())).size).toBe(3);
});
