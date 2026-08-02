export type RealtimeEventType =
  | 'user.online'
  | 'user.offline'
  | 'user.typing.started'
  | 'user.typing.stopped'
  | 'message.created'
  | 'message.scheduled'
  | 'message.updated'
  | 'message.deleted'
  | 'message.delivered'
  | 'message.read'
  | 'partnership.requested'
  | 'partnership.accepted'
  | 'partnership.rejected'
  | 'mood.updated'
  | 'post.created'
  | 'memory.created'
  | 'tree.leaf.created'
  | 'calendar.event.created'
  | 'occasion.created'
  | 'wish.created'
  | 'goal.created'
  | 'shared_list.created'
  | 'game.updated'
  | 'place.created'
  | 'album.created'
  | 'time_capsule.created'
  | 'music.room.invited'
  | 'music.room.joined'
  | 'music.playback.updated'
  | 'music.queue.updated'
  | 'watch.room.invited'
  | 'watch.room.joined'
  | 'watch.playback.updated'
  | 'notification.created';

export type RealtimeEvent<TPayload extends Record<string, unknown> = Record<string, unknown>> = {
  eventId: string;
  eventVersion: 1;
  type: RealtimeEventType;
  occurredAt: string;
  actorId: string;
  partnershipId?: string;
  payload: TPayload;
  serverTimestamp: string;
};
