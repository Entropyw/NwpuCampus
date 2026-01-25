# NwpuCampus Server (ArkTS-style TypeScript)

This is a minimal ArkTS-style (TypeScript subset) REST server used by the map WebView for authentication, custom places, moderation, votes, hazards, and user preferences. It uses a JSON file for persistence.

## Features
- User registration & login (no email verification)
- Custom places (private/pending/approved)
- Public places and hazard places (water/slippery/danger)
- Voting (👍/👎)
- Feedback to admins
- Admin approval/rejection and system-place overrides
- User hidden-place preferences

## Setup
1. Install dependencies:

```bash
npm install
```

2. Build & run:

```bash
npm run build
npm start
```

Or run directly in dev mode:

```bash
npm run dev
```

The server listens on `0.0.0.0:8080` by default.

## Default Admin
The default admin user is configured in `data/db.json`:

- username: `admin`
- password: `admin123`

You should change this for production.

## API (summary)
- `POST /api/register` — `{ username, password }`
- `POST /api/login` — `{ username, password }`
- `GET /api/me`
- `GET /api/places?scope=public|mine|pending`
- `POST /api/places`
- `PUT /api/places/:id`
- `DELETE /api/places/:id`
- `POST /api/places/:id/publish`
- `POST /api/places/:id/vote` — `{ value: 1 | -1 }`
- `POST /api/places/:id/feedback` — `{ message }`
- `GET /api/preferences`
- `POST /api/preferences/hide` — `{ placeId, hidden }`
- `GET /api/system-overrides`
- `POST /api/admin/places/:id/approve`
- `POST /api/admin/places/:id/reject`

## Data
Data is persisted in `data/db.json`.

---
If you change the server IP/port, update the WebView’s API base (`API_BASE_DEFAULT`) or call `window.setApiBase(...)` from the host.
