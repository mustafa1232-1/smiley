import { Router } from 'express';
import { randomUUID } from 'node:crypto';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';

import {
  ensureConversation,
  getCurrentPartnership,
  otherPartnerId,
  requireActivePartnership
} from '../../lib/access.js';
import { AppError } from '../../lib/errors.js';
import { prisma } from '../../lib/prisma.js';
import { createPutUploadUrl } from '../../lib/storage.js';
import { requireAuth } from '../../middleware/auth.js';
import type { RealtimeEventType } from '../../realtime/events.js';
import { emitToPartnership, emitToUser } from '../../realtime/server.js';

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
  category: z.string().trim().max(40).optional(),
  assetIds: z.array(z.string().uuid()).max(20).optional()
});

const eventSchema = z.object({
  title: z.string().trim().min(1).max(120),
  startsAt: z.coerce.date(),
  endsAt: z.coerce.date().optional()
});

const occasionInputSchema = z.object({
  title: z.string().trim().min(1).max(120),
  description: z.string().trim().max(500).optional(),
  date: z.coerce.date(),
  recurrence: z.string().trim().max(40).optional()
});

const messageSchema = z.object({
  clientMessageId: z.string().trim().min(1).max(80),
  body: z.string().trim().min(1).max(4000)
});

const profileSchema = z.object({
  displayName: z.string().trim().min(1).max(80),
  bio: z.string().trim().max(240).optional(),
  searchable: z.boolean().optional(),
  canReceivePartnershipRequests: z.boolean().optional()
});

const settingsSchema = z.object({
  worldName: z.string().trim().min(1).max(80).optional(),
  themeColor: z.string().trim().min(4).max(32).optional()
});

const wishSchema = z.object({
  title: z.string().trim().min(1).max(160)
});

const goalSchema = z.object({
  title: z.string().trim().min(1).max(160),
  dueAt: z.coerce.date().optional(),
  steps: z.array(z.string().trim().min(1).max(140)).max(20).optional()
});

const sharedListSchema = z.object({
  title: z.string().trim().min(1).max(120),
  kind: z.string().trim().min(1).max(40).default('general')
});

const sharedListItemSchema = z.object({
  title: z.string().trim().min(1).max(160)
});

const placeSchema = z.object({
  title: z.string().trim().min(1).max(120),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional()
});

const albumSchema = z.object({
  title: z.string().trim().min(1).max(120)
});

const albumAssetSchema = z.object({
  assetId: z.string().uuid(),
  caption: z.string().trim().max(240).optional()
});

const uploadPresignSchema = z.object({
  mimeType: z.string().trim().min(3).max(120),
  sizeBytes: z.number().int().positive(),
  fileName: z.string().trim().min(1).max(180).optional()
});

const uploadCompleteSchema = z.object({
  checksum: z.string().trim().max(160).optional()
});

const roomItemSchema = z.object({
  title: z.string().trim().min(1).max(160),
  source: z.string().trim().min(1).max(60).default('manual'),
  sourceUrl: z.string().trim().url().optional()
});

const treeLeafSchema = z.object({
  title: z.string().trim().max(120).optional(),
  body: z.string().trim().min(1).max(2000)
});

const timeCapsuleSchema = z.object({
  title: z.string().trim().min(1).max(160),
  body: z.string().trim().max(4000).optional(),
  opensAt: z.coerce.date()
});

const reportSchema = z.object({
  reason: z.string().trim().min(1).max(120),
  details: z.string().trim().max(2000).optional()
});

spaceRouter.get('/me', requireAuth, async (request, response) => {
  const user = await prisma.user.findUniqueOrThrow({
    where: { id: request.user!.sub },
    select: {
      id: true,
      username: true,
      email: true,
      createdAt: true,
      profile: true
    }
  });

  response.json({
    user: {
      id: user.id,
      username: user.username,
      email: user.email,
      createdAt: user.createdAt,
      displayName: user.profile?.displayName ?? 'مستخدم',
      avatarUrl: user.profile?.avatarUrl,
      bio: user.profile?.bio,
      searchable: user.profile?.searchable ?? true,
      canReceivePartnershipRequests:
        user.profile?.canReceivePartnershipRequests ?? true
    }
  });
});

