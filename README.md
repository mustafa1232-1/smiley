# Smiley

Smiley is a private two-person relationship space built with Flutter, Node.js, TypeScript, PostgreSQL, Prisma, and realtime events.

## Phase One Status

Implemented in this repository:

- Flutter app shell for Android, iOS, web, and desktop targets.
- First-run date gate with secure local persistence.
- Login, registration, and password-reset screens wired to REST endpoints.
- Empty Smiley world state before partnership setup.
- Partner search and partnership request UI wired to the backend contract.
- Backend scaffold with Express, TypeScript, Prisma, JWT, bcrypt, request IDs, rate limiting, health endpoints, and Socket.IO bootstrap.
- PostgreSQL Prisma schema covering the requested product domains.
- Environment variable examples and initial migration SQL for the core phase-one tables.
- Flutter widget/unit tests and a backend username policy unit test.

Not yet implemented:

- Email/phone delivery providers, push delivery, media upload signing, Redis presence, full relationship onboarding endpoints, feed, chat persistence, offline queue, and production deployment.

## Flutter

```bash
flutter pub get
flutter test
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

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
