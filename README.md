# Smiley

Smiley is a private two-person relationship space built with Flutter, Node.js, TypeScript, PostgreSQL, Prisma, and realtime events.

## Current Status

Implemented in this repository:

- Flutter app shell for Android, iOS, web, and desktop targets.
- First-run date gate with secure local persistence.
- Login, registration, and password-reset screens wired to REST endpoints.
- Empty Smiley world state before partnership setup with distinct tab states.
- Partner search, partnership requests, accepting/rejecting/cancelling, and relationship onboarding.
- Home/feed, moods, chat persistence, calendar, occasions, notifications, wishes, goals, lists, albums, places, daily tree leaves, time capsules, music queue, and watch queue.
- Profile, relationship settings, reports, account export, and soft-delete.
- Backend with Express, TypeScript, Prisma, JWT, bcrypt, request IDs, rate limiting, health endpoints, and authenticated Socket.IO realtime rooms.
- PostgreSQL Prisma schema covering the requested product domains.
- Environment variable examples and initial migration SQL for the core phase-one tables.
- Flutter widget/unit tests and a backend username policy unit test.

External integrations still require provider credentials before they can be production-active:

- Email/phone delivery providers.
- Firebase/APNs push delivery.
- Cloudflare R2 media object storage and upload signing.
- Redis-backed multi-instance presence.
- Full offline queue/local database sync.

## Flutter

```bash
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

If `API_BASE_URL` is not provided, the Flutter app uses the deployed Railway API.

## Backend

```bash
cd backend
npm install
cp .env.example .env
npm run prisma:generate
npm run prisma:migrate
npm run dev
```

Health endpoints:

- `GET /health`
- `GET /ready`
- `GET /live`

API prefix:

- `/api/v1`

## Local Database

Use PostgreSQL locally. A matching Docker Compose file is included:

```bash
docker compose up -d
```

Then run Prisma migrations from `backend`.

## Secrets

Do not commit real secrets. Copy `.env.example` or `backend/.env.example` and fill local values in `.env`.
