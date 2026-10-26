import Fastify from 'fastify';
import staticFiles from '@fastify/static';
import { createHash, timingSafeEqual } from 'node:crypto';
import { mkdirSync, readFileSync } from 'node:fs';
import { dirname, resolve } from 'node:path';
import { Store, mutation } from './store.ts';
const secret = process.env.TRACKER_WRITE_TOKEN;
if (!secret || secret.length < 32) throw new Error('TRACKER_WRITE_TOKEN must contain at least 32 characters');
const dbPath = process.env.TRACKER_DB ?? './work/tracker.sqlite';
mkdirSync(dirname(dbPath), {recursive:true});
const store = new Store(dbPath);
const seed = JSON.parse(readFileSync(new URL('../seed.json', import.meta.url), 'utf8'));
for (const task of seed) if (!store.list().some(t => t.id === task.id)) store.apply(`seed-${task.id}`, mutation.parse(task));
const app = Fastify({logger:{level:'info', redact:['req.headers.authorization']}, bodyLimit:32_768});
app.addHook('onSend', async (_req, reply) => {
  reply.header('X-Content-Type-Options', 'nosniff');
  reply.header('Referrer-Policy', 'no-referrer');
  reply.header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; frame-ancestors 'none'; base-uri 'none'");
});
await app.register(staticFiles, {root:resolve(import.meta.dirname, '../public')});
app.get('/health', async () => { store.list(); return {ok:true}; });
app.get('/api/tasks', async (_req, reply) => {
  const tasks = store.list(); reply.header('Cache-Control', 'no-store');
  return { tasks, fetchedAt:new Date().toISOString(), activityAt:tasks.map(t=>t.updatedAt).sort().at(-1) ?? null };
});
app.post('/api/tasks', async (req, reply) => {
  const actual = createHash('sha256').update(req.headers.authorization ?? '').digest();
  const expected = createHash('sha256').update(`Bearer ${secret}`).digest();
  if (!timingSafeEqual(actual, expected)) return reply.code(401).send({error:'Authenticated editing only'});
  const key = req.headers['idempotency-key'];
  if (typeof key !== 'string' || !/^[\w-]{8,128}$/.test(key)) return reply.code(400).send({error:'A stable Idempotency-Key is required'});
  const parsed = mutation.safeParse(req.body);
  if (!parsed.success) return reply.code(400).send({error:parsed.error.flatten()});
  try { return store.apply(key, parsed.data); }
  catch(e) { return reply.code(409).send({error:(e as Error).message}); }
});
await app.listen({host:'0.0.0.0',port:Number(process.env.PORT ?? 3000)});