spaceRouter.patch('/me', requireAuth, async (request, response) => {
  const input = profileSchema.parse(request.body);
  const profile = await prisma.userProfile.update({
    where: { userId: request.user!.sub },
    data: {
      displayName: input.displayName,
      bio: input.bio,
      searchable: input.searchable,
      canReceivePartnershipRequests: input.canReceivePartnershipRequests
    }
  });

  response.json({ profile });
});

spaceRouter.patch('/partnerships/current/settings', requireAuth, async (request, response) => {
  const input = settingsSchema.parse(request.body);
  const partnership = await requireActivePartnership(request.user!.sub);
  const settings = await prisma.partnershipSettings.upsert({
    where: { partnershipId: partnership.id },
    update: {
      worldName: input.worldName,
      themeColor: input.themeColor
    },
    create: {
      partnershipId: partnership.id,
      worldName: input.worldName,
      themeColor: input.themeColor
    }
  });

  response.json({ settings });
});

spaceRouter.post('/uploads/presign', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = uploadPresignSchema.parse(request.body);
  const objectKey = buildObjectKey(userId, input.mimeType, input.fileName);
  const signed = await createPutUploadUrl({
    objectKey,
    mimeType: input.mimeType,
    sizeBytes: input.sizeBytes
  });

  const upload = await prisma.upload.create({
    data: {
      userId,
      status: 'pending',
      objectKey,
      mimeType: input.mimeType,
      sizeBytes: BigInt(input.sizeBytes)
    }
  });

  response.status(201).json({
    upload: serializeUpload(upload),
    uploadUrl: signed.uploadUrl,
    headers: signed.headers,
    expiresIn: signed.expiresIn,
    publicUrl: signed.publicUrl
  });
});

spaceRouter.post('/uploads/:id/complete', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = uploadCompleteSchema.parse(request.body);
  const upload = await prisma.upload.findFirst({
    where: {
      id: routeParam(request.params.id),
      userId,
      status: 'pending'
    }
  });

  if (!upload) {
    response.status(404).json({
      code: 'upload_not_found',
      message: 'ملف الرفع غير موجود'
    });
    return;
  }

  const partnership = await getOptionalActivePartnership(userId);
  const asset = await prisma.$transaction(async (tx) => {
    await tx.upload.update({
      where: { id: upload.id },
      data: { status: 'ready' }
    });

    return tx.mediaAsset.upsert({
      where: { objectKey: upload.objectKey },
      update: {
        checksum: input.checksum,
        deletedAt: null
      },
      create: {
        ownerUserId: userId,
        partnershipId: partnership?.id,
        objectKey: upload.objectKey,
        mimeType: upload.mimeType,
        sizeBytes: upload.sizeBytes,
        checksum: input.checksum
      }
    });
  });

  response.json({ asset: serializeMediaAsset(asset) });
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
      media: true,
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
      category: input.category,
      media: input.assetIds?.length
        ? {
            create: await buildPostMediaCreate(userId, partnership.id, input.assetIds)
          }
        : undefined
    },
    include: {
      media: true,
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

spaceRouter.get('/occasions', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.occasion.findMany({
    where: { partnershipId: partnership.id },
    orderBy: { date: 'asc' },
    take: 100
  });
  response.json({ items });
});

