import { Router } from 'express';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';

import {
  ensureConversation,
  otherPartnerId,
  requireActivePartnership
} from '../../lib/access.js';
import { prisma } from '../../lib/prisma.js';
import { requireAuth } from '../../middleware/auth.js';

export const spaceRouter = Router();

const moodSchema = z.object({
  kind: z.string().trim().min(1).max(40),
  emoji: z.string().trim().max(16).optional(),
  note: z.string().trim().max(240).optional()
});

const postSchema = z.object({
  title: z.string().trim().max(120).optional(),
  body: z.string().trim().min(1).max(4000),
  memoryDate: z.coerce.date().optional(),
  category: z.string().trim().max(40).optional()
});

const eventSchema = z.object({
  title: z.string().trim().min(1).max(120),
  startsAt: z.coerce.date(),
  endsAt: z.coerce.date().optional()
});

const messageSchema = z.object({
  clientMessageId: z.string().trim().min(1).max(80),
  body: z.string().trim().min(1).max(4000)
});

spaceRouter.get('/space', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);

  const [latestMood, latestPosts, nextEvent, unreadNotifications] = await Promise.all([
    prisma.mood.findFirst({
      where: { partnershipId: partnership.id },
      include: {
        user: { select: { username: true, profile: { select: { displayName: true } } } }
      },
      orderBy: { createdAt: 'desc' }
    }),
    prisma.post.findMany({
      where: { partnershipId: partnership.id, deletedAt: null },
      orderBy: { createdAt: 'desc' },
      take: 5
    }),
    prisma.calendarEvent.findFirst({
      where: { partnershipId: partnership.id, startsAt: { gte: new Date() } },
      orderBy: { startsAt: 'asc' }
    }),
    prisma.notification.count({
      where: { userId, readAt: null }
    })
  ]);

  response.json({
    partnership: {
      id: partnership.id,
      status: partnership.status,
      worldName: partnership.settings?.worldName,
      startedAt: partnership.startedAt,
      daysTogether: partnership.startedAt ? daysBetween(partnership.startedAt, new Date()) : null,
      members: partnership.members.map((member) => ({
        id: member.user.id,
        username: member.user.username,
        displayName: member.user.profile?.displayName ?? 'مستخدم',
        avatarUrl: member.user.profile?.avatarUrl
      }))
    },
    latestMood: latestMood
      ? {
          id: latestMood.id,
          kind: latestMood.kind,
          emoji: latestMood.emoji,
          note: latestMood.note,
          createdAt: latestMood.createdAt,
          user: {
            username: latestMood.user.username,
            displayName: latestMood.user.profile?.displayName ?? 'مستخدم'
          }
        }
      : null,
    latestPosts: latestPosts.map(serializePost),
    nextEvent,
    unreadNotifications
  });
});

spaceRouter.get('/moods', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.mood.findMany({
    where: { partnershipId: partnership.id },
    orderBy: { createdAt: 'desc' },
    take: 50
  });
  response.json({ items });
});

spaceRouter.post('/moods', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = moodSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);

  const mood = await prisma.mood.create({
    data: {
      partnershipId: partnership.id,
      userId,
      kind: input.kind,
      emoji: input.emoji,
      note: input.note
    }
  });

  await notifyPartner(partnership, userId, {
    type: 'mood.updated',
    title: 'تم تحديث المزاج',
    body: input.note ?? input.kind,
    payload: { moodId: mood.id }
  });

  response.status(201).json({ mood });
});

spaceRouter.get('/posts', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const posts = await prisma.post.findMany({
    where: { partnershipId: partnership.id, deletedAt: null },
    include: {
      author: { select: { username: true, profile: { select: { displayName: true } } } }
    },
    orderBy: { createdAt: 'desc' },
    take: 50
  });
  response.json({ items: posts.map(serializePost) });
});

spaceRouter.post('/posts', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = postSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);

  const post = await prisma.post.create({
    data: {
      partnershipId: partnership.id,
      authorId: userId,
      title: input.title,
      body: input.body,
      memoryDate: input.memoryDate,
      category: input.category
    },
    include: {
      author: { select: { username: true, profile: { select: { displayName: true } } } }
    }
  });

  await notifyPartner(partnership, userId, {
    type: 'post.created',
    title: 'ذكرى جديدة',
    body: input.title ?? input.body.slice(0, 120),
    payload: { postId: post.id }
  });

  response.status(201).json({ post: serializePost(post) });
});

spaceRouter.get('/calendar-events', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const events = await prisma.calendarEvent.findMany({
    where: { partnershipId: partnership.id },
    orderBy: { startsAt: 'asc' },
    take: 100
  });
  response.json({ items: events });
});

