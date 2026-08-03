# API

Base path: `/api/v1`

Client offline behavior: the Flutter app queues unsent chat messages and shared posts locally when a request fails with `network_error`, then retries synchronization when the related screen loads again.

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

Creates a short-lived password reset token when the account exists and always returns `202` to avoid account enumeration. The token is only included in the response when `PASSWORD_RESET_DEBUG_TOKEN=true` for local development.

### `POST /auth/password-reset/confirm`

Consumes a reset token, updates the password, and revokes active sessions.

```json
{
  "token": "reset-token",
  "password": "new-strong-password"
}
```

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

### `POST /me/email-verification/request`

Creates a short-lived 6-digit email verification code for the authenticated user. The code is only included in the response when `AUTH_DEBUG_TOKENS=true` for local development.

### `POST /me/email-verification/confirm`

Consumes a valid 6-digit code and marks the user's email as verified.

```json
{
  "code": "123456"
}
```

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

### `GET /relationship-summary?period=month`

Returns a neutral relationship summary for `week`, `month`, `year`, or `anniversary`, computed from real relationship data. The response includes counts for messages, media, tree leaves, music/watch items, places, completed goals, frequent moods, highlights, important occasion, and a timeline.

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

### `POST /posts/:id/reactions`

Sets the current user's reaction on a post and returns the updated post counters.

```json
{
  "value": "heart"
}
```

### `POST /posts/:id/comments`

Adds a comment to a post and returns the updated post counters.

```json
{
  "body": "تعليق قصير"
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

Lists the shared conversation messages, including `assetIds` for message attachments and the current user's `deliveredAt` and `readAt` receipt timestamps when present.

### `POST /messages`

Creates an idempotent text or media message using `clientMessageId`. The request must include a non-empty `body`, at least one uploaded media `assetIds` entry, or both.

```json
{
  "clientMessageId": "m-1",
  "body": "مرحبا",
  "assetIds": ["2a57e5a4-77f4-49b4-9c31-808c614e19c2"]
}
```

### `POST /messages/:id/reactions`

Sets the current user's reaction on a message and returns the updated message counters.

```json
{
  "value": "heart"
}
```

### `POST /messages/:id/pin`

Pins or unpins a message for the current user and returns the updated message counters.

```json
{
  "pinned": true
}
```

### `GET /messages/scheduled`

Lists unsent scheduled messages for the active conversation. Due messages are published before the response is returned.

### `POST /messages/scheduled`

Schedules a text message for a future time. The message is published into the normal conversation when a conversation endpoint runs after `sendAt`.

```json
{
  "body": "رسالة لاحقة",
  "sendAt": "2026-08-04T09:00:00.000Z"
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

### `GET /notifications/preferences`

Lists notification preferences. Defaults are returned even before the user customizes them.

### `PATCH /notifications/preferences`

Updates one notification preference. Quiet hours are stored as `HH:mm` and applied to external push delivery.

```json
{
  "type": "message.created",
  "enabled": true,
  "quietFrom": "22:00",
  "quietTo": "08:00"
}
```

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

### `GET /games`

Lists recent shared games for the active partnership.

### `POST /games`

Creates a persisted game session. Supported `gameType` values are `tic_tac_toe` and `daily_prompt`.

```json
{
  "gameType": "daily_prompt"
}
```

### `POST /games/:id/moves`

Plays one X/O move. The backend validates turn order, occupied cells, winner detection, and draw state.

```json
{
  "position": 4
}
```

### `POST /games/:id/answer`

Submits the current user's answer for a `daily_prompt` game. The game finishes when both partners answer or skip.

```json
{
  "answer": "فيلم هادئ"
}
```

### `POST /games/:id/skip`

Skips the current user's answer for a `daily_prompt` game.

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

Adds a music queue item. Optional `sourceUrl` can store an external track link.

```json
{
  "title": "أغنية",
  "sourceUrl": "https://example.com/track"
}
```

### `POST /music-room/playback`

Records a shared playback event for the music room and updates room status. `eventType` can be `play`, `pause`, `seek`, or `stop`.

```json
{
  "eventType": "play",
  "positionMs": 0
}
```

### `GET /watch-room`

Returns or creates the shared watch room.

### `POST /watch-room/items`

Adds a watch item. Optional `sourceUrl` can store an external video or streaming link.

```json
{
  "title": "فيلم",
  "sourceUrl": "https://example.com/watch"
}
```

### `POST /watch-room/playback`

Records a shared playback event for the watch room and updates room status. `eventType` can be `play`, `pause`, `seek`, or `stop`.

```json
{
  "eventType": "pause",
  "positionMs": 120000
}
```

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
