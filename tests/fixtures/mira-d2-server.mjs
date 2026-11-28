import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';

const port = Number(process.env.MIRA_D2_FIXTURE_PORT ?? 18796);
const origin = process.env.MIRA_E2E_D2_ENDPOINT;
const jobs = new Map();
const preview = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAADYAAABgCAIAAADZ8BZgAAAAw0lEQVR4nO3OsQ0CQQxE0SuFniiBAIkS6I0WaIeUhBS4tX1aa/WkH8+87XS7Nm+bLkBERETsFSJilxARu4SI2CXEJsTX8/6t+cQfuEJokLgTVwKNEAO+jHKYGPaFlWPEpC+mXItY4gsoFyIW+kaViIiIiIgxYq1y/+lyxCrl0OOKxLxy9C5CzCgDX0FiTBk7ihOHoJmLLPEvND9eQzw6RMQuISJ+elzOR4eIiIiIiIiIiIiIiIiIiIiIiIiIiIiIOJn4BkTalCNcrb77AAAAAElFTkSuQmCC', 'base64');

function output(input, card) {
  const language = input.profile.language;
  const { location, filmingMinutes } = input.constraints;
  const title = ['A quiet breakfast', 'A table by the window', 'A short walk'][card - 1];
  const script = {
    id: randomUUID(), hook: 'Here’s how I start the day.',
    spoken: 'Here’s how I start the day.\nHere is one thing I do every morning.',
    caption: 'My morning routine.', durationSeconds: 15, language,
  };
  const words = ["Here's how I start the day.", 'Here is one thing I do every morning.', ''];
  const shots = ['Set the bowl down', 'Add the fruit', 'Show the bowl'].map((action, index) => ({
    id: randomUUID(), purpose: action, editedSeconds: 5, recordingSeconds: 7, location,
    props: 'Bowl and fruit', placement: 'Put the phone on the table.', distance: 'One arm away',
    framing: 'Hands and bowl', frameType: 'closeUp', action, words: words[index], voiceover: false,
    onScreenText: '', simplerAlternative: 'Keep the phone still.',
  }));
  return {
    ideas: [{ id: randomUUID(), title, hook: script.hook, visual: shots[0].action,
      fit: 'You can film alone.', filmingMinutes: Math.min(10, filmingMinutes), setup: 'Use the table.' }],
    script, storyboard: { id: randomUUID(), sourceScriptID: script.id, requirementsRevision: 0, shots, mappings: [] },
    conflicts: [],
  };
}

const json = (response, value, code = 200) => {
  response.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify(value));
};

async function handle(request, response) {
  const path = new URL(request.url, 'http://fixture.invalid').pathname;
  const parts = path.split('/');
  if (request.method === 'GET' && parts.at(-1) === 'health') return json(response, { ready: true });
  if (request.method === 'GET' && parts.at(-3) === 'image') {
    const job = jobs.get(parts.at(-2));
    if (!job) return json(response, {}, 404);
    if (parts.at(-1) === 'expired') {
      job.expiredGets += 1;
      return json(response, {}, 403);
    }
    job.freshGets += 1;
    response.writeHead(200, { 'Content-Type': 'image/png', 'Cache-Control': 'no-store' });
    return response.end(preview);
  }

  if (request.method !== 'POST') return json(response, {}, 405);
  let raw = '';
  for await (const part of request) raw += part;
  const body = JSON.parse(raw);
  if (path === '/control') {
    if (body.begin) {
      for (const [id, entry] of jobs) {
        if (entry.job.input.request === body.scenario) jobs.delete(id);
      }
    }
    const matching = [...jobs.values()].filter(entry => entry.job.input.request === body.scenario);
    for (const entry of matching) {
      if (body.card && entry.card !== body.card) continue;
      if (body.step) entry.step = body.step;
      if (body.finish) entry.finished = true;
      if (body.previews) entry.previews = body.previews;
    }
    return json(response, matching.map(({ card, starts, prematureOptIns, optedIn, expiredGets, freshGets, refreshes }) => ({
      card, starts, prematureOptIns, optedIn, expiredGets, freshGets, refreshes,
    })));
  }
  if (!path.endsWith('/functions/v1/mira-generation')) return json(response, {}, 404);
  if (body.action === 'start') {
    if (body.pictures !== undefined || body.input.operation !== 'todayIdea') return json(response, {}, 400);
    const card = body.input.angle.startsWith('A short') ? 1 : body.input.angle.startsWith('A food') ? 2 : 3;
    const id = body.id.toLowerCase();
    if (!jobs.has(id)) {
      jobs.set(id, {
        card, job: { id: body.id, inputRevision: body.inputRevision, input: body.input },
        output: output(body.input, card), finished: false, starts: 0, optedIn: 0, prematureOptIns: 0,
        expiredGets: 0, freshGets: 0, refreshes: 0,
      });
    }
    jobs.get(id).starts += 1;
    if (body.input.request === 'Demo D2 transport' && card === 1 && jobs.get(id).starts === 1) {
      response.writeHead(200, { 'Content-Type': 'application/json', 'Content-Length': '1000' });
      response.write('{"job":', () => response.destroy());
      return;
    }
  }
  const id = body.id.toLowerCase();
  const entry = jobs.get(id);
  if (!entry) return json(response, { error: 'not_found' }, 404);
  const state = body.action === 'cancel' ? 'cancelled' : entry.finished ? 'succeeded' : 'working';
  const job = { ...entry.job, phase: state === 'working' ? 'running' : state, state };
  if (entry.step && entry.job.input.request !== 'Demo D2 legacy') job.step = entry.step;
  if (state === 'succeeded') job.output = entry.output;
  if (body.action === 'status' && body.pictures === true) {
    entry.optedIn += 1;
    if (!entry.finished) entry.prematureOptIns += 1;
    if (entry.previews === 'pending' || entry.previews === 'ready') {
      const [first, second] = entry.output.storyboard.shots;
      const variant = entry.expiredGets ? 'fresh' : 'expired';
      if (entry.previews === 'ready' && variant === 'fresh') entry.refreshes += 1;
      job.pictures = [
        entry.previews === 'pending' ? { shotID: first.id, status: 'pending' }
          : { shotID: first.id, status: 'ready', url: `${origin}/image/${id}/${variant}` },
        { shotID: second.id, status: entry.previews === 'pending' ? 'pending' : 'failed' },
      ];
    }
  }
  return json(response, { job });
}

createServer((request, response) => {
  handle(request, response).catch(() => json(response, { error: 'invalid_fixture_request' }, 400));
}).listen(port, '127.0.0.1');
