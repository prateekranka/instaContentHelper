import { createClient } from "jsr:@supabase/supabase-js@2";
import { handleMira } from '../../supabase/functions/mira-generation/index.ts';
import { generate } from '../../supabase/functions/mira-generation/provider.ts';
import { sha256Hex } from '../../supabase/functions/_shared/device-auth.ts';

const localPort = Deno.env.get('MIRA_API_E2E_LOCAL_PORT');
const localRole = Deno.env.get('MIRA_API_E2E_LOCAL_SERVICE_ROLE');
const localAdmin = localPort && /^\d{1,5}$/.test(localPort) && localRole
  ? createClient(`http://127.0.0.1:${localPort}`, localRole, {
    auth: { persistSession: false, autoRefreshToken: false },
  }) : undefined;
const workspaceID = '10000000-0000-4000-8000-000000000001';
const creatorID = '10000000-0000-4000-8000-000000000002';
const memberID = '10000000-0000-4000-8000-000000000003';
const otherMember = '10000000-0000-4000-8000-000000000004';
const otherTokenHash = await sha256Hex('fixture-other-member');
const tokenHash = await sha256Hex('fixture-device-token');
type Row = Record<string, unknown>;
const jobs = new Map<string, Row>();
const pictures: Row[] = [];
const savedPictures = new Set<string>();
const streamGates = new Map<string, (() => void)[]>();
const stepWrites: { id: string; step: unknown }[] = [];
const fixtureLeaseMs = new Map([
  ['lost-expired-claim', -1],
  ['remaining-lease-short', 74_000],
]);
const calls: { url: string; model: string; mode: string; payload?: Row }[] = [];
const tables: Record<string, Row[]> = {
  device_installations: [
    { id: 'installation', workspace_id: workspaceID, member_id: memberID, token_hash: tokenHash, revoked_at: null },
    { id: 'other-installation', workspace_id: workspaceID, member_id: otherMember, token_hash: otherTokenHash, revoked_at: null },
  ],
  members: [memberID, otherMember].map(id => ({ id, workspace_id: workspaceID, role: 'creator', status: 'active' })),
  creators: [{ id: creatorID, workspace_id: workspaceID }],
};

class Query {
  private conditions: ((row: Row) => boolean)[] = [];
  private changes?: Row;
  private many = false;
  constructor(private table: string, private mode: string) {}
  select(_columns: string) { return this; }
  eq(key: string, value: unknown) { this.conditions.push((row) => row[key] === value); return this; }
  is(key: string, value: unknown) { return this.eq(key, value); }
  in(key: string, values: unknown[]) { this.conditions.push((row) => values.includes(row[key])); return this; }
  gt(key: string, value: string) { this.conditions.push((row) => String(row[key]) > value); return this; }
  order(_key: string) { this.many = true; return this; }
  update(changes: Row) { this.changes = changes; return this; }
  result() {
    const rows = this.table === 'mira_generation_jobs' ? [...jobs.values()] :
      this.table === 'mira_shot_pictures' ? pictures : tables[this.table] ?? [];
    const matches = rows.filter((item) => this.conditions.every((condition) => condition(item)));
    if (this.changes?.status === 'ready' && this.mode === 'd2-lost-picture-write') {
      return { data: null, error: new Error('fixture_lost_picture_write') };
    }
    for (const row of matches) {
      if (this.changes?.step) stepWrites.push({ id: String(row.id), step: this.changes.step });
      if (this.changes) Object.assign(row, this.changes);
    }
    return { data: structuredClone(this.many ? matches : matches[0] ?? null), error: null };
  }
  maybeSingle() { return Promise.resolve(this.result()); }
  then(resolve: (value: unknown) => void, reject: (reason: unknown) => void) {
    return Promise.resolve(this.result()).then(resolve, reject);
  }
}

