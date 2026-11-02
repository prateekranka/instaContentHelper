import { DatabaseSync } from 'node:sqlite';
import { z } from 'zod';

export const mutation = z.object({
  id: z.string().regex(/^MIRA-\d{3}$/),
  title: z.string().min(1).max(160).optional(),
  description: z.string().max(3000).optional(),
  milestone: z.string().max(100).optional(),
  criteria: z.array(z.string().min(1).max(500)).min(1).optional(),
  status: z.enum(['Planned', 'Working', 'Done']).optional(),
  commits: z.array(z.string().regex(/^https:\/\/github\.com\/prateekranka\/instaContentHelper\/commit\/[a-f0-9]{40}$/)).optional(),
  verification: z.string().max(5000).optional(),
  blocker: z.string().max(2000).nullable().optional(),
  nextAction: z.string().max(2000).optional(),
  note: z.string().min(1).max(5000),
  codeTask: z.boolean().optional(),
}).strict();
export type Mutation = z.infer<typeof mutation>;
export type Task = Omit<Mutation, 'note'> & {
  title: string; description: string; milestone: string; criteria: string[];
  status: 'Planned' | 'Working' | 'Done'; commits: string[]; verification: string;
  createdAt: string; startedAt: string | null; updatedAt: string; completedAt: string | null;
  history: { at: string; note: string; status: string }[];
};
export class Store {
  db: DatabaseSync;
  constructor(path: string) {
    this.db = new DatabaseSync(path);
    this.db.exec(`PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000;
      CREATE TABLE IF NOT EXISTS tasks(id TEXT PRIMARY KEY, body TEXT NOT NULL);
      CREATE TABLE IF NOT EXISTS mutations(key TEXT PRIMARY KEY, input TEXT NOT NULL, result TEXT NOT NULL);`);
  }
  list(): Task[] {
    return (this.db.prepare('SELECT body FROM tasks ORDER BY id').all() as {body:string}[]).map(r => JSON.parse(r.body));
  }
  initialize(snapshot: unknown): boolean {
    if (this.list().length) return false;
    const timestamp = z.iso.datetime();
    const stored = mutation.omit({note:true}).extend({
      title:z.string().min(1).max(160),description:z.string().max(3000),milestone:z.string().max(100),
      criteria:z.array(z.string().min(1).max(500)).min(1),status:z.enum(['Planned','Working','Done']),
      commits:z.array(z.string().regex(/^https:\/\/github\.com\/prateekranka\/instaContentHelper\/commit\/[a-f0-9]{40}$/)),
      verification:z.string().max(5000),createdAt:timestamp,startedAt:timestamp.nullable(),updatedAt:timestamp,completedAt:timestamp.nullable(),
      history:z.array(z.object({at:timestamp,note:z.string().min(1).max(5000),status:z.enum(['Planned','Working','Done'])}).strict()).min(1),
    }).strict();
    const tasks=z.array(stored).parse(snapshot);
    if(new Set(tasks.map(t=>t.id)).size!==tasks.length)throw Error('Snapshot has duplicate task IDs');
    for(const task of tasks)if(task.status==='Done'&&(!task.verification.trim()||(task.codeTask&&!task.commits.length)||task.blocker||!task.completedAt))throw Error('Snapshot completion evidence is missing');
    this.db.exec('BEGIN IMMEDIATE');
    try{
      if(this.list().length){this.db.exec('ROLLBACK');return false;}
      for(const task of tasks)this.db.prepare('INSERT INTO tasks VALUES(?,?)').run(task.id,JSON.stringify(task));
      this.db.exec('COMMIT');return true;
    }catch(error){this.db.exec('ROLLBACK');throw error;}
  }
  apply(key: string, input: Mutation): Task {
    this.db.exec('BEGIN IMMEDIATE');
    try {
      const previous = this.db.prepare('SELECT input, result FROM mutations WHERE key=?').get(key) as {input:string;result:string} | undefined;
      const canonical = JSON.stringify(input);
      if (previous) {
        if (previous.input !== canonical) throw new Error('Idempotency key reused with different input');
        this.db.exec('COMMIT'); return JSON.parse(previous.result);
      }
      const now = new Date().toISOString();
      const row = this.db.prepare('SELECT body FROM tasks WHERE id=?').get(input.id) as {body:string}|undefined;
      const old: Task | undefined = row ? JSON.parse(row.body) : undefined;
      if (!old && (!input.title || !input.description || !input.criteria || !input.milestone)) throw new Error('New tasks need title, description, milestone and criteria');
      const {note, ...fields} = input;
      const task = {...old, ...fields, commits:[...new Set([...(old?.commits ?? []), ...(input.commits ?? [])])],
        verification:input.verification ?? old?.verification ?? '', status:input.status ?? old?.status ?? 'Planned',
        createdAt:old?.createdAt ?? now, updatedAt:now, startedAt:old?.startedAt ?? null, completedAt:old?.completedAt ?? null,
        history:[...(old?.history ?? []), {at:now, note, status:input.status ?? old?.status ?? 'Planned'}]} as Task;
      if (task.status !== 'Planned') task.startedAt ??= now;
      if (task.status === 'Done') {
        if (!task.verification.trim() || (task.codeTask && !task.commits.length) || task.blocker) throw new Error('Done requires verification, pushed commits for code, and no blocker');
        if (old?.status !== 'Done') task.completedAt = now;
      } else task.completedAt = null;
      this.db.prepare('INSERT INTO tasks VALUES(?,?) ON CONFLICT(id) DO UPDATE SET body=excluded.body').run(task.id, JSON.stringify(task));
      this.db.prepare('INSERT INTO mutations VALUES(?,?,?)').run(key, canonical, JSON.stringify(task));
      this.db.exec('COMMIT'); return task;
    } catch(e) { this.db.exec('ROLLBACK'); throw e; }
  }
}
