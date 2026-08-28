import { env } from "cloudflare:workers";

export const dynamic = "force-dynamic";

function ownerId(request: Request) {
  return request.headers.get("oai-authenticated-user-id") ?? "local-preview-user";
}

async function ensureSchema() {
  const db = env.DB;
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, title TEXT NOT NULL, due_at TEXT, category TEXT NOT NULL DEFAULT 'Work', estimate_minutes INTEGER NOT NULL DEFAULT 25, completed INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, title TEXT NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'Work', updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, label TEXT NOT NULL, mode TEXT NOT NULL, duration_seconds INTEGER NOT NULL, started_at TEXT NOT NULL, updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_tasks_owner_updated ON tasks(owner_id, updated_at)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_events_owner_starts ON events(owner_id, starts_at)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_sessions_owner_started ON sessions(owner_id, started_at)"),
  ]);
}

export async function GET(request: Request) {
  await ensureSchema();
  const owner = ownerId(request);
  const [tasks, events, sessions] = await env.DB.batch([
    env.DB.prepare("SELECT * FROM tasks WHERE owner_id = ? ORDER BY completed, updated_at DESC").bind(owner),
    env.DB.prepare("SELECT * FROM events WHERE owner_id = ? ORDER BY starts_at").bind(owner),
    env.DB.prepare("SELECT * FROM sessions WHERE owner_id = ? ORDER BY started_at DESC LIMIT 100").bind(owner),
  ]);
  return Response.json({ tasks: tasks.results, events: events.results, sessions: sessions.results, cursor: Date.now() });
}

export async function POST(request: Request) {
  await ensureSchema();
  const owner = ownerId(request);
  const body = await request.json() as { action?: string; payload?: Record<string, unknown> };
  const value = body.payload ?? {};
  const now = Date.now();

  if (body.action === "upsert-task") {
    await env.DB.prepare("INSERT INTO tasks (id, owner_id, title, due_at, category, estimate_minutes, completed, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title=excluded.title, due_at=excluded.due_at, category=excluded.category, estimate_minutes=excluded.estimate_minutes, completed=excluded.completed, updated_at=excluded.updated_at WHERE owner_id=excluded.owner_id")
      .bind(value.id, owner, value.title, value.when ?? null, value.category ?? "Work", value.estimate ?? 25, value.done ? 1 : 0, now).run();
  } else if (body.action === "upsert-event") {
    const startsAt = value.startsAt ?? "2026-08-28T15:00:00+08:00";
    const endsAt = value.endsAt ?? "2026-08-28T16:00:00+08:00";
    await env.DB.prepare("INSERT INTO events (id, owner_id, title, starts_at, ends_at, category, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title=excluded.title, starts_at=excluded.starts_at, ends_at=excluded.ends_at, category=excluded.category, updated_at=excluded.updated_at WHERE owner_id=excluded.owner_id")
      .bind(value.id, owner, value.title, startsAt, endsAt, value.category ?? "Work", now).run();
  } else if (body.action === "log-session") {
    await env.DB.prepare("INSERT INTO sessions (id, owner_id, label, mode, duration_seconds, started_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .bind(value.id, owner, value.label ?? "Focus", value.mode ?? "focus", value.duration ?? 0, new Date().toISOString(), now).run();
  } else {
    return Response.json({ error: "Unsupported sync action" }, { status: 400 });
  }
  return Response.json({ ok: true, syncedAt: now });
}
