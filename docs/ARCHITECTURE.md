# Architecture

## Applications

- `lib/`: Flutter client with feature modules.
- `backend/`: Node.js TypeScript API and realtime server.
- `backend/prisma/`: PostgreSQL data model and migrations.

## Flutter Modules

- `core`: HTTP client, Socket.IO realtime client, and secure storage abstractions.
- `features/gate`: first-run date gate.
- `features/auth`: login, registration, and password reset.
- `features/home`: empty world, main navigation shell, chat, calendar, world tools, profile, settings screens, and offline retry wiring for messages/posts.
- `core/offline_outbox`: SharedPreferences-backed local outbox for unsent chat messages and posts when network requests fail.
- `features/partnerships`: partner search and request contracts.

## Backend Modules

- `auth`: registration, login, password reset request, token issuing.
- `users`: username search with limited public profile data.
- `partnerships`: partnership request lifecycle and onboarding.
- `space`: active relationship APIs for home, feed, chat, calendar, moods, notifications, wishes, goals, lists, places, albums, rooms, tree leaves, time capsules, reports, export, and account deletion.
- `health`: readiness and liveness.
- `realtime`: event contract plus authenticated Socket.IO rooms for users and partnerships.

## Security Decisions

- Passwords are hashed with bcrypt.
- Access tokens are short-lived JWTs.
- Refresh tokens are persisted only as hashes.
- The Flutter client stores tokens and the first-run gate flag through secure storage.
- Search results do not expose email, phone, birth date, or private profile fields.
- Partnership requests are created inside database transactions.
- API errors return `code`, `message`, `details`, and `requestId`.
- Realtime sockets validate JWT access tokens and only join rooms for memberships found in the database.

## Phase Plan

1. Core account, date gate, profile, partner discovery, partnership requests, relationship onboarding.
2. Home, feed, moods, calendar, occasions, counters, basic notifications.
3. Media posts/messages, receipts, offline queue, full push notifications.
4. Rich Smiley world visualizations, summaries, and games.
5. Audio upload, allowed YouTube integration, and playback sync.
6. Uploaded videos, allowed YouTube playback, and external countdowns.
7. Performance, security hardening, and provider-specific production integrations.