spaceRouter.post('/occasions', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = occasionInputSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const occasion = await prisma.occasion.create({
    data: {
      partnershipId: partnership.id,
      title: input.title,
      description: input.description,
      date: input.date,
      recurrence: input.recurrence
    }
  });

  await notifyPartner(partnership, userId, {
    type: 'occasion.created',
    title: 'مناسبة جديدة',
    body: input.title,
    payload: { occasionId: occasion.id }
  });

  response.status(201).json({ occasion });
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

spaceRouter.get('/wishes', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.wish.findMany({
    where: { partnershipId: partnership.id },
    orderBy: [{ completedAt: 'asc' }, { createdAt: 'desc' }],
    take: 100
  });
  response.json({ items });
});

spaceRouter.post('/wishes', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = wishSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const wish = await prisma.wish.create({
    data: {
      partnershipId: partnership.id,
      creatorId: userId,
      title: input.title
    }
  });
  await notifyPartner(partnership, userId, {
    type: 'wish.created',
    title: 'أمنية جديدة',
    body: input.title,
    payload: { wishId: wish.id }
  });
  response.status(201).json({ wish });
});

spaceRouter.post('/wishes/:id/toggle', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const wish = await prisma.wish.findFirstOrThrow({
    where: { id: routeParam(request.params.id), partnershipId: partnership.id }
  });
  const updated = await prisma.wish.update({
    where: { id: wish.id },
    data: { completedAt: wish.completedAt ? null : new Date() }
  });
  response.json({ wish: updated });
});

spaceRouter.get('/goals', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.goal.findMany({
    where: { partnershipId: partnership.id },
    include: { steps: true },
    orderBy: [{ completedAt: 'asc' }, { createdAt: 'desc' }],
    take: 100
  });
  response.json({ items });
});

spaceRouter.post('/goals', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = goalSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const goal = await prisma.goal.create({
    data: {
      partnershipId: partnership.id,
      title: input.title,
      dueAt: input.dueAt,
      steps: {
        create: (input.steps ?? []).map((title) => ({ title }))
      }
    },
    include: { steps: true }
  });
  await notifyPartner(partnership, userId, {
    type: 'goal.created',
    title: 'هدف جديد',
    body: input.title,
    payload: { goalId: goal.id }
  });
  response.status(201).json({ goal });
});

spaceRouter.post('/goals/:id/toggle', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const goal = await prisma.goal.findFirstOrThrow({
    where: { id: routeParam(request.params.id), partnershipId: partnership.id }
  });
  const updated = await prisma.goal.update({
    where: { id: goal.id },
    data: { completedAt: goal.completedAt ? null : new Date() },
    include: { steps: true }
  });
  response.json({ goal: updated });
});

spaceRouter.post('/goal-steps/:id/toggle', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const step = await prisma.goalStep.findFirstOrThrow({
    where: {
      id: routeParam(request.params.id),
      goal: { partnershipId: partnership.id }
    }
  });
  const updated = await prisma.goalStep.update({
    where: { id: step.id },
    data: { completedAt: step.completedAt ? null : new Date() }
  });
  response.json({ step: updated });
});

spaceRouter.get('/shared-lists', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.sharedList.findMany({
    where: { partnershipId: partnership.id },
    include: { items: { orderBy: [{ completedAt: 'asc' }, { title: 'asc' }] } },
    orderBy: { createdAt: 'desc' },
    take: 50
  });
  response.json({ items });
});

spaceRouter.post('/shared-lists', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = sharedListSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const list = await prisma.sharedList.create({
    data: {
      partnershipId: partnership.id,
      title: input.title,
      kind: input.kind
    },
    include: { items: true }
  });
  await notifyPartner(partnership, userId, {
    type: 'shared_list.created',
    title: 'قائمة مشتركة جديدة',
    body: input.title,
    payload: { listId: list.id }
  });
  response.status(201).json({ list });
});

spaceRouter.post('/shared-lists/:id/items', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const input = sharedListItemSchema.parse(request.body);
  const list = await prisma.sharedList.findFirstOrThrow({
    where: { id: routeParam(request.params.id), partnershipId: partnership.id }
  });
  const item = await prisma.sharedListItem.create({
    data: { sharedListId: list.id, title: input.title }
  });
  response.status(201).json({ item });
});

