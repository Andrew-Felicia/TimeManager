CREATE INDEX `idx_events_owner_starts` ON `events` (`owner_id`,`starts_at`);--> statement-breakpoint
CREATE INDEX `idx_sessions_owner_started` ON `sessions` (`owner_id`,`started_at`);--> statement-breakpoint
CREATE INDEX `idx_tasks_owner_updated` ON `tasks` (`owner_id`,`updated_at`);