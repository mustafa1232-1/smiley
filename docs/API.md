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

### `POST /auth/refresh`

Rotates a refresh token and returns a new auth session. Reusing an already rotated token revokes the remaining active refresh tokens for that user.

```json
{
  "refreshToken": "token"
}
```

### `POST /auth/logout`

Revokes the provided refresh token and returns `204`.

```json
{
  "refreshToken": "token"
}
```

### `POST /auth/logout-all`

Requires bearer auth. Revokes all active refresh tokens for the current user.

### `GET /auth/sessions`

Requires bearer auth. Lists recent login sessions and device metadata. The current access-token session is marked with `current: true`.

### `DELETE /auth/sessions/:id`

Requires bearer auth. Revokes the selected session and all refresh tokens linked to it.

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

### `GET /me`

Returns the authenticated user's profile.

### `PATCH /me`

Updates display name, bio, search visibility, and partnership request availability.

### `PATCH /partnerships/current/settings`

Updates active world settings.

```json
{
  "worldName": "عالمنا",
  "themeColor": "#B96B7F"
}
```

### `GET /space`

Returns the active world summary: members, world name, days together, latest mood, latest posts, next event, and unread notification count.

### `GET /posts`

Lists recent shared posts. Each post response includes `assetIds` for attached media.

### `POST /posts`

Creates a shared memory post. Optional `assetIds` attaches uploaded media assets.

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

Lists the shared conversation messages, including the current user's `deliveredAt` and `readAt` receipt timestamps when present.

### `POST /messages`

Creates an idempotent text message using `clientMessageId`.

```json
{
  "clientMessageId": "m-1",
  "body": "مرحبا"
}
```

### `POST /messages/:id/delivered`

Marks a partner message as delivered for the current user and emits `message.delivered`.

### `POST /messages/:id/read`

Marks a partner message as read for the current user and emits `message.read`.

### `POST /messages/read-all`

Marks all unread partner messages in the active conversation as read.

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

### `GET /occasions`

Lists important relationship occasions.

### `POST /occasions`

Creates an occasion.

```json
{
  "title": "مناسبة",
  "date": "2026-08-03T00:00:00.000Z"
}
```

### `GET /notifications`

Lists recent notifications for the current user.

### `POST /notifications/read-all`

Marks unread notifications as read.

### `POST /notifications/push-tokens`

Registers or refreshes the current device push token. The backend stores the token encrypted and sends FCM notifications when Firebase variables are configured.

```json
{
  "platform": "android",
  "token": "device-push-token"
}
```

### `DELETE /notifications/push-tokens`

Revokes a device push token for the current user.

### `GET /wishes`

Lists shared wishes.

### `POST /wishes`

Creates a wish.

### `POST /wishes/:id/toggle`

Toggles wish completion.

### `GET /goals`

Lists shared goals with steps.

### `POST /goals`

Creates a goal with optional steps.

```json
{
  "title": "هدف مشترك",
  "steps": ["خطوة أولى", "خطوة ثانية"]
}
```

### `POST /goals/:id/toggle`

Toggles goal completion.

### `POST /goal-steps/:id/toggle`

Toggles goal step completion.

### `GET /shared-lists`

Lists shared lists and their items.

### `POST /shared-lists`

Creates a shared list.

### `POST /shared-lists/:id/items`

Adds an item to a shared list.

### `POST /shared-list-items/:id/toggle`

Toggles shared list item completion.

### `GET /places`

Lists saved places for the memory map.

### `POST /places`

Creates a saved place.

### `POST /uploads/presign`

Creates a pending upload and returns a signed PUT URL for Cloudflare R2/S3-compatible storage.

```json
{
  "fileName": "memory.jpg",
  "mimeType": "image/jpeg",
  "sizeBytes": 2450000
}
```

Response includes:

- `upload.id`: pass this to `/uploads/:id/complete` after the PUT succeeds.
- `uploadUrl`: signed URL for the direct file upload.
- `headers`: required request headers for the PUT request.
- `publicUrl`: public object URL when `R2_PUBLIC_BASE_URL` is configured.

If storage environment variables are missing, the API returns `503 storage_not_configured`.

### `POST /uploads/:id/complete`

Marks a pending upload as ready and creates or updates its media asset.

```json
{
  "checksum": "optional-client-checksum"
}
```

### `GET /albums`

Lists albums.

### `POST /albums`

Creates an album.

### `POST /albums/:id/items`

Adds an uploaded media asset to an album.

```json
{
  "assetId": "00000000-0000-0000-0000-000000000000",
  "caption": "اختياري"
}
```

### `GET /music-room`

Returns or creates the shared music room.

### `POST /music-room/queue`

Adds a music queue item.

### `GET /watch-room`

Returns or creates the shared watch room.

### `POST /watch-room/items`

Adds a watch item.

### `GET /tree/today`

Returns or creates today's memory tree day.

### `POST /tree/leaves`

Creates a daily tree leaf.

### `GET /time-capsules`

Lists time capsules for the active partnership.

### `POST /time-capsules`

Creates a time capsule.

### `GET /account/export`

Exports the authenticated user's profile and relationship data.

### `POST /reports`

Creates an abuse/support report.

### `DELETE /me`

Soft-deletes the authenticated user and revokes active refresh tokens.

## Error Shape

```json
{
  "code": "validation_failed",
  "message": "المدخلات غير صالحة",
  "details": [],
  "requestId": "request-id"
}
```
