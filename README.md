# Flowtime

Flowtime combines a weekly calendar, tasks, focus timers, a stopwatch, and time analytics in one calm workspace. The repository includes the responsive web product, a Cloudflare D1 sync API, and a native SwiftUI iOS companion.

## Product surfaces

- `app/` — responsive Vinext/React web app and `/api/sync` backend route
- `db/` and `drizzle/` — shared SQLite/D1 data model and migrations
- `ios/` — SwiftUI iPhone client using the same sync contract
- `.openai/hosting.json` — deploy-time D1 binding

Every record belongs to an authenticated owner. Hosted web routes use a stable authenticated user ID; on a future VPS deployment, the same value should come from the verified subject in an OAuth/JWT session. Both clients then read and write the same owner-scoped records.

## Local web development

Use Node 22.13 or newer:

```bash
npm install
npm run dev
```

Create a production bundle with `npm run build`. The local Cloudflare runtime supplies a D1-compatible database automatically.

## iOS development

Open `ios/Flowtime.xcodeproj` directly in Xcode; the generated project is included in the repository. The `ios/project.yml` definition remains available if the project ever needs to be regenerated. Before a real release, point `FlowtimeAPI.baseURL` at the deployed backend and add Sign in with Apple to exchange an Apple identity token for your API session.

## Production roadmap

1. Add Sign in with Apple and web passkeys/OAuth through one identity provider.
2. Replace the compatibility owner-header adapter with verified JWT middleware.
3. Add delta sync using `updated_at`, cursor pagination, idempotency keys, and soft deletes.
4. Add APNs reminders, background refresh, calendar import, privacy policy, account deletion, and App Store assets.
5. Deploy the web worker and D1 migration, then map the custom domain or reproduce the API contract on the VPS.

The current UI and data model are production-shaped; payments, public account creation, notifications, and App Store compliance remain release work rather than mocked features.