spaceRouter.post('/shared-list-items/:id/toggle', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const item = await prisma.sharedListItem.findFirstOrThrow({
    where: {
      id: routeParam(request.params.id),
      sharedList: { partnershipId: partnership.id }
    }
  });
  const updated = await prisma.sharedListItem.update({
    where: { id: item.id },
    data: { completedAt: item.completedAt ? null : new Date() }
  });
  response.json({ item: updated });
});

spaceRouter.get('/places', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.place.findMany({
    where: { partnershipId: partnership.id },
    orderBy: { createdAt: 'desc' },
    take: 100
  });
  response.json({ items });
});

spaceRouter.post('/places', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = placeSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const place = await prisma.place.create({
    data: {
      partnershipId: partnership.id,
      title: input.title,
      latitude: input.latitude,
      longitude: input.longitude
    }
  });
  await notifyPartner(partnership, userId, {
    type: 'place.created',
    title: 'مكان جديد',
    body: input.title,
    payload: { placeId: place.id }
  });
  response.status(201).json({ place });
});

spaceRouter.get('/albums', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.album.findMany({
    where: { partnershipId: partnership.id },
    include: { items: true },
    orderBy: { createdAt: 'desc' },
    take: 50
  });
  response.json({ items });
});

spaceRouter.post('/albums', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = albumSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const album = await prisma.album.create({
    data: { partnershipId: partnership.id, title: input.title },
    include: { items: true }
  });
  await notifyPartner(partnership, userId, {
    type: 'album.created',
    title: 'ألبوم جديد',
    body: input.title,
    payload: { albumId: album.id }
  });
  response.status(201).json({ album });
});

spaceRouter.post('/albums/:id/items', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = albumAssetSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const album = await prisma.album.findFirstOrThrow({
    where: { id: routeParam(request.params.id), partnershipId: partnership.id }
  });
  await assertMediaAssetAccess(userId, partnership.id, [input.assetId]);
  const item = await prisma.albumItem.create({
    data: {
      albumId: album.id,
      assetId: input.assetId,
      caption: input.caption
    }
  });
  response.status(201).json({ item });
});

spaceRouter.get('/music-room', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const room = await ensureMusicRoom(partnership.id);
  response.json({ room });
});

spaceRouter.post('/music-room/queue', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = roomItemSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const room = await ensureMusicRoom(partnership.id);
  const count = await prisma.musicQueueItem.count({ where: { musicRoomId: room.id } });
  const item = await prisma.musicQueueItem.create({
    data: {
      musicRoomId: room.id,
      title: input.title,
      source: input.source,
      sourceUrl: input.sourceUrl,
      position: count + 1
    }
  });
  await notifyPartner(partnership, userId, {
    type: 'music.queue.updated',
    title: 'أغنية جديدة',
    body: input.title,
    payload: { itemId: item.id }
  });
  response.status(201).json({ item });
});

spaceRouter.get('/watch-room', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const room = await ensureWatchRoom(partnership.id);
  response.json({ room });
});

spaceRouter.post('/watch-room/items', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = roomItemSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const room = await ensureWatchRoom(partnership.id);
  const item = await prisma.watchItem.create({
    data: {
      watchRoomId: room.id,
      title: input.title,
      source: input.source,
      sourceUrl: input.sourceUrl
    }
  });
  await notifyPartner(partnership, userId, {
    type: 'watch.room.invited',
    title: 'فيلم أو حلقة جديدة',
    body: input.title,
    payload: { itemId: item.id }
  });
  response.status(201).json({ item });
});

spaceRouter.get('/tree/today', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const date = startOfUtcDay(new Date());
  const day = await prisma.treeDay.upsert({
    where: {
      partnershipId_date: {
        partnershipId: partnership.id,
        date
      }
    },
    update: {},
    create: {
      partnershipId: partnership.id,
      date
    },
    include: {
      leaves: {
        include: { contributions: true },
        orderBy: { createdAt: 'desc' }
      }
    }
  });
  response.json({ day });
});

