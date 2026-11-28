import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import recordedToday from './mira-recorded-today.json' with { type: 'json' };

const port = Number(process.env.MIRA_D2_FIXTURE_PORT ?? 18796);
const origin = process.env.MIRA_E2E_D2_ENDPOINT;
const jobs = new Map();
let e5;
const preview = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAADYAAABgCAIAAADZ8BZgAAAAw0lEQVR4nO3OsQ0CQQxE0SuFniiBAIkS6I0WaIeUhBS4tX1aa/WkH8+87XS7Nm+bLkBERETsFSJilxARu4SI2CXEJsTX8/6t+cQfuEJokLgTVwKNEAO+jHKYGPaFlWPEpC+mXItY4gsoFyIW+kaViIiIiIgxYq1y/+lyxCrl0OOKxLxy9C5CzCgDX0FiTBk7ihOHoJmLLPEvND9eQzw6RMQuISJ+elzOR4eIiIiIiIiIiIiIiIiIiIiIiIiIiIiIOJn4BkTalCNcrb77AAAAAElFTkSuQmCC', 'base64');

function output(input, card) {
  const language = input.profile.language;
  const { location, filmingMinutes } = input.constraints;
  const title = ['A quiet breakfast', 'A table by the window', 'A short walk'][card - 1];
  const pick = input.operation === 'pickIdea';
  const checklist = pick ? input.dealChecklist : undefined;
  const recorded = input.request === 'Demo D2 pictures' && card === 1;
  const script = recorded ? { ...recordedToday.script, id: randomUUID(), language } : {
    id: randomUUID(), hook: 'Here’s how I start the day.',
    spoken: 'Here’s how I start the day.\nHere is one thing I do every morning.',
    caption: 'My morning routine.', durationSeconds: 15, language,
  };
  const words = ["Here's how I start the day.", 'Here is one thing I do every morning.', ''];
  const shots = recorded ? recordedToday.storyboard.shots.map(shot => ({ ...shot, id: randomUUID() }))
    : ['Set the bowl down', 'Add the fruit', 'Show the bowl'].map((action, index) => ({
    id: randomUUID(), purpose: action, editedSeconds: 5, recordingSeconds: 7, location,
    props: 'Bowl and fruit', placement: 'Put the phone on the table.', distance: 'One arm away',
    framing: 'Hands and bowl', frameType: 'closeUp', action, words: words[index], voiceover: false,
    onScreenText: '', simplerAlternative: 'Keep the phone still.',
  }));
  const mappings = checklist?.items.map(item => ({
    requirementID: item.id, shotIDs: [shots[2].id], scriptExcerpt: '',
  })) ?? [];
  if (checklist) {
    shots[2].onScreenText = checklist.items.filter(item => item.kind === 'onScreenText')
      .map(item => item.requiredText ?? '').filter(Boolean).join(' ');
  }
  return {
    ideas: [{ id: randomUUID(), title, hook: script.hook, visual: shots[0].action,
      fit: 'You can film alone.', filmingMinutes: Math.min(10, filmingMinutes), setup: 'Use the table.' }],
    script, storyboard: {
      id: randomUUID(), sourceScriptID: script.id, requirementsRevision: checklist?.revision ?? 0, shots, mappings,
    },
    conflicts: [],
    ...(pick ? { reason: 'You can film this in one place with things you already have.' } : {}),
  };
}

const json = (response, value, code = 200) => {
  response.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
  response.end(JSON.stringify(value));
};

const e5Snapshots = [
  { followers: 1200, reach7d: 700 },
  { followers: 1212, reach7d: 690, saves7d: 15, topPosts: [
    { caption: 'A mango bowl in one minute', saves: 11, likes: 38 },
    { caption: 'My walk before breakfast', saves: 4, comments: 0 },
  ] },
];

