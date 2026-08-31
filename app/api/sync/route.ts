import { env } from "cloudflare:workers";

export const dynamic = "force-dynamic";

function ownerId(request: Request) {
  return request.headers.get("oai-authenticated-user-id") ?? "local-preview-user";
}

async function ensureSchema() {
  const db = env.DB;
  await db.batch([
    db.prepare("CREATE TABLE IF NOT EXISTS tasks (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, title TEXT NOT NULL, due_at TEXT, category TEXT NOT NULL DEFAULT 'Work', estimate_minutes INTEGER NOT NULL DEFAULT 25, completed INTEGER NOT NULL DEFAULT 0, list_id TEXT NOT NULL DEFAULT 'inbox', details TEXT NOT NULL DEFAULT '', deadline TEXT, scheduled_at TEXT, subtasks_json TEXT NOT NULL DEFAULT '[]', updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, title TEXT NOT NULL, starts_at TEXT NOT NULL, ends_at TEXT NOT NULL, category TEXT NOT NULL DEFAULT 'Work', all_day INTEGER NOT NULL DEFAULT 0, updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS sessions (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, label TEXT NOT NULL, mode TEXT NOT NULL, duration_seconds INTEGER NOT NULL, started_at TEXT NOT NULL, updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE TABLE IF NOT EXISTS categories (owner_id TEXT NOT NULL, name TEXT NOT NULL, updated_at INTEGER NOT NULL, PRIMARY KEY (owner_id, name))"),
    db.prepare("CREATE TABLE IF NOT EXISTS task_lists (id TEXT PRIMARY KEY, owner_id TEXT NOT NULL, name TEXT NOT NULL, updated_at INTEGER NOT NULL)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_tasks_owner_updated ON tasks(owner_id, updated_at)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_events_owner_starts ON events(owner_id, starts_at)"),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_sessions_owner_started ON sessions(owner_id, started_at)"),
  ]);
  try {
    await db.prepare("ALTER TABLE events ADD COLUMN all_day INTEGER NOT NULL DEFAULT 0").run();
  } catch {
    // Existing databases already containing the column need no migration.
  }
  for (const statement of [
    "ALTER TABLE tasks ADD COLUMN list_id TEXT NOT NULL DEFAULT 'inbox'",
    "ALTER TABLE tasks ADD COLUMN details TEXT NOT NULL DEFAULT ''",
    "ALTER TABLE tasks ADD COLUMN deadline TEXT",
    "ALTER TABLE tasks ADD COLUMN scheduled_at TEXT",
    "ALTER TABLE tasks ADD COLUMN subtasks_json TEXT NOT NULL DEFAULT '[]'",
  ]) {
    try {
      await db.prepare(statement).run();
    } catch {
      // The column is already present.
    }
  }
}

export async function GET(request: Request) {
  await ensureSchema();
  const owner = ownerId(request);
  const [tasks, events, sessions, categories, taskLists] = await env.DB.batch([
    env.DB.prepare("SELECT * FROM tasks WHERE owner_id = ? ORDER BY completed, updated_at DESC").bind(owner),
    env.DB.prepare("SELECT * FROM events WHERE owner_id = ? ORDER BY starts_at").bind(owner),
    env.DB.prepare("SELECT * FROM sessions WHERE owner_id = ? ORDER BY started_at DESC LIMIT 100").bind(owner),
    env.DB.prepare("SELECT * FROM categories WHERE owner_id = ? ORDER BY name").bind(owner),
    env.DB.prepare("SELECT * FROM task_lists WHERE owner_id = ? ORDER BY updated_at, name").bind(owner),
  ]);
  return Response.json({ tasks: tasks.results, events: events.results, sessions: sessions.results, categories: categories.results, taskLists: taskLists.results, cursor: Date.now() });
}

export async function POST(request: Request) {
  await ensureSchema();
  const owner = ownerId(request);
  const body = await request.json() as { action?: string; payload?: Record<string, unknown> };
  const value = body.payload ?? {};
  const now = Date.now();

  if (body.action === "upsert-task") {
    await env.DB.prepare("INSERT INTO tasks (id, owner_id, title, due_at, category, estimate_minutes, completed, list_id, details, deadline, scheduled_at, subtasks_json, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title=excluded.title, due_at=excluded.due_at, category=excluded.category, estimate_minutes=excluded.estimate_minutes, completed=excluded.completed, list_id=excluded.list_id, details=excluded.details, deadline=excluded.deadline, scheduled_at=excluded.scheduled_at, subtasks_json=excluded.subtasks_json, updated_at=excluded.updated_at WHERE owner_id=excluded.owner_id")
      .bind(value.id, owner, value.title, value.when ?? null, value.category ?? "Work", value.estimate ?? 25, value.done ? 1 : 0, value.listId ?? "inbox", value.details ?? "", value.deadline ?? null, value.scheduledAt ?? null, JSON.stringify(value.subtasks ?? []), now).run();
  } else if (body.action === "upsert-event") {
    const startsAt = value.startsAt ?? "2026-08-28T15:00:00+08:00";
    const endsAt = value.endsAt ?? "2026-08-28T16:00:00+08:00";
    await env.DB.prepare("INSERT INTO events (id, owner_id, title, starts_at, ends_at, category, all_day, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET title=excluded.title, starts_at=excluded.starts_at, ends_at=excluded.ends_at, category=excluded.category, all_day=excluded.all_day, updated_at=excluded.updated_at WHERE owner_id=excluded.owner_id")
      .bind(value.id, owner, value.title, startsAt, endsAt, value.category ?? "Work", value.allDay ? 1 : 0, now).run();
  } else if (body.action === "log-session") {
    await env.DB.prepare("INSERT INTO sessions (id, owner_id, label, mode, duration_seconds, started_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?)")
      .bind(value.id, owner, value.label ?? "Focus", value.mode ?? "focus", value.duration ?? 0, new Date().toISOString(), now).run();
  } else if (body.action === "upsert-category") {
    await env.DB.prepare("INSERT INTO categories (owner_id, name, updated_at) VALUES (?, ?, ?) ON CONFLICT(owner_id, name) DO UPDATE SET updated_at=excluded.updated_at")
      .bind(owner, value.name, now).run();
  } else if (body.action === "delete-category") {
    await env.DB.prepare("DELETE FROM categories WHERE owner_id = ? AND name = ?")
      .bind(owner, value.name).run();
  } else if (body.action === "upsert-task-list") {
    await env.DB.prepare("INSERT INTO task_lists (id, owner_id, name, updated_at) VALUES (?, ?, ?, ?) ON CONFLICT(id) DO UPDATE SET name=excluded.name, updated_at=excluded.updated_at WHERE owner_id=excluded.owner_id")
      .bind(value.id, owner, value.name, now).run();
  } else if (body.action === "delete-task-list") {
    await env.DB.prepare("DELETE FROM task_lists WHERE id = ? AND owner_id = ?")
      .bind(value.id, owner).run();
  } else {
    return Response.json({ error: "Unsupported sync action" }, { status: 400 });
  }
  return Response.json({ ok: true, syncedAt: now });
}