spaceRouter.post('/tree/leaves', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = treeLeafSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const date = startOfUtcDay(new Date());
  const day = await prisma.treeDay.upsert({
    where: {
      partnershipId_date: {
        partnershipId: partnership.id,
        date
      }
    },
    update: {},
    create: {
      partnershipId: partnership.id,
      date
    }
  });
  const leaf = await prisma.treeLeaf.create({
    data: {
      treeDayId: day.id,
      title: input.title,
      body: input.body,
      contributions: {
        create: {
          userId,
          body: input.body
        }
      }
    },
    include: { contributions: true }
  });
  await notifyPartner(partnership, userId, {
    type: 'tree.leaf.created',
    title: 'ورقة جديدة في الشجرة',
    body: input.title ?? input.body.slice(0, 120),
    payload: { leafId: leaf.id }
  });
  response.status(201).json({ leaf });
});

spaceRouter.get('/time-capsules', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.timeCapsule.findMany({
    where: { partnershipId: partnership.id },
    orderBy: { opensAt: 'asc' },
    take: 100
  });
  response.json({ items });
});

spaceRouter.post('/time-capsules', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = timeCapsuleSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const capsule = await prisma.timeCapsule.create({
    data: {
      partnershipId: partnership.id,
      creatorId: userId,
      title: input.title,
      body: input.body,
      opensAt: input.opensAt
    }
  });
  await notifyPartner(partnership, userId, {
    type: 'time_capsule.created',
    title: 'كبسولة وقت جديدة',
    body: input.title,
    payload: { capsuleId: capsule.id }
  });
  response.status(201).json({ capsule });
});

spaceRouter.get('/account/export', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const [user, memberships, notifications] = await Promise.all([
    prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true,
        username: true,
        email: true,
        createdAt: true,
        profile: true
      }
    }),
    prisma.partnershipMember.findMany({
      where: { userId },
      include: {
        partnership: {
          include: {
            settings: true,
            dates: true,
            occasions: true,
            posts: { where: { deletedAt: null } },
            moods: true,
            calendarEvents: true,
            wishes: true,
            goals: { include: { steps: true } },
            sharedLists: { include: { items: true } },
            places: true,
            treeDays: { include: { leaves: { include: { contributions: true } } } }
          }
        }
      }
    }),
    prisma.notification.findMany({ where: { userId }, take: 500 })
  ]);

  response.json({
    exportedAt: new Date().toISOString(),
    user,
    partnerships: memberships.map((membership) => membership.partnership),
    notifications
  });
});

spaceRouter.post('/reports', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = reportSchema.parse(request.body);
  const partnership = await getOptionalActivePartnership(userId);
  const report = await prisma.report.create({
    data: {
      reporterId: userId,
      partnershipId: partnership?.id,
      reason: input.reason,
      details: input.details
    }
  });
  response.status(201).json({ report });
});

spaceRouter.delete('/me', requireAuth, async (request, response) => {
  await prisma.user.update({
    where: { id: request.user!.sub },
    data: {
      deletedAt: new Date(),
      refreshTokens: {
        updateMany: {
          where: { revokedAt: null },
          data: { revokedAt: new Date() }
        }
      }
    }
  });
  response.status(204).send();
});

type NotificationInput = {
  type: RealtimeEventType;
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

  const notification = await prisma.notification.create({
    data: {
      userId,
      partnershipId: partnership.id,
      type: input.type,
      title: input.title,
      body: input.body,
      payload: input.payload as Prisma.InputJsonValue | undefined
    }
  });
  emitToUser(userId, 'notification.created', actorId, { notification });
  emitToPartnership(input.type, actorId, partnership.id, input.payload ?? {});
}

