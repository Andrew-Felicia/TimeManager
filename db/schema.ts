import { index, integer, sqliteTable, text } from "drizzle-orm/sqlite-core";

export const tasks = sqliteTable("tasks", {
  id: text("id").primaryKey(),
  ownerId: text("owner_id").notNull(),
  title: text("title").notNull(),
  dueAt: text("due_at"),
  category: text("category").notNull().default("Work"),
  estimateMinutes: integer("estimate_minutes").notNull().default(25),
  completed: integer("completed", { mode: "boolean" }).notNull().default(false),
  updatedAt: integer("updated_at").notNull(),
}, (table) => [index("idx_tasks_owner_updated").on(table.ownerId, table.updatedAt)]);

export const events = sqliteTable("events", {
  id: text("id").primaryKey(),
  ownerId: text("owner_id").notNull(),
  title: text("title").notNull(),
  startsAt: text("starts_at").notNull(),
  endsAt: text("ends_at").notNull(),
  category: text("category").notNull().default("Work"),
  updatedAt: integer("updated_at").notNull(),
}, (table) => [index("idx_events_owner_starts").on(table.ownerId, table.startsAt)]);

export const sessions = sqliteTable("sessions", {
  id: text("id").primaryKey(),
  ownerId: text("owner_id").notNull(),
  label: text("label").notNull(),
  mode: text("mode").notNull(),
  durationSeconds: integer("duration_seconds").notNull(),
  startedAt: text("started_at").notNull(),
  updatedAt: integer("updated_at").notNull(),
}, (table) => [index("idx_sessions_owner_started").on(table.ownerId, table.startedAt)]);
