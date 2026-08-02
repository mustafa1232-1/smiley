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

Initial event types:

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
- `music.room.invited`
- `music.room.joined`
- `music.playback.updated`
- `music.queue.updated`
- `watch.room.invited`
- `watch.room.joined`
- `watch.playback.updated`
- `notification.created`

Authorization rule: events scoped to a partnership must only be emitted to authenticated sockets whose user is an active member of that partnership.