function serializePost(post: {
  id: string;
  title: string | null;
  body: string | null;
  memoryDate: Date | null;
  category: string | null;
  createdAt: Date;
  media?: Array<{ assetId: string }>;
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
    assetIds: post.media?.map((item) => item.assetId) ?? [],
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

function startOfUtcDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function routeParam(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}

async function ensureMusicRoom(partnershipId: string) {
  const existing = await prisma.musicRoom.findFirst({
    where: { partnershipId },
    include: { queueItems: { orderBy: { position: 'asc' } } }
  });
  if (existing) return existing;

  return prisma.musicRoom.create({
    data: { partnershipId },
    include: { queueItems: { orderBy: { position: 'asc' } } }
  });
}

async function ensureWatchRoom(partnershipId: string) {
  const existing = await prisma.watchRoom.findFirst({
    where: { partnershipId },
    include: { items: { orderBy: { title: 'asc' } } }
  });
  if (existing) return existing;

  return prisma.watchRoom.create({
    data: { partnershipId },
    include: { items: { orderBy: { title: 'asc' } } }
  });
}

async function getOptionalActivePartnership(userId: string) {
  const partnership = await getCurrentPartnership(userId);
  return partnership?.status === 'active' ? partnership : null;
}

async function buildPostMediaCreate(
  userId: string,
  partnershipId: string,
  assetIds: string[]
) {
  await assertMediaAssetAccess(userId, partnershipId, assetIds);
  return assetIds.map((assetId) => ({ assetId }));
}

async function assertMediaAssetAccess(
  userId: string,
  partnershipId: string,
  assetIds: string[]
) {
  const uniqueAssetIds = [...new Set(assetIds)];
  const count = await prisma.mediaAsset.count({
    where: {
      id: { in: uniqueAssetIds },
      deletedAt: null,
      OR: [
        { ownerUserId: userId },
        { partnershipId }
      ]
    }
  });
  if (count !== uniqueAssetIds.length) {
    throw new AppError(404, 'media_asset_not_found', 'ملف الوسائط غير موجود');
  }
}

function buildObjectKey(userId: string, mimeType: string, fileName?: string) {
  const extension = extensionFromMimeType(mimeType) ?? extensionFromFileName(fileName);
  const suffix = extension ? `.${extension}` : '';
  return `users/${userId}/${new Date().toISOString().slice(0, 10)}/${randomUUID()}${suffix}`;
}

function extensionFromMimeType(mimeType: string) {
  const safe = mimeType.toLowerCase();
  if (safe === 'image/jpeg') return 'jpg';
  if (safe === 'image/png') return 'png';
  if (safe === 'image/webp') return 'webp';
  if (safe === 'image/gif') return 'gif';
  if (safe === 'video/mp4') return 'mp4';
  if (safe === 'audio/mpeg') return 'mp3';
  if (safe === 'audio/mp4') return 'm4a';
  if (safe === 'audio/wav') return 'wav';
  if (safe === 'application/pdf') return 'pdf';
  return null;
}

function extensionFromFileName(fileName?: string) {
  const match = fileName?.toLowerCase().match(/\.([a-z0-9]{1,12})$/);
  return match?.[1] ?? null;
}

function serializeUpload(upload: {
  id: string;
  status: string;
  objectKey: string;
  mimeType: string;
  sizeBytes: bigint;
  createdAt: Date;
}) {
  return {
    id: upload.id,
    status: upload.status,
    objectKey: upload.objectKey,
    mimeType: upload.mimeType,
    sizeBytes: upload.sizeBytes.toString(),
    createdAt: upload.createdAt
  };
}

function serializeMediaAsset(asset: {
  id: string;
  objectKey: string;
  mimeType: string;
  sizeBytes: bigint;
  checksum: string | null;
  createdAt: Date;
}) {
  return {
    id: asset.id,
    objectKey: asset.objectKey,
    mimeType: asset.mimeType,
    sizeBytes: asset.sizeBytes.toString(),
    checksum: asset.checksum,
    createdAt: asset.createdAt
  };
}
