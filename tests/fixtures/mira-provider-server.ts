import { handleMira } from '../../supabase/functions/mira-generation/index.ts';
import { generate } from '../../supabase/functions/mira-generation/provider.ts';
import { sha256Hex } from '../../supabase/functions/_shared/device-auth.ts';

const workspaceID = '10000000-0000-4000-8000-000000000001';
const creatorID = '10000000-0000-4000-8000-000000000002';
const memberID = '10000000-0000-4000-8000-000000000003';
const tokenHash = await sha256Hex('fixture-device-token');
type Row = Record<string, unknown>;
const jobs = new Map<string, Row>();
const calls: { url: string; model: string; mode: string }[] = [];
const tables: Record<string, Row[]> = {
  device_installations: [{ id: 'installation', workspace_id: workspaceID, member_id: memberID, token_hash: tokenHash, revoked_at: null }],
  members: [{ id: memberID, workspace_id: workspaceID, role: 'creator', status: 'active' }],
  creators: [{ id: creatorID, workspace_id: workspaceID }],
};

class Query {
  private conditions: ((row: Row) => boolean)[] = [];
  private changes?: Row;
  constructor(private table: string) {}
  select(_columns: string) { return this; }
  eq(key: string, value: unknown) { this.conditions.push((row) => row[key] === value); return this; }
  is(key: string, value: unknown) { return this.eq(key, value); }
  in(key: string, values: unknown[]) { this.conditions.push((row) => values.includes(row[key])); return this; }
  update(changes: Row) { this.changes = changes; return this; }
  result() {
    const rows = this.table === 'mira_generation_jobs' ? [...jobs.values()] : tables[this.table] ?? [];
    const row = rows.find((item) => this.conditions.every((condition) => condition(item)));
    if (row && this.changes) Object.assign(row, this.changes);
    return { data: row ? structuredClone(row) : null, error: null };
  }
  maybeSingle() { return Promise.resolve(this.result()); }
  then(resolve: (value: unknown) => void, reject: (reason: unknown) => void) {
    return Promise.resolve(this.result()).then(resolve, reject);
  }
}

const admin = {
  from(table: string) { return new Query(table); },
  rpc(name: string, args: Row) {
    if (name === 'mira_enqueue') {
      const id = String(args.p_id);
      const row = { id, workspace_id: args.p_workspace, creator_id: args.p_creator, member_id: args.p_member,
        input_revision: args.p_revision, input: args.p_input, status: 'queued', attempts: 0 };
      jobs.set(id, row);
      return Promise.resolve({ data: row, error: null });
    }
    if (name === 'mira_claim') {
      const row = jobs.get(String(args.p_id));
      if (!row || row.status !== 'queued') return Promise.resolve({ data: [], error: null });
      Object.assign(row, { status: 'running', lease_id: crypto.randomUUID(), attempts: Number(row.attempts) + 1 });
      return Promise.resolve({ data: [structuredClone(row)], error: null });
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
  if (url.pathname === '/observations') return Response.json({ calls, jobs: [...jobs.values()] });
  const selected = request.headers.get('x-fixture-provider') ?? 'deepseek';
  const mode = request.headers.get('x-fixture-mode') ?? 'ok';
  const values: Record<string, string> = {
    SUPABASE_URL: 'https://fixture.invalid', SUPABASE_SERVICE_ROLE_KEY: 'fixture-server-key',
    MIRA_AI_PROVIDER: selected, MIRA_MODEL: 'fixture-model',
    OPENAI_API_KEY: 'fixture-openai-key', DEEPSEEK_API_KEY: 'fixture-deepseek-key', GEMINI_API_KEY: 'fixture-gemini-key',
  };
  const env = { get: (name: string) => values[name] };
  const providerFetch: typeof fetch = async (requestInfo, init) => {
    const payload = JSON.parse(String(init?.body));
    calls.push({ url: String(requestInfo), model: payload.model ?? 'fixture-model', mode });
    if (mode === 'unavailable') return new Response('', { status: 503 });
    const text = mode === 'invalid' ? '{}' : JSON.stringify(output);
    return Response.json(selected === 'gemini'
      ? { candidates: [{ content: { parts: [{ text }] } }] }
      : { choices: [{ message: { content: text } }] });
  };
  return await handleMira(request, { env, admin, generate: (input, config) => generate(input, config, providerFetch) });
});