spaceRouter.post('/calendar-events', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = eventSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);

  const event = await prisma.calendarEvent.create({
    data: {
      partnershipId: partnership.id,
      title: input.title,
      startsAt: input.startsAt,
      endsAt: input.endsAt,
      sourceType: 'manual'
    }
  });

  await notifyPartner(partnership, userId, {
    type: 'calendar.event.created',
    title: 'موعد جديد',
    body: input.title,
    payload: { eventId: event.id }
  });

  response.status(201).json({ event });
});

spaceRouter.get('/messages', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const conversation = await prisma.conversation.findFirst({
    where: { partnershipId: partnership.id }
  });

  if (!conversation) {
    response.json({ items: [] });
    return;
  }

  const messages = await prisma.message.findMany({
    where: { conversationId: conversation.id, deletedAt: null },
    include: {
      sender: { select: { username: true, profile: { select: { displayName: true } } } }
    },
    orderBy: { serverTimestamp: 'desc' },
    take: 100
  });

  response.json({ items: messages.reverse().map(serializeMessage) });
});

spaceRouter.post('/messages', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = messageSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);

  const message = await prisma.$transaction(async (tx) => {
    const conversation = await ensureConversation(
      tx,
      partnership.id,
      partnership.members.map((member) => member.userId)
    );

    const existing = await tx.message.findUnique({
      where: {
        conversationId_clientMessageId: {
          conversationId: conversation.id,
          clientMessageId: input.clientMessageId
        }
      },
      include: {
        sender: { select: { username: true, profile: { select: { displayName: true } } } }
      }
    });
    if (existing) return existing;

    return tx.message.create({
      data: {
        conversationId: conversation.id,
        senderId: userId,
        clientMessageId: input.clientMessageId,
        kind: 'text',
        body: input.body
      },
      include: {
        sender: { select: { username: true, profile: { select: { displayName: true } } } }
      }
    });
  });

  await notifyPartner(partnership, userId, {
    type: 'message.created',
    title: 'رسالة جديدة',
    body: input.body.slice(0, 120),
    payload: { messageId: message.id }
  });

  response.status(201).json({ message: serializeMessage(message) });
});

spaceRouter.get('/notifications', requireAuth, async (request, response) => {
  const items = await prisma.notification.findMany({
    where: { userId: request.user!.sub },
    orderBy: { createdAt: 'desc' },
    take: 50
  });
  response.json({ items });
});

spaceRouter.post('/notifications/read-all', requireAuth, async (request, response) => {
  await prisma.notification.updateMany({
    where: { userId: request.user!.sub, readAt: null },
    data: { readAt: new Date() }
  });
  response.status(204).send();
});

type NotificationInput = {
  type: string;
  title: string;
  body?: string;
  payload?: Record<string, unknown>;
};

async function notifyPartner(
  partnership: { id: string; members: Array<{ userId: string }> },
  actorId: string,
  input: NotificationInput
) {
  const userId = otherPartnerId(partnership, actorId);
  if (!userId) return;

  await prisma.notification.create({
    data: {
      userId,
      partnershipId: partnership.id,
      type: input.type,
      title: input.title,
      body: input.body,
      payload: input.payload as Prisma.InputJsonValue | undefined
    }
  });
}

function serializePost(post: {
  id: string;
  title: string | null;
  body: string | null;
  memoryDate: Date | null;
  category: string | null;
  createdAt: Date;
  author?: {
    username: string;
    profile: { displayName: string } | null;
  };
}) {
  return {
    id: post.id,
    title: post.title,
    body: post.body,
    memoryDate: post.memoryDate,
    category: post.category,
    createdAt: post.createdAt,
    author: post.author
      ? {
          username: post.author.username,
          displayName: post.author.profile?.displayName ?? 'مستخدم'
        }
      : null
  };
}

function serializeMessage(message: {
  id: string;
  clientMessageId: string;
  body: string | null;
  serverTimestamp: Date;
  sender?: {
    username: string;
    profile: { displayName: string } | null;
  };
}) {
  return {
    id: message.id,
    clientMessageId: message.clientMessageId,
    body: message.body,
    serverTimestamp: message.serverTimestamp,
    sender: message.sender
      ? {
          username: message.sender.username,
          displayName: message.sender.profile?.displayName ?? 'مستخدم'
        }
      : null
  };
}

function daysBetween(start: Date, end: Date) {
  const startDay = Date.UTC(start.getUTCFullYear(), start.getUTCMonth(), start.getUTCDate());
  const endDay = Date.UTC(end.getUTCFullYear(), end.getUTCMonth(), end.getUTCDate());
  return Math.max(0, Math.floor((endDay - startDay) / 86_400_000) + 1);
}