const admin = {
  storage: {
    from(_bucket: string) {
      return {
        upload(path: string, _data: Uint8Array, options: Row) {
          if (options.upsert !== false || savedPictures.has(path)) return { error: 'duplicate' };
          savedPictures.add(path);
          return { error: null };
        },
        createSignedUrl(path: string, ttl: number) {
          return { data: { signedUrl: `https://fixture.invalid/storage/v1/object/sign/mira-shot-pictures/${path}?token=fixture&ttl=${ttl}` }, error: null };
        },
      };
    },
  },
  rpc(name: string, args: Row, mode: string) {
    if (name === 'mira_enqueue') {
      const id = String(args.p_id);
      const row = { id, workspace_id: args.p_workspace, creator_id: args.p_creator, member_id: args.p_member,
        input_revision: args.p_revision, input: args.p_input, status: 'queued', attempts: 0 };
      jobs.set(id, row);
      return Promise.resolve({ data: row, error: null });
    }
    if (name === 'mira_claim') {
      const row = jobs.get(String(args.p_id));
      const now = Date.now();
      const ready = row && Number(row.attempts) < 3 &&
        (!row.next_attempt_at || Date.parse(String(row.next_attempt_at)) <= now) &&
        (row.status === 'queued' || (row.status === 'running' && Date.parse(String(row.lease_until)) <= now));
      if (!ready) return Promise.resolve({ data: [], error: null });
      Object.assign(row, {
        status: 'running', step: null, lease_id: crypto.randomUUID(), attempts: Number(row.attempts) + 1,
        lease_until: new Date(now + (fixtureLeaseMs.get(mode) ?? Number(args.p_lease_seconds) * 1000)).toISOString(),
      });
      if (mode === 'lost-claim' || mode === 'lost-expired-claim') {
        return Promise.resolve({ data: [], error: null });
      }
      return Promise.resolve({ data: [structuredClone(row)], error: null });
    }
    if (name === 'mira_claim_shot_pictures') {
      const job = jobs.get(String(args.p_job_id))!;
      const now = Date.now();
      let rows = pictures.filter((row) => row.job_id === job.id);
      if (!rows.length) {
        const shots = (job.output as { storyboard: { shots: { id: string }[] } }).storyboard.shots;
        rows = shots.slice(0, Number(job.picture_count)).map((shot) => ({
          job_id: job.id, shot_id: shot.id, object_path: `${job.id}/${shot.id}.jpg`,
          status: 'generating', lease_id: args.p_lease_id,
          lease_until: new Date(now + (mode === 'd2-short-picture' ? 119_000 : Number(args.p_lease_seconds) * 1000)).toISOString(),
        }));
        pictures.push(...rows);
      }
      for (const row of rows) {
        if (row.status === 'generating' && Date.parse(String(row.lease_until)) <= now) {
          row.status = savedPictures.has(String(row.object_path)) ? 'ready' : 'failed';
        }
      }
      return Promise.resolve({ data: structuredClone(rows), error: null });
    }
    return Promise.resolve({ data: null, error: new Error('unexpected_rpc') });
  },
};

const output = { conflicts: [], ideas: [1, 2, 3].map((n) => ({
  id: `20000000-0000-4000-8000-00000000000${n}`, title: `Idea ${n}`, hook: 'A useful hook',
  visual: 'Show a familiar object', fit: 'Fits the available time', filmingMinutes: 5, setup: 'A stable shelf',
})) };

