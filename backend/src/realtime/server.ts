import type { Server as HttpServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import jwt from 'jsonwebtoken';
import { Server, type Socket } from 'socket.io';

import { config } from '../config.js';
import { prisma } from '../lib/prisma.js';
import type { AccessTokenPayload } from '../middleware/auth.js';
import type { RealtimeEvent, RealtimeEventType } from './events.js';

let ioInstance: Server | null = null;

export function configureRealtime(server: HttpServer) {
  const io = new Server(server, {
    cors: { origin: config.corsOrigin === '*' ? true : config.corsOrigin }
  });
  ioInstance = io;

  io.use(async (socket, next) => {
    const token = resolveToken(socket);
    if (!token) return next(new Error('unauthorized'));

    try {
      const payload = jwt.verify(token, config.jwtAccessSecret) as AccessTokenPayload;
      const user = await prisma.user.findFirst({
        where: { id: payload.sub, deletedAt: null },
        select: { id: true, username: true }
      });
      if (!user) return next(new Error('unauthorized'));

      socket.data.userId = user.id;
      socket.data.username = user.username;
      next();
    } catch {
      next(new Error('unauthorized'));
    }
  });

  io.on('connection', async (socket) => {
    const userId = socket.data.userId as string;
    socket.join(userRoom(userId));

    const partnershipIds = await joinCurrentPartnershipRooms(socket, userId);
    socket.emit('connected', {
      socketId: socket.id,
      userId,
      partnershipIds
    });

    for (const partnershipId of partnershipIds) {
      emitToPartnership('user.online', userId, partnershipId, { userId });
    }

    socket.on('typing.started', (payload) => {
      void forwardTyping(socket, 'user.typing.started', payload);
    });
    socket.on('typing.stopped', (payload) => {
      void forwardTyping(socket, 'user.typing.stopped', payload);
    });

    socket.on('disconnect', () => {
      for (const partnershipId of partnershipIds) {
        emitToPartnership('user.offline', userId, partnershipId, { userId });
      }
    });
  });

  return io;
}

export function emitToUser(
  userId: string,
  type: RealtimeEventType,
  actorId: string,
  payload: Record<string, unknown>
) {
  emitRoom(userRoom(userId), buildEvent(type, actorId, payload));
}

export function emitToPartnership(
  type: RealtimeEventType,
  actorId: string,
  partnershipId: string,
  payload: Record<string, unknown>
) {
  emitRoom(partnershipRoom(partnershipId), buildEvent(type, actorId, payload, partnershipId));
}

function emitRoom(room: string, event: RealtimeEvent) {
  ioInstance?.to(room).emit('event', event);
}

async function joinCurrentPartnershipRooms(socket: Socket, userId: string) {
  const memberships = await prisma.partnershipMember.findMany({
    where: {
      userId,
      leftAt: null,
      partnership: { status: { in: ['pending_onboarding', 'active'] } }
    },
    select: { partnershipId: true }
  });

  const partnershipIds = memberships.map((membership) => membership.partnershipId);
  for (const partnershipId of partnershipIds) {
    socket.join(partnershipRoom(partnershipId));
  }
  return partnershipIds;
}

async function forwardTyping(
  socket: Socket,
  type: 'user.typing.started' | 'user.typing.stopped',
  payload: unknown
) {
  if (!payload || typeof payload !== 'object') return;
  const partnershipId = (payload as { partnershipId?: unknown }).partnershipId;
  if (typeof partnershipId !== 'string') return;

  const userId = socket.data.userId as string;
  const allowed = await prisma.partnershipMember.findFirst({
    where: {
      userId,
      partnershipId,
      leftAt: null,
      partnership: { status: { in: ['pending_onboarding', 'active'] } }
    },
    select: { id: true }
  });
  if (!allowed) return;

  socket.to(partnershipRoom(partnershipId)).emit(
    'event',
    buildEvent(type, userId, { userId }, partnershipId)
  );
}

function buildEvent(
  type: RealtimeEventType,
  actorId: string,
  payload: Record<string, unknown>,
  partnershipId?: string
): RealtimeEvent {
  const now = new Date().toISOString();
  return {
    eventId: randomUUID(),
    eventVersion: 1,
    type,
    occurredAt: now,
    actorId,
    partnershipId,
    payload,
    serverTimestamp: now
  };
}

function resolveToken(socket: Socket) {
  const authToken = socket.handshake.auth.token;
  if (typeof authToken === 'string') return authToken;

  const header = socket.handshake.headers.authorization;
  if (header?.startsWith('Bearer ')) return header.slice('Bearer '.length);
  return null;
}

function userRoom(userId: string) {
  return `user:${userId}`;
}

function partnershipRoom(partnershipId: string) {
  return `partnership:${partnershipId}`;
}
