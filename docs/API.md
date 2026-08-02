# API

Base path: `/api/v1`

## Auth

### `POST /auth/register`

Creates a user and returns an auth session.

```json
{
  "displayName": "مستخدم",
  "username": "user.name",
  "email": "user@example.com",
  "password": "strong-password",
  "birthDate": "2000-01-01T00:00:00.000Z",
  "timezone": "Asia/Baghdad",
  "language": "ar",
  "acceptedTerms": true
}
```

### `POST /auth/login`

```json
{
  "identifier": "user.name",
  "password": "strong-password"
}
```

### `POST /auth/password-reset/request`

Always returns `202` to avoid account enumeration.

## Users

### `GET /users/search?username=value`

Requires bearer token. Returns public limited profile fields:

- `displayName`
- `username`
- `avatarUrl`
- `canReceiveRequests`

## Partnerships

### `POST /partnership-requests`

Creates a pending request by partner username.

```json
{
  "username": "partner.username"
}
```

### `GET /partnership-requests`

Lists pending incoming and outgoing requests for the current user.

### `POST /partnership-requests/:id/accept`

Accepts an incoming request, creates a two-person partnership, creates the default conversation, and moves the relationship to `pending_onboarding`.

### `POST /partnership-requests/:id/reject`

Rejects an incoming pending request.

### `POST /partnership-requests/:id/cancel`

Cancels an outgoing pending request.

### `GET /partnerships/current`

Returns the current `pending_onboarding` or `active` partnership for the authenticated user, or `null`.

### `POST /partnerships/:id/onboarding`

Completes the relationship setup and activates the shared world.

```json
{
  "startDate": "2026-08-03T00:00:00.000Z",
  "worldName": "عالمنا",
  "themeColor": "#B96B7F",
  "answers": {},
  "occasions": []
}
```

## Space

All endpoints require bearer auth and an active partnership.

### `GET /space`

Returns the active world summary: members, world name, days together, latest mood, latest posts, next event, and unread notification count.

### `GET /posts`

Lists recent shared posts.

### `POST /posts`

Creates a shared memory post.

```json
{
  "title": "اختياري",
  "body": "نص الذكرى"
}
```

### `GET /moods`

Lists recent moods.

### `POST /moods`

Creates a mood update.

```json
{
  "kind": "happy",
  "note": "اليوم جميل"
}
```

### `GET /messages`

Lists the shared conversation messages.

### `POST /messages`

Creates an idempotent text message using `clientMessageId`.

```json
{
  "clientMessageId": "m-1",
  "body": "مرحبا"
}
```

### `GET /calendar-events`

Lists shared calendar events.

### `POST /calendar-events`

Creates a manual calendar event.

```json
{
  "title": "موعد",
  "startsAt": "2026-08-03T18:00:00.000Z"
}
```

### `GET /notifications`

Lists recent notifications for the current user.

### `POST /notifications/read-all`

Marks unread notifications as read.

## Error Shape

```json
{
  "code": "validation_failed",
  "message": "المدخلات غير صالحة",
  "details": [],
  "requestId": "request-id"
}
```
