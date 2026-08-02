# Realtime Events

All realtime events use this envelope:

```json
{
  "eventId": "uuid",
  "eventVersion": 1,
  "type": "message.created",
  "occurredAt": "2026-08-02T00:00:00.000Z",
  "actorId": "uuid",
  "partnershipId": "uuid",
  "payload": {},
  "serverTimestamp": "2026-08-02T00:00:00.000Z"
}
```

Runtime:

- Socket.IO is mounted on the same HTTPS origin as the API.
- Clients authenticate with the JWT access token in `handshake.auth.token` or a `Bearer` header.
- Authenticated sockets join `user:{userId}` and every active/pending partnership room they are allowed to see.
- The Flutter client connects after login and refreshes relationship state on partnership and notification events.
- Typing events are accepted as `typing.started` and `typing.stopped` with `{ "partnershipId": "uuid" }`.

Event types:

- `user.online`
- `user.offline`
- `user.typing.started`
- `user.typing.stopped`
- `message.created`
- `message.updated`
- `message.deleted`
- `message.delivered`
- `message.read`
- `partnership.requested`
- `partnership.accepted`
- `partnership.rejected`
- `mood.updated`
- `post.created`
- `memory.created`
- `tree.leaf.created`
- `calendar.event.created`
- `occasion.created`
- `wish.created`
- `goal.created`
- `shared_list.created`
- `place.created`
- `album.created`
- `time_capsule.created`
- `music.room.invited`
- `music.room.joined`
- `music.playback.updated`
- `music.queue.updated`
- `watch.room.invited`
- `watch.room.joined`
- `watch.playback.updated`
- `notification.created`

Authorization rule: events scoped to a partnership must only be emitted to authenticated sockets whose user is an active member of that partnership.