function dailyNote(body, response) {
  if (body.action === 'start') {
    e5.starts.push(body.id);
    if (!e5.job) {
      const type = e5.action;
      const target = type === 'continueReel' ? body.input.openReels[0] : body.input.openDeals[0];
      if (['continueReel', 'openDeal'].includes(type) && !target) return json(response, {}, 400);
      const buttonText = { makeIdea: 'Make an idea', continueReel: 'Continue this Reel', openDeal: 'Open this deal', none: '' }[type];
      const noticed = body.input.snapshots.length ? 'You have 1,212 followers.' : 'Here is what matters today.';
      e5.job = { id: body.id, inputRevision: body.inputRevision, input: body.input,
        output: { dailyNote: { noticed, action: { type, ...(buttonText && target && type !== 'makeIdea' ? { id: target.id } : {}) }, buttonText } } };
      e5.calls += 1;
    }
    return json(response, { job: { ...e5.job, state: 'working', output: undefined } });
  }
  e5.statuses.push(body.id);
  const state = e5.fail ? 'failed' : 'succeeded';
  return json(response, { job: { ...e5.job, state, output: e5.fail ? undefined : e5.job.output } });
}

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
    if (body.scenario === 'E5') {
      if (body.begin) e5 = { action: body.action, insights: body.insights, fail: body.fail,
        calls: 0, starts: [], statuses: [], picks: [] };
      return json(response, e5 ?? {}, e5 ? 200 : 404);
    }
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
    return json(response, matching.map(entry => {
      const { card, starts, prematureOptIns, optedIn, expiredGets, freshGets, refreshes } = entry;
      return { card, starts, prematureOptIns, optedIn, expiredGets, freshGets, refreshes,
        dealChecklist: entry.job.input.dealChecklist };
    }));
  }
  if (path.endsWith('/functions/v1/instagram-insights') && e5) {
    if (e5.insights === 'missing') return json(response, { state: 'no_data' });
    if (e5.insights === 'legacy') {
      return json(response, { state: 'ready', source: 'api', metrics: [
        { id: 'followers', label: 'Followers', value: '1,212', delta: '+12 this week' },
      ] });
    }
    return json(response, { state: 'ready', source: 'api', snapshots: e5Snapshots });
  }
  if (!path.endsWith('/functions/v1/mira-generation')) return json(response, {}, 404);
  if (e5 && (body.input?.operation === 'dailyNote' || body.id === e5.job?.id)) return dailyNote(body, response);
  if (body.action === 'start') {
    const e5Pick = e5 && ['Make one like this', 'Give me a Reel idea for today.'].includes(body.input.request);
    const pick = body.input.operation === 'pickIdea' && (body.input.request === 'Demo E2 pick' || e5Pick);
    if (body.pictures !== undefined || (!pick && body.input.operation !== 'todayIdea')) return json(response, {}, 400);
    const card = pick
      ? ['A quiet breakfast', 'A table by the window', 'A short walk'].findIndex(title => !body.input.avoid.includes(title)) + 1
      : body.input.angle.startsWith('A short') ? 1 : body.input.angle.startsWith('A food') ? 2 : 3;
    if (!card) return json(response, {}, 400);
    const id = body.id.toLowerCase();
    if (!jobs.has(id)) {
      jobs.set(id, {
        card, job: { id: body.id, inputRevision: body.inputRevision, input: body.input },
        output: output(body.input, card), finished: Boolean(e5Pick), starts: 0, optedIn: 0, prematureOptIns: 0,
        expiredGets: 0, freshGets: 0, refreshes: 0,
      });
    }
    if (pick && e5Pick) e5.picks.push(body.input);
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
    if (entry.finished && entry.job.input.operation === 'pickIdea') {
      job.pictures = entry.output.storyboard.shots.map(shot => ({
        shotID: shot.id, status: 'ready', url: `${origin}/image/${id}/fresh`,
      }));
    } else if (entry.previews === 'pending' || entry.previews === 'ready') {
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