Deno.serve({ hostname: '127.0.0.1', port: Number(Deno.env.get('MIRA_FIXTURE_PORT')) }, async (request) => {
  const url = new URL(request.url);
  if (url.pathname === '/observations') return Response.json({ calls, jobs: [...jobs.values()], stepWrites });
  const id = request.headers.get('x-fixture-job') ?? '';
  if (url.pathname === '/tick') {
    const gate = streamGates.get(id)?.shift();
    if (!gate) return new Response(null, { status: 409 });
    gate();
    return new Response(null, { status: 204 });
  }
  if (url.pathname === '/expire-pictures') {
    for (const row of pictures.filter((row) => row.job_id === id)) row.lease_until = new Date(0).toISOString();
    return new Response(null, { status: 204 });
  }
  const selected = request.headers.get('x-fixture-provider') ?? 'deepseek';
  const mode = request.headers.get('x-fixture-mode') ?? 'ok';
  const values: Record<string, string> = {
    SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-server-key',
    MIRA_AI_PROVIDER: selected, MIRA_MODEL: 'fixture-model',
    MIRA_PICTURES_PER_CARD: mode.startsWith('d2-') && !['d2-stream', 'd2-cut'].includes(mode) ? '5' : '0',
    OPENAI_API_KEY: 'fixture-openai-key', DEEPSEEK_API_KEY: 'fixture-deepseek-key', GEMINI_API_KEY: 'fixture-gemini-key',
  };
  const env = { get: (name: string) => values[name] };
  const providerFetch: typeof fetch = async (requestInfo, init) => {
    const payload = await new Request(requestInfo, init).json();
    const imageRequest = String(requestInfo).endsWith('/images/generations');
    calls.push({ url: String(requestInfo), model: payload.model ?? 'fixture-model', mode,
      payload: imageRequest ? payload : undefined });
    if (imageRequest) {
      if (['d2-mixed', 'd2-local-storage'].includes(mode) && payload.prompt.includes('Your hands and the bowl')) {
        return new Response('', { status: 503 });
      }
      return Response.json({ data: [{ b64_json: '/9j/4AAQSkZJRgABAQAASABIAAD/4QBMRXhpZgAATU0AKgAAAAgAAYdpAAQAAAABAAAAGgAAAAAAA6ABAAMAAAABAAEAAKACAAQAAAABAAAAAqADAAQAAAABAAAAAgAAAAD/7QA4UGhvdG9zaG9wIDMuMAA4QklNBAQAAAAAAAA4QklNBCUAAAAAABDUHYzZjwCyBOmACZjs+EJ+/8AAEQgAAgACAwEiAAIRAQMRAf/EAB8AAAEFAQEBAQEBAAAAAAAAAAABAgMEBQYHCAkKC//EALUQAAIBAwMCBAMFBQQEAAABfQECAwAEEQUSITFBBhNRYQcicRQygZGhCCNCscEVUtHwJDNicoIJChYXGBkaJSYnKCkqNDU2Nzg5OkNERUZHSElKU1RVVldYWVpjZGVmZ2hpanN0dXZ3eHl6g4SFhoeIiYqSk5SVlpeYmZqio6Slpqeoqaqys7S1tre4ubrCw8TFxsfIycrS09TV1tfY2drh4uPk5ebn6Onq8fLz9PX29/j5+v/EAB8BAAMBAQEBAQEBAQEAAAAAAAABAgMEBQYHCAkKC//EALURAAIBAgQEAwQHBQQEAAECdwABAgMRBAUhMQYSQVEHYXETIjKBCBRCkaGxwQkjM1LwFWJy0QoWJDThJfEXGBkaJicoKSo1Njc4OTpDREVGR0hJSlNUVVZXWFlaY2RlZmdoaWpzdHV2d3h5eoKDhIWGh4iJipKTlJWWl5iZmqKjpKWmp6ipqrKztLW2t7i5usLDxMXGx8jJytLT1NXW19jZ2uLj5OXm5+jp6vLz9PX29/j5+v/bAEMAAgICAgICAwICAwUDAwMFBgUFBQUGCAYGBgYGCAoICAgICAgKCgoKCgoKCgwMDAwMDA4ODg4ODw8PDw8PDw8PD//bAEMBAgICBAQEBwQEBxALCQsQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEBAQEP/dAAQAAf/aAAwDAQACEQMRAD8AvN94/Wm05vvH602vzM9Q/9k=' }] });
    }
    if (mode === 'unavailable') return new Response('', { status: 503 });
    const input = JSON.parse(payload.messages?.[1]?.content ?? payload.contents?.[0]?.parts?.[0]?.text ?? '{}');
    let result: unknown = output;
    if (['storyboard', 'reviseShot', 'todayIdea'].includes(input.operation)) {
      const script = input.operation === 'todayIdea' ? {
        id: crypto.randomUUID(), hook: 'Here is my breakfast.', spoken: 'Add fruit to the bowl.',
        caption: 'My breakfast', durationSeconds: 20, language: 'English',
      } : input.script;
      const first = {
        id: '30000000-0000-4000-8000-000000000001', purpose: 'Introduce the routine',
        editedSeconds: 6, recordingSeconds: 12, location: 'Home', props: 'Phone and books',
        placement: 'Prop the phone against books on the table.',
        distance: mode === 'blank-distance' ? '  ' : 'One arm’s length', framing: 'Head and shoulders', frameType: 'headShoulders',
        action: 'Sit at the table.', words: 'Here is my breakfast.', voiceover: false,
        onScreenText: 'My breakfast', simplerAlternative: 'Stay seated.',
      };
      const second = {
        ...first, id: '30000000-0000-4000-8000-000000000002', purpose: 'Show the bowl',
        editedSeconds: 14, frameType: 'closeUp', framing: 'Your hands and the bowl', recordingSeconds: 20,
      };
      const shots = input.operation === 'reviseShot'
        ? [{
          ...first, id: mode === 'wrong-target' ? second.id : first.id,
          placement: 'Put the phone on a steady shelf.', distance: 'Two big steps', framing: 'Waist up', frameType: 'halfBody',
        }]
        : [first, second];
      if (mode === 'missing-frame') Reflect.deleteProperty(shots[0], 'frameType');
      result = {
        conflicts: [],
        storyboard: {
          id: crypto.randomUUID(), sourceScriptID: script.id, requirementsRevision: 0, shots, mappings: [],
        },
      };
      if (input.operation === 'todayIdea') {
        const third = { ...first, id: crypto.randomUUID(), purpose: 'Finish the idea', editedSeconds: 4 };
        const idea = { ...output.ideas[0], title: input.angle, hook: script.hook,
          visual: 'Show a bowl of dahi 🥣 with "script": braces { and commas, and a slash \\.' };
        const board = {
          id: crypto.randomUUID(), sourceScriptID: mode === 'wrong-source' ? crypto.randomUUID() : script.id,
          requirementsRevision: 0, shots: [first, { ...second, editedSeconds: 10 }, third], mappings: [],
        };
        if (mode === 'wrong-duration') third.editedSeconds += 8;
        result = { conflicts: [], ideas: [idea], script, storyboard: board };
      }
    }
    const text = mode === 'invalid' ? '{}' : JSON.stringify(result);
    if (payload.stream) {
      const gates: (() => void)[] = [];
      const manual = mode === 'd2-stream' || mode === 'd2-cut';
      if (manual) streamGates.set(id, gates);
      const encoder = new TextEncoder();
      const frame = (delta: string, reason: string | null = null) =>
        `data: ${JSON.stringify({ choices: [{ delta: { content: delta }, finish_reason: reason }] })}\r\n\r\n`;
      const body = new ReadableStream<Uint8Array>({
        async start(controller) {
          const send = (event: string) => {
            const bytes = encoder.encode(event);
            const split = bytes.indexOf(0xf0);
            const offset = split >= 0 ? split + 2 : 3;
            controller.enqueue(bytes.slice(0, offset));
            controller.enqueue(bytes.slice(offset));
          };
          if (manual) {
            const value = result as Record<string, unknown>;
            const parts = [
              `{"ideas":${JSON.stringify(value.ideas)},`,
              `"script":${JSON.stringify(value.script)},`,
              `"storyboard":${JSON.stringify(value.storyboard)},`,
              '"conflicts":[]}',
            ];
            for (const part of parts) {
              await new Promise<void>(resolve => gates.push(resolve));
              if (mode === 'd2-cut' && part.startsWith('"script"')) {
                send(frame(part.slice(0, 30)));
                controller.close();
                return;
              }
              const middle = Math.floor(part.length / 2);
              send(frame(part.slice(0, middle)));
              send(frame(part.slice(middle)));
            }
          } else {
            send(frame(text));
          }
          send(frame('', 'stop') + 'data: [DONE]\r\n\r\n');
          controller.close();
        },
      });
      return new Response(body, { headers: { 'content-type': 'text/event-stream' } });
    }
    return Response.json(selected === 'gemini'
      ? { candidates: [{ content: { parts: [{ text }] } }] }
      : { choices: [{ message: { content: text } }] });
  };
  const database = mode === 'd2-local-storage' ? localAdmin : undefined;
  return await handleMira(request, {
    env,
    admin: {
      from: (table: string) => database && ['mira_generation_jobs', 'mira_shot_pictures'].includes(table)
        ? database.from(table) : new Query(table, mode),
      storage: database?.storage ?? admin.storage,
      rpc: (name: string, args: Row) => database ? database.rpc(name, args) : admin.rpc(name, args, mode),
    },
    generate: (input, config, signal, _fetch, onStep) => generate(input, config, signal, providerFetch, onStep),
    pictureFetch: providerFetch,
    ...(mode === 'd2-stream' || mode === 'd2-cut' ? {
      defer: (work: Promise<unknown>) => { void work.catch(() => {}); },
    } : {}),
  });
});
