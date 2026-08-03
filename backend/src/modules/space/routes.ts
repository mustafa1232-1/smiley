import { Router } from 'express';
import { randomInt, randomUUID } from 'node:crypto';
import bcrypt from 'bcryptjs';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';

import { config } from '../../config.js';
import {
  ensureConversation,
  getCurrentPartnership,
  otherPartnerId,
  requireActivePartnership
} from '../../lib/access.js';
import { AppError } from '../../lib/errors.js';
import { prisma } from '../../lib/prisma.js';
import { encryptPushToken, hashPushToken, sendPushToUser } from '../../lib/push.js';
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

const postReactionSchema = z.object({
  value: z.string().trim().min(1).max(24).default('heart')
});

const postCommentSchema = z.object({
  body: z.string().trim().min(1).max(1000)
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
  body: z.string().trim().max(4000).optional(),
  assetIds: z.array(z.string().uuid()).max(10).optional()
});

const messageReactionSchema = z.object({
  value: z.string().trim().min(1).max(24).default('heart')
});

const messageUpdateSchema = z.object({
  body: z.string().trim().min(1).max(4000)
});

const messagePinSchema = z.object({
  pinned: z.boolean().default(true)
});

const scheduledMessageSchema = z.object({
  body: z.string().trim().min(1).max(4000),
  sendAt: z.coerce.date()
});

const messageReceiptSchema = z.object({
  messageId: z.string().uuid()
});

const profileSchema = z.object({
  displayName: z.string().trim().min(1).max(80),
  bio: z.string().trim().max(240).optional(),
  searchable: z.boolean().optional(),
  canReceivePartnershipRequests: z.boolean().optional()
});

const emailVerificationSchema = z.object({
  code: z.string().trim().regex(/^\d{6}$/)
});

const settingsSchema = z.object({
  worldName: z.string().trim().min(1).max(80).optional(),
  themeColor: z.string().trim().min(4).max(32).optional()
});

const relationshipSummaryQuerySchema = z.object({
  period: z.enum(['week', 'month', 'year', 'anniversary']).default('month'),
  referenceDate: z.coerce.date().optional()
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

const gameCreateSchema = z.object({
  gameType: z.enum(['tic_tac_toe', 'daily_prompt']).default('tic_tac_toe')
});

const gameMoveSchema = z.object({
  position: z.number().int().min(0).max(8)
});

const gamePromptAnswerSchema = z.object({
  answer: z.string().trim().min(1).max(500)
});

const placeSchema = z.object({
  title: z.string().trim().min(1).max(120),
  latitude: z.number().min(-90).max(90).optional(),
  longitude: z.number().min(-180).max(180).optional()
});

const placeVisitSchema = z.object({
  visitedAt: z.coerce.date().optional()
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

const defaultNotificationTypes = [
  'message.created',
  'message.scheduled',
  'partnership.requested',
  'post.created',
  'post.updated',
  'mood.updated',
  'calendar.event.created',
  'occasion.created',
  'wish.created',
  'goal.created',
  'shared_list.created',
  'game.updated',
  'music.queue.updated',
  'music.playback.updated',
  'watch.playback.updated'
];

const notificationPreferenceSchema = z.object({
  type: z.string().trim().min(1).max(80),
  enabled: z.boolean(),
  quietFrom: z.string().trim().regex(/^\d{2}:\d{2}$/).nullable().optional(),
  quietTo: z.string().trim().regex(/^\d{2}:\d{2}$/).nullable().optional()
});

const pushTokenSchema = z.object({
  token: z.string().trim().min(20).max(4096),
  platform: z.string().trim().min(2).max(20)
});

const roomItemSchema = z.object({
  title: z.string().trim().min(1).max(160),
  source: z.string().trim().min(1).max(60).default('manual'),
  sourceUrl: z.string().trim().url().optional()
});

const roomPlaybackSchema = z.object({
  eventType: z.enum(['play', 'pause', 'seek', 'stop']),
  positionMs: z.number().int().min(0).max(86_400_000).optional()
});

const treeLeafSchema = z.object({
  title: z.string().trim().max(120).optional(),
  body: z.string().trim().min(1).max(2000)
});

const treeLeafContributionSchema = z.object({
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
      emailVerifiedAt: true,
      createdAt: true,
      profile: true
    }
  });

  response.json({
    user: {
      id: user.id,
      username: user.username,
      email: user.email,
      emailVerifiedAt: user.emailVerifiedAt,
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

spaceRouter.post('/me/email-verification/request', requireAuth, async (request, response) => {
  const user = await prisma.user.findUniqueOrThrow({
    where: { id: request.user!.sub },
    select: { id: true, email: true, emailVerifiedAt: true }
  });
  if (!user.email) {
    throw new AppError(409, 'email_missing', 'لا يوجد بريد إلكتروني للتحقق');
  }
  if (user.emailVerifiedAt) {
    response.status(202).json({ status: 'already_verified' });
    return;
  }

  const code = randomInt(0, 1_000_000).toString().padStart(6, '0');
  await prisma.verificationCode.create({
    data: {
      userId: user.id,
      channel: 'email',
      codeHash: await bcrypt.hash(code, config.bcryptCost),
      expiresAt: new Date(Date.now() + 15 * 60 * 1000)
    }
  });

  request.log?.info({ userId: user.id, channel: 'email' }, 'email verification code created');
  response.status(202).json({
    status: 'accepted',
    ...(config.exposeAuthDebugTokens ? { code } : {})
  });
});

spaceRouter.post('/me/email-verification/confirm', requireAuth, async (request, response) => {
  const input = emailVerificationSchema.parse(request.body);
  const codes = await prisma.verificationCode.findMany({
    where: {
      userId: request.user!.sub,
      channel: 'email',
      usedAt: null,
      expiresAt: { gt: new Date() }
    },
    orderBy: { createdAt: 'desc' },
    take: 5
  });

  let matched: (typeof codes)[number] | undefined;
  for (const code of codes) {
    if (await bcrypt.compare(input.code, code.codeHash)) {
      matched = code;
      break;
    }
  }

  if (!matched) {
    throw new AppError(400, 'invalid_verification_code', 'رمز التحقق غير صالح');
  }

  await prisma.$transaction(async (tx) => {
    await tx.verificationCode.update({
      where: { id: matched.id },
      data: { usedAt: new Date() }
    });
    await tx.user.update({
      where: { id: request.user!.sub },
      data: { emailVerifiedAt: new Date() }
    });
  });

  response.status(204).send();
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
      include: postResponseInclude(userId),
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

spaceRouter.get('/relationship-summary', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = relationshipSummaryQuerySchema.parse(request.query);
  const partnership = await requireActivePartnership(userId);
  const range = relationshipSummaryRange(input.period, input.referenceDate ?? new Date(), partnership.startedAt);
  const conversation = await prisma.conversation.findFirst({
    where: { partnershipId: partnership.id }
  });
  if (conversation) {
    await publishDueScheduledMessages(partnership, conversation.id);
  }

  const [counts, topMoods, highlightedPosts, importantOccasion, timeline] = await Promise.all([
    relationshipSummaryCounts(partnership.id, conversation?.id, range.start, range.end),
    relationshipSummaryMoods(partnership.id, range.start, range.end),
    relationshipSummaryHighlights(partnership.id, range.start, range.end),
    relationshipSummaryOccasion(partnership.id, range.start, range.end),
    relationshipSummaryTimeline(partnership.id, range.start, range.end)
  ]);

  response.json({
    period: input.period,
    start: range.start,
    end: range.end,
    title: relationshipSummaryTitle(input.period, range.start, range.end),
    counts,
    topMoods,
    highlights: highlightedPosts,
    importantOccasion,
    timeline
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
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const posts = await prisma.post.findMany({
    where: { partnershipId: partnership.id, deletedAt: null },
    include: postResponseInclude(userId),
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
    include: postResponseInclude(userId)
  });

  await notifyPartner(partnership, userId, {
    type: 'post.created',
    title: 'ذكرى جديدة',
    body: input.title ?? input.body.slice(0, 120),
    payload: { postId: post.id }
  });

  response.status(201).json({ post: serializePost(post) });
});

spaceRouter.post('/posts/:id/reactions', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = postReactionSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const postId = routeParam(request.params.id);

  const post = await prisma.$transaction(async (tx) => {
    const existing = await tx.post.findFirst({
      where: { id: postId, partnershipId: partnership.id, deletedAt: null }
    });
    if (!existing) {
      throw new AppError(404, 'post_not_found', 'المنشور غير موجود');
    }

    await tx.postReaction.deleteMany({ where: { postId, userId } });
    await tx.postReaction.create({
      data: { postId, userId, value: input.value }
    });

    return tx.post.findFirstOrThrow({
      where: { id: postId },
      include: postResponseInclude(userId)
    });
  });

  emitToPartnership('post.updated', userId, partnership.id, { postId });
  response.json({ post: serializePost(post) });
});

spaceRouter.post('/posts/:id/comments', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = postCommentSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const postId = routeParam(request.params.id);

  const post = await prisma.$transaction(async (tx) => {
    const existing = await tx.post.findFirst({
      where: { id: postId, partnershipId: partnership.id, deletedAt: null }
    });
    if (!existing) {
      throw new AppError(404, 'post_not_found', 'المنشور غير موجود');
    }

    await tx.postComment.create({
      data: { postId, authorId: userId, body: input.body }
    });

    return tx.post.findFirstOrThrow({
      where: { id: postId },
      include: postResponseInclude(userId)
    });
  });

  emitToPartnership('post.updated', userId, partnership.id, { postId });
  await notifyPartner(partnership, userId, {
    type: 'post.updated',
    title: 'تعليق جديد',
    body: input.body,
    payload: { postId }
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
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const conversation = await prisma.conversation.findFirst({
    where: { partnershipId: partnership.id }
  });

  if (!conversation) {
    response.json({ items: [] });
    return;
  }

  await publishDueScheduledMessages(partnership, conversation.id);

  const messages = await prisma.message.findMany({
    where: { conversationId: conversation.id, deletedAt: null },
    include: messageResponseInclude(userId),
    orderBy: { serverTimestamp: 'desc' },
    take: 100
  });

  response.json({ items: messages.reverse().map(serializeMessage) });
});

spaceRouter.get('/messages/scheduled', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const conversation = await prisma.conversation.findFirst({
    where: { partnershipId: partnership.id }
  });

  if (!conversation) {
    response.json({ items: [] });
    return;
  }

  await publishDueScheduledMessages(partnership, conversation.id);

  const items = await prisma.scheduledMessage.findMany({
    where: { conversationId: conversation.id, sentAt: null },
    orderBy: { sendAt: 'asc' },
    take: 50
  });

  response.json({ items: items.map(serializeScheduledMessage) });
});

spaceRouter.post('/messages/scheduled', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = scheduledMessageSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  if (input.sendAt.getTime() <= Date.now()) {
    throw new AppError(422, 'send_at_must_be_future', 'اختر وقتاً مستقبلياً للإرسال');
  }

  const scheduledMessage = await prisma.$transaction(async (tx) => {
    const conversation = await ensureConversation(
      tx,
      partnership.id,
      partnership.members.map((member) => member.userId)
    );
    return tx.scheduledMessage.create({
      data: {
        conversationId: conversation.id,
        senderId: userId,
        body: input.body,
        sendAt: input.sendAt
      }
    });
  });

  await notifyPartner(partnership, userId, {
    type: 'message.scheduled',
    title: 'رسالة مجدولة',
    body: `رسالة ستصل في ${input.sendAt.toISOString()}`,
    payload: { scheduledMessageId: scheduledMessage.id }
  });

  response.status(201).json({ scheduledMessage: serializeScheduledMessage(scheduledMessage) });
});

spaceRouter.post('/messages', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = messageSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const body = input.body?.trim() ?? '';
  const assetIds = [...new Set(input.assetIds ?? [])];

  if (!body && assetIds.length === 0) {
    throw new AppError(422, 'message_empty', 'اكتب رسالة أو أضف مرفقاً');
  }

  if (assetIds.length > 0) {
    await assertMediaAssetAccess(userId, partnership.id, assetIds);
  }

  const currentConversation = await prisma.conversation.findFirst({
    where: { partnershipId: partnership.id }
  });
  if (currentConversation) {
    await publishDueScheduledMessages(partnership, currentConversation.id);
  }

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
      include: messageResponseInclude(userId)
    });
    if (existing) return existing;

    return tx.message.create({
      data: {
        conversationId: conversation.id,
        senderId: userId,
        clientMessageId: input.clientMessageId,
        kind: assetIds.length > 0 ? 'file' : 'text',
        body: body || null,
        attachments: assetIds.length
          ? { create: assetIds.map((assetId) => ({ assetId, kind: 'media' })) }
          : undefined
      },
      include: messageResponseInclude(userId)
    });
  });

  await notifyPartner(partnership, userId, {
    type: 'message.created',
    title: 'رسالة جديدة',
    body: body ? body.slice(0, 120) : 'مرفق جديد',
    payload: { messageId: message.id }
  });

  response.status(201).json({ message: serializeMessage(message) });
});

spaceRouter.patch('/messages/:id', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = messageUpdateSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const messageId = routeParam(request.params.id);

  const message = await prisma.$transaction(async (tx) => {
    const existing = await tx.message.findFirst({
      where: {
        id: messageId,
        deletedAt: null,
        conversation: { partnershipId: partnership.id }
      }
    });
    if (!existing) {
      throw new AppError(404, 'message_not_found', 'الرسالة غير موجودة');
    }
    if (existing.senderId !== userId) {
      throw new AppError(403, 'message_not_owned', 'يمكن تعديل رسائلك فقط');
    }

    return tx.message.update({
      where: { id: messageId },
      data: { body: input.body, editedAt: new Date() },
      include: messageResponseInclude(userId)
    });
  });

  emitToPartnership('message.updated', userId, partnership.id, { messageId });
  response.json({ message: serializeMessage(message) });
});

spaceRouter.delete('/messages/:id', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const messageId = routeParam(request.params.id);

  await prisma.$transaction(async (tx) => {
    const existing = await tx.message.findFirst({
      where: {
        id: messageId,
        deletedAt: null,
        conversation: { partnershipId: partnership.id }
      }
    });
    if (!existing) {
      throw new AppError(404, 'message_not_found', 'الرسالة غير موجودة');
    }
    if (existing.senderId !== userId) {
      throw new AppError(403, 'message_not_owned', 'يمكن حذف رسائلك فقط');
    }

    await tx.message.update({
      where: { id: messageId },
      data: { deletedAt: new Date() }
    });
  });

  emitToPartnership('message.deleted', userId, partnership.id, { messageId });
  response.status(204).send();
});

spaceRouter.post('/messages/:id/reactions', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = messageReactionSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const messageId = routeParam(request.params.id);

  const message = await prisma.$transaction(async (tx) => {
    const existing = await tx.message.findFirst({
      where: {
        id: messageId,
        deletedAt: null,
        conversation: { partnershipId: partnership.id }
      }
    });
    if (!existing) {
      throw new AppError(404, 'message_not_found', 'الرسالة غير موجودة');
    }

    await tx.messageReaction.deleteMany({ where: { messageId, userId } });
    await tx.messageReaction.create({
      data: { messageId, userId, value: input.value }
    });

    return tx.message.findFirstOrThrow({
      where: { id: messageId },
      include: messageResponseInclude(userId)
    });
  });

  emitToPartnership('message.updated', userId, partnership.id, { messageId });
  response.json({ message: serializeMessage(message) });
});

spaceRouter.post('/messages/:id/pin', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = messagePinSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const messageId = routeParam(request.params.id);

  const message = await prisma.$transaction(async (tx) => {
    const existing = await tx.message.findFirst({
      where: {
        id: messageId,
        deletedAt: null,
        conversation: { partnershipId: partnership.id }
      }
    });
    if (!existing) {
      throw new AppError(404, 'message_not_found', 'الرسالة غير موجودة');
    }

    await tx.messagePin.deleteMany({ where: { messageId, userId } });
    if (input.pinned) {
      await tx.messagePin.create({ data: { messageId, userId } });
    }

    return tx.message.findFirstOrThrow({
      where: { id: messageId },
      include: messageResponseInclude(userId)
    });
  });

  emitToPartnership('message.updated', userId, partnership.id, { messageId });
  response.json({ message: serializeMessage(message) });
});

spaceRouter.post('/messages/:id/delivered', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const input = messageReceiptSchema.parse({ messageId: routeParam(request.params.id) });
  const receipt = await markMessageReceipt(
    userId,
    partnership.id,
    input.messageId,
    'delivered'
  );
  emitToPartnership('message.delivered', userId, partnership.id, {
    messageId: receipt.messageId,
    userId,
    deliveredAt: receipt.deliveredAt
  });
  response.json({ receipt });
});

spaceRouter.post('/messages/:id/read', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const input = messageReceiptSchema.parse({ messageId: routeParam(request.params.id) });
  const receipt = await markMessageReceipt(
    userId,
    partnership.id,
    input.messageId,
    'read'
  );
  emitToPartnership('message.read', userId, partnership.id, {
    messageId: receipt.messageId,
    userId,
    readAt: receipt.readAt
  });
  response.json({ receipt });
});

spaceRouter.post('/messages/read-all', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);
  const conversation = await prisma.conversation.findFirst({
    where: { partnershipId: partnership.id }
  });

  if (!conversation) {
    response.status(204).send();
    return;
  }

  const unread = await prisma.message.findMany({
    where: {
      conversationId: conversation.id,
      senderId: { not: userId },
      deletedAt: null,
      receipts: { none: { userId, readAt: { not: null } } }
    },
    select: { id: true }
  });
  if (unread.length === 0) {
    response.status(204).send();
    return;
  }

  const now = new Date();
  await prisma.$transaction(
    unread.map((message) =>
      prisma.messageReceipt.upsert({
        where: { messageId_userId: { messageId: message.id, userId } },
        update: { deliveredAt: now, readAt: now },
        create: { messageId: message.id, userId, deliveredAt: now, readAt: now }
      })
    )
  );

  emitToPartnership('message.read', userId, partnership.id, {
    messageIds: unread.map((message) => message.id),
    userId,
    readAt: now
  });
  response.status(204).send();
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

spaceRouter.get('/notifications/preferences', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const saved = await prisma.notificationPreference.findMany({
    where: { userId },
    orderBy: { type: 'asc' }
  });
  const byType = new Map(saved.map((item) => [item.type, item]));
  const types = [...new Set([...defaultNotificationTypes, ...saved.map((item) => item.type)])];
  response.json({
    items: types.map((type) =>
      serializeNotificationPreference(
        byType.get(type) ?? {
          id: null,
          userId,
          type,
          enabled: true,
          quietFrom: null,
          quietTo: null,
          updatedAt: null
        }
      )
    )
  });
});

spaceRouter.patch('/notifications/preferences', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = notificationPreferenceSchema.parse(request.body);
  const item = await prisma.notificationPreference.upsert({
    where: {
      userId_type: {
        userId,
        type: input.type
      }
    },
    update: {
      enabled: input.enabled,
      quietFrom: input.quietFrom ?? null,
      quietTo: input.quietTo ?? null
    },
    create: {
      userId,
      type: input.type,
      enabled: input.enabled,
      quietFrom: input.quietFrom ?? null,
      quietTo: input.quietTo ?? null
    }
  });
  response.json({ preference: serializeNotificationPreference(item) });
});

spaceRouter.post('/notifications/push-tokens', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = pushTokenSchema.parse(request.body);
  const tokenHash = hashPushToken(input.token);
  const item = await prisma.pushToken.upsert({
    where: { tokenHash },
    update: {
      userId,
      platform: input.platform,
      tokenCiphertext: encryptPushToken(input.token),
      revokedAt: null,
      failureCount: 0,
      lastSeenAt: new Date()
    },
    create: {
      userId,
      platform: input.platform,
      tokenHash,
      tokenCiphertext: encryptPushToken(input.token),
      lastSeenAt: new Date()
    }
  });
  response.status(201).json({
    token: {
      id: item.id,
      platform: item.platform,
      lastSeenAt: item.lastSeenAt,
      createdAt: item.createdAt
    }
  });
});

spaceRouter.delete('/notifications/push-tokens', requireAuth, async (request, response) => {
  const input = pushTokenSchema.pick({ token: true }).parse(request.body);
  await prisma.pushToken.updateMany({
    where: {
      userId: request.user!.sub,
      tokenHash: hashPushToken(input.token),
      revokedAt: null
    },
    data: { revokedAt: new Date() }
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

spaceRouter.get('/games', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.gameSession.findMany({
    where: { partnershipId: partnership.id },
    orderBy: { updatedAt: 'desc' },
    take: 20
  });
  response.json({ items: items.map(serializeGameSession) });
});

spaceRouter.post('/games', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = gameCreateSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const gamePlayers = [
    userId,
    ...partnership.members.map((member) => member.userId).filter((id) => id !== userId)
  ].slice(0, 2);

  const game = await prisma.gameSession.create({
    data: {
      partnershipId: partnership.id,
      gameType: input.gameType,
      status: 'active',
      state: input.gameType === 'daily_prompt'
        ? initialDailyPromptState(gamePlayers)
        : initialTicTacToeState(gamePlayers),
      currentTurnUserId: input.gameType === 'daily_prompt' ? null : gamePlayers[0],
      createdById: userId
    }
  });
  emitToPartnership('game.updated', userId, partnership.id, { gameId: game.id });
  response.status(201).json({ game: serializeGameSession(game) });
});

spaceRouter.post('/games/:id/moves', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = gameMoveSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);

  const game = await prisma.$transaction(async (tx) => {
    const existing = await tx.gameSession.findFirst({
      where: {
        id: routeParam(request.params.id),
        partnershipId: partnership.id
      }
    });
    if (!existing) {
      throw new AppError(404, 'game_not_found', 'Ø§Ù„Ù„Ø¹Ø¨Ø© ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯Ø©');
    }
    if (existing.gameType !== 'tic_tac_toe') {
      throw new AppError(409, 'unsupported_game_move', 'هذه اللعبة لا تستخدم خانات X/O');
    }
    if (existing.status !== 'active') {
      throw new AppError(409, 'game_finished', 'Ø§Ù†ØªÙ‡Øª Ø§Ù„Ù„Ø¹Ø¨Ø©');
    }
    if (existing.currentTurnUserId !== userId) {
      throw new AppError(409, 'not_your_turn', 'Ù„ÙŠØ³ Ø¯ÙˆØ±Ùƒ Ø§Ù„Ø¢Ù†');
    }

    const next = applyTicTacToeMove(
      normalizeTicTacToeState(existing.state, partnership.members.map((member) => member.userId)),
      userId,
      input.position
    );

    return tx.gameSession.update({
      where: { id: existing.id },
      data: {
        state: next.state as Prisma.InputJsonValue,
        status: next.status,
        winnerUserId: next.winnerUserId,
        currentTurnUserId: next.currentTurnUserId
      }
    });
  });

  emitToPartnership('game.updated', userId, partnership.id, { gameId: game.id });
  response.json({ game: serializeGameSession(game) });
});

spaceRouter.post('/games/:id/answer', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = gamePromptAnswerSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);

  const game = await prisma.$transaction(async (tx) => {
    const existing = await tx.gameSession.findFirst({
      where: { id: routeParam(request.params.id), partnershipId: partnership.id }
    });
    if (!existing) {
      throw new AppError(404, 'game_not_found', 'اللعبة غير موجودة');
    }
    if (existing.gameType !== 'daily_prompt') {
      throw new AppError(409, 'unsupported_game_answer', 'هذه اللعبة لا تقبل إجابات نصية');
    }
    if (existing.status !== 'active') {
      throw new AppError(409, 'game_finished', 'انتهت اللعبة');
    }

    const next = applyDailyPromptAnswer(
      normalizeDailyPromptState(existing.state, partnership.members.map((member) => member.userId)),
      userId,
      input.answer
    );

    return tx.gameSession.update({
      where: { id: existing.id },
      data: {
        state: next.state as Prisma.InputJsonValue,
        status: next.status,
        currentTurnUserId: null
      }
    });
  });

  emitToPartnership('game.updated', userId, partnership.id, { gameId: game.id });
  response.json({ game: serializeGameSession(game) });
});

spaceRouter.post('/games/:id/skip', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const partnership = await requireActivePartnership(userId);

  const game = await prisma.$transaction(async (tx) => {
    const existing = await tx.gameSession.findFirst({
      where: { id: routeParam(request.params.id), partnershipId: partnership.id }
    });
    if (!existing) {
      throw new AppError(404, 'game_not_found', 'اللعبة غير موجودة');
    }
    if (existing.gameType !== 'daily_prompt') {
      throw new AppError(409, 'unsupported_game_skip', 'هذه اللعبة لا تدعم التخطي');
    }
    if (existing.status !== 'active') {
      throw new AppError(409, 'game_finished', 'انتهت اللعبة');
    }

    const next = applyDailyPromptSkip(
      normalizeDailyPromptState(existing.state, partnership.members.map((member) => member.userId)),
      userId
    );

    return tx.gameSession.update({
      where: { id: existing.id },
      data: {
        state: next.state as Prisma.InputJsonValue,
        status: next.status,
        currentTurnUserId: null
      }
    });
  });

  emitToPartnership('game.updated', userId, partnership.id, { gameId: game.id });
  response.json({ game: serializeGameSession(game) });
});

spaceRouter.get('/places', requireAuth, async (request, response) => {
  const partnership = await requireActivePartnership(request.user!.sub);
  const items = await prisma.place.findMany({
    where: { partnershipId: partnership.id },
    include: placeResponseInclude,
    orderBy: { createdAt: 'desc' },
    take: 100
  });
  response.json({ items: items.map(serializePlace) });
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
    },
    include: placeResponseInclude
  });
  await notifyPartner(partnership, userId, {
    type: 'place.created',
    title: 'مكان جديد',
    body: input.title,
    payload: { placeId: place.id }
  });
  response.status(201).json({ place: serializePlace(place) });
});

spaceRouter.post('/places/:id/visits', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = placeVisitSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const place = await prisma.place.findFirst({
    where: { id: routeParam(request.params.id), partnershipId: partnership.id }
  });
  if (!place) {
    throw new AppError(404, 'place_not_found', 'المكان غير موجود');
  }

  const visit = await prisma.placeVisit.create({
    data: {
      placeId: place.id,
      visitedAt: input.visitedAt ?? new Date()
    }
  });
  emitToPartnership('place.created', userId, partnership.id, {
    placeId: place.id,
    visitId: visit.id
  });
  response.status(201).json({ visit });
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

spaceRouter.post('/music-room/playback', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = roomPlaybackSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const room = await ensureMusicRoom(partnership.id);

  const event = await prisma.musicPlaybackEvent.create({
    data: {
      musicRoomId: room.id,
      actorId: userId,
      eventType: input.eventType,
      positionMs: input.positionMs
    }
  });
  const updated = await prisma.musicRoom.update({
    where: { id: room.id },
    data: { status: playbackStatus(input.eventType) },
    include: musicRoomInclude
  });

  emitToPartnership('music.playback.updated', userId, partnership.id, {
    roomId: room.id,
    eventId: event.id,
    eventType: event.eventType,
    positionMs: event.positionMs
  });
  response.json({ room: updated });
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

spaceRouter.post('/watch-room/playback', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = roomPlaybackSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const room = await ensureWatchRoom(partnership.id);

  const event = await prisma.watchPlaybackEvent.create({
    data: {
      watchRoomId: room.id,
      actorId: userId,
      eventType: input.eventType,
      positionMs: input.positionMs
    }
  });
  const updated = await prisma.watchRoom.update({
    where: { id: room.id },
    data: { status: playbackStatus(input.eventType) },
    include: watchRoomInclude
  });

  emitToPartnership('watch.playback.updated', userId, partnership.id, {
    roomId: room.id,
    eventId: event.id,
    eventType: event.eventType,
    positionMs: event.positionMs
  });
  response.json({ room: updated });
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

spaceRouter.post('/tree/leaves/:id/contributions', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const input = treeLeafContributionSchema.parse(request.body);
  const partnership = await requireActivePartnership(userId);
  const leaf = await prisma.treeLeaf.findFirst({
    where: {
      id: routeParam(request.params.id),
      treeDay: { partnershipId: partnership.id }
    }
  });
  if (!leaf) {
    throw new AppError(404, 'tree_leaf_not_found', 'الورقة غير موجودة');
  }

  const contribution = await prisma.treeLeafContribution.create({
    data: {
      treeLeafId: leaf.id,
      userId,
      body: input.body
    }
  });
  emitToPartnership('tree.leaf.created', userId, partnership.id, {
    leafId: leaf.id,
    contributionId: contribution.id
  });
  response.status(201).json({ contribution });
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
  void shouldSendPush(userId, input.type)
    .then((allowed) => {
      if (!allowed) return;
      return sendPushToUser(userId, {
        notificationId: notification.id,
        type: input.type,
        title: input.title,
        body: input.body,
        payload: input.payload
      });
    })
    .catch((error) => {
      console.error(JSON.stringify({ level: 'error', message: 'push_send_failed', error }));
    });
}

async function shouldSendPush(userId: string, type: string) {
  const preference = await prisma.notificationPreference.findUnique({
    where: { userId_type: { userId, type } }
  });
  if (!preference) return true;
  if (!preference.enabled) return false;
  if (preference.quietFrom && preference.quietTo) {
    return !isNowInsideQuietHours(preference.quietFrom, preference.quietTo);
  }
  return true;
}

function isNowInsideQuietHours(quietFrom: string, quietTo: string) {
  const now = new Date();
  const current = now.getUTCHours() * 60 + now.getUTCMinutes();
  const from = minutesFromClock(quietFrom);
  const to = minutesFromClock(quietTo);
  if (from === to) return false;
  if (from < to) return current >= from && current < to;
  return current >= from || current < to;
}

function minutesFromClock(value: string) {
  const [hours, minutes] = value.split(':').map(Number);
  return hours * 60 + minutes;
}

function serializeNotificationPreference(preference: {
  id: string | null;
  userId: string;
  type: string;
  enabled: boolean;
  quietFrom: string | null;
  quietTo: string | null;
  updatedAt: Date | null;
}) {
  return {
    id: preference.id,
    type: preference.type,
    enabled: preference.enabled,
    quietFrom: preference.quietFrom,
    quietTo: preference.quietTo,
    updatedAt: preference.updatedAt
  };
}

async function markMessageReceipt(
  userId: string,
  partnershipId: string,
  messageId: string,
  mode: 'delivered' | 'read'
) {
  const message = await prisma.message.findFirst({
    where: {
      id: messageId,
      deletedAt: null,
      conversation: { partnershipId }
    }
  });
  if (!message) {
    throw new AppError(404, 'message_not_found', 'Ø§Ù„Ø±Ø³Ø§Ù„Ø© ØºÙŠØ± Ù…ÙˆØ¬ÙˆØ¯Ø©');
  }
  if (message.senderId === userId) {
    throw new AppError(409, 'own_message_receipt', 'Ù„Ø§ ÙŠÙ…ÙƒÙ† ØªØ­Ø¯ÙŠØ« Ø¥ÙŠØµØ§Ù„ Ø±Ø³Ø§Ù„ØªÙƒ');
  }

  const now = new Date();
  return prisma.messageReceipt.upsert({
    where: {
      messageId_userId: {
        messageId,
        userId
      }
    },
    update:
      mode === 'read'
        ? { deliveredAt: now, readAt: now }
        : { deliveredAt: now },
    create: {
      messageId,
      userId,
      deliveredAt: now,
      readAt: mode === 'read' ? now : undefined
    }
  });
}

type TicTacToeState = {
  board: Array<string | null>;
  players: string[];
  symbols: Record<string, 'x' | 'o'>;
};

type DailyPromptState = {
  prompt: string;
  options: string[];
  players: string[];
  answers: Record<string, string>;
  skipped: string[];
};

const dailyPromptBank = [
  {
    prompt: 'أي نشاط بسيط تختارانه لهذا الأسبوع؟',
    options: ['مشي قصير', 'فيلم', 'طبخة جديدة', 'مكالمة هادئة']
  },
  {
    prompt: 'أي تفصيل صغير أسعدك اليوم؟',
    options: ['رسالة', 'صورة', 'موقف لطيف', 'وقت هادئ']
  },
  {
    prompt: 'هذا أو ذاك لليلة القادمة؟',
    options: ['قهوة', 'شاي', 'فيلم', 'موسيقى']
  },
  {
    prompt: 'اختر فكرة ذكرى جديدة.',
    options: ['صورة', 'ورقة شجرة', 'مكان', 'أغنية']
  }
];

function initialTicTacToeState(players: string[]): Prisma.InputJsonValue {
  const orderedPlayers = players.slice(0, 2);
  return {
    board: Array<string | null>(9).fill(null),
    players: orderedPlayers,
    symbols: {
      ...(orderedPlayers[0] ? { [orderedPlayers[0]]: 'x' } : {}),
      ...(orderedPlayers[1] ? { [orderedPlayers[1]]: 'o' } : {})
    }
  };
}

function normalizeTicTacToeState(value: unknown, players: string[]): TicTacToeState {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  const board = Array.isArray(raw.board)
    ? raw.board.map((cell) => (cell === 'x' || cell === 'o' ? cell : null)).slice(0, 9)
    : [];
  while (board.length < 9) board.push(null);

  const normalizedPlayers = Array.isArray(raw.players)
    ? raw.players.map(String).slice(0, 2)
    : players.slice(0, 2);
  const symbols = raw.symbols && typeof raw.symbols === 'object'
    ? (raw.symbols as Record<string, 'x' | 'o'>)
    : {
        ...(normalizedPlayers[0] ? { [normalizedPlayers[0]]: 'x' as const } : {}),
        ...(normalizedPlayers[1] ? { [normalizedPlayers[1]]: 'o' as const } : {})
      };

  return { board, players: normalizedPlayers, symbols };
}

function initialDailyPromptState(players: string[]): Prisma.InputJsonValue {
  const prompt = dailyPromptBank[Math.floor(Math.random() * dailyPromptBank.length)];
  return {
    prompt: prompt.prompt,
    options: prompt.options,
    players: players.slice(0, 2),
    answers: {},
    skipped: []
  };
}

function normalizeDailyPromptState(value: unknown, players: string[]): DailyPromptState {
  const raw = value && typeof value === 'object' ? (value as Record<string, unknown>) : {};
  const fallback = dailyPromptBank[0];
  const answers = raw.answers && typeof raw.answers === 'object'
    ? Object.fromEntries(
        Object.entries(raw.answers as Record<string, unknown>).map(([key, value]) => [key, String(value)])
      )
    : {};
  const skipped = Array.isArray(raw.skipped) ? raw.skipped.map(String) : [];
  return {
    prompt: typeof raw.prompt === 'string' ? raw.prompt : fallback.prompt,
    options: Array.isArray(raw.options) ? raw.options.map(String).slice(0, 6) : fallback.options,
    players: Array.isArray(raw.players) ? raw.players.map(String).slice(0, 2) : players.slice(0, 2),
    answers,
    skipped
  };
}

function applyDailyPromptAnswer(state: DailyPromptState, userId: string, answer: string) {
  if (!state.players.includes(userId)) {
    throw new AppError(403, 'not_game_player', 'لست مشاركاً في هذه اللعبة');
  }
  const nextState: DailyPromptState = {
    ...state,
    answers: { ...state.answers, [userId]: answer.trim() },
    skipped: state.skipped.filter((id) => id !== userId)
  };
  return {
    state: nextState,
    status: dailyPromptFinished(nextState) ? 'finished' : 'active'
  };
}

function applyDailyPromptSkip(state: DailyPromptState, userId: string) {
  if (!state.players.includes(userId)) {
    throw new AppError(403, 'not_game_player', 'لست مشاركاً في هذه اللعبة');
  }
  const nextState: DailyPromptState = {
    ...state,
    answers: Object.fromEntries(Object.entries(state.answers).filter(([id]) => id !== userId)),
    skipped: [...new Set([...state.skipped, userId])]
  };
  return {
    state: nextState,
    status: dailyPromptFinished(nextState) ? 'finished' : 'active'
  };
}

function dailyPromptFinished(state: DailyPromptState) {
  return state.players.length > 0
    && state.players.every((player) => state.answers[player] || state.skipped.includes(player));
}

function applyTicTacToeMove(
  state: TicTacToeState,
  userId: string,
  position: number
) {
  const symbol = state.symbols[userId];
  if (!symbol) {
    throw new AppError(403, 'not_game_player', 'Ù„Ø³Øª Ù„Ø§Ø¹Ø¨Ø§Ù‹ ÙÙŠ Ù‡Ø°Ù‡ Ø§Ù„Ù„Ø¹Ø¨Ø©');
  }
  if (state.board[position]) {
    throw new AppError(409, 'cell_taken', 'Ø§Ù„Ø®Ø§Ù†Ø© Ù…Ø­Ø¬ÙˆØ²Ø©');
  }

  const board = [...state.board];
  board[position] = symbol;
  const winningSymbol = ticTacToeWinner(board);
  const winnerUserId = winningSymbol
    ? Object.entries(state.symbols).find(([, value]) => value === winningSymbol)?.[0] ?? null
    : null;
  const draw = !winnerUserId && board.every(Boolean);
  const nextUserId = state.players.find((player) => player !== userId) ?? null;
  const finished = Boolean(winnerUserId || draw || !nextUserId);

  return {
    state: { ...state, board },
    status: finished ? 'finished' : 'active',
    winnerUserId,
    currentTurnUserId: finished ? null : nextUserId
  };
}

function ticTacToeWinner(board: Array<string | null>) {
  const lines = [
    [0, 1, 2],
    [3, 4, 5],
    [6, 7, 8],
    [0, 3, 6],
    [1, 4, 7],
    [2, 5, 8],
    [0, 4, 8],
    [2, 4, 6]
  ];
  for (const [a, b, c] of lines) {
    if (board[a] && board[a] === board[b] && board[a] === board[c]) {
      return board[a];
    }
  }
  return null;
}

function serializeGameSession(game: {
  id: string;
  gameType: string;
  status: string;
  state: Prisma.JsonValue;
  currentTurnUserId: string | null;
  winnerUserId: string | null;
  createdById: string;
  createdAt: Date;
  updatedAt: Date;
}) {
  if (game.gameType === 'daily_prompt') {
    const state = normalizeDailyPromptState(game.state, []);
    return {
      id: game.id,
      gameType: game.gameType,
      status: game.status,
      prompt: state.prompt,
      options: state.options,
      players: state.players,
      answers: state.answers,
      skipped: state.skipped,
      currentTurnUserId: game.currentTurnUserId,
      winnerUserId: game.winnerUserId,
      createdById: game.createdById,
      createdAt: game.createdAt,
      updatedAt: game.updatedAt
    };
  }
  const state = normalizeTicTacToeState(game.state, []);
  return {
    id: game.id,
    gameType: game.gameType,
    status: game.status,
    board: state.board,
    players: state.players,
    symbols: state.symbols,
    currentTurnUserId: game.currentTurnUserId,
    winnerUserId: game.winnerUserId,
    createdById: game.createdById,
    createdAt: game.createdAt,
    updatedAt: game.updatedAt
  };
}

const placeResponseInclude = {
  visits: { orderBy: { visitedAt: 'desc' as const } }
};

function serializePlace(place: {
  id: string;
  title: string;
  latitude: Prisma.Decimal | null;
  longitude: Prisma.Decimal | null;
  createdAt: Date;
  visits?: Array<{ visitedAt: Date }>;
}) {
  return {
    id: place.id,
    title: place.title,
    latitude: place.latitude?.toNumber() ?? null,
    longitude: place.longitude?.toNumber() ?? null,
    createdAt: place.createdAt,
    visitCount: place.visits?.length ?? 0,
    lastVisitedAt: place.visits?.[0]?.visitedAt ?? null
  };
}

function postResponseInclude(userId: string) {
  return {
    media: true,
    author: { select: { username: true, profile: { select: { displayName: true } } } },
    reactions: { where: { userId }, select: { value: true } },
    _count: { select: { reactions: true, comments: true } }
  };
}

function serializePost(post: {
  id: string;
  title: string | null;
  body: string | null;
  memoryDate: Date | null;
  category: string | null;
  createdAt: Date;
  media?: Array<{ assetId: string }>;
  reactions?: Array<{ value: string }>;
  _count?: { reactions: number; comments: number };
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
    reactionCount: post._count?.reactions ?? 0,
    commentCount: post._count?.comments ?? 0,
    myReaction: post.reactions?.[0]?.value ?? null,
    author: post.author
      ? {
          username: post.author.username,
          displayName: post.author.profile?.displayName ?? 'مستخدم'
        }
      : null
  };
}

function serializeScheduledMessage(message: {
  id: string;
  body: string;
  sendAt: Date;
  sentAt: Date | null;
  createdAt: Date;
}) {
  return {
    id: message.id,
    body: message.body,
    sendAt: message.sendAt,
    sentAt: message.sentAt,
    createdAt: message.createdAt
  };
}

function messageResponseInclude(userId: string) {
  return {
    attachments: true,
    receipts: { where: { userId } },
    reactions: { where: { userId }, select: { value: true } },
    pins: { where: { userId }, select: { id: true } },
    _count: { select: { reactions: true, pins: true } },
    sender: { select: { username: true, profile: { select: { displayName: true } } } }
  };
}

function serializeMessage(message: {
  id: string;
  clientMessageId: string;
  body: string | null;
  serverTimestamp: Date;
  editedAt: Date | null;
  attachments?: Array<{ assetId: string | null }>;
  receipts?: Array<{
    deliveredAt: Date | null;
    readAt: Date | null;
  }>;
  reactions?: Array<{ value: string }>;
  pins?: Array<{ id: string }>;
  _count?: { reactions: number; pins: number };
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
    editedAt: message.editedAt,
    assetIds: (message.attachments ?? [])
      .map((item) => item.assetId)
      .filter((assetId): assetId is string => Boolean(assetId)),
    deliveredAt: message.receipts?.[0]?.deliveredAt ?? null,
    readAt: message.receipts?.[0]?.readAt ?? null,
    reactionCount: message._count?.reactions ?? 0,
    myReaction: message.reactions?.[0]?.value ?? null,
    pinCount: message._count?.pins ?? 0,
    pinnedByMe: Boolean(message.pins?.length),
    sender: message.sender
      ? {
          username: message.sender.username,
          displayName: message.sender.profile?.displayName ?? 'مستخدم'
        }
      : null
  };
}

async function publishDueScheduledMessages(
  partnership: { id: string; members: Array<{ userId: string }> },
  conversationId: string
) {
  const due = await prisma.scheduledMessage.findMany({
    where: {
      conversationId,
      sentAt: null,
      sendAt: { lte: new Date() }
    },
    orderBy: { sendAt: 'asc' },
    take: 20
  });

  for (const scheduled of due) {
    const message = await prisma.$transaction(async (tx) => {
      const claimed = await tx.scheduledMessage.updateMany({
        where: { id: scheduled.id, sentAt: null },
        data: { sentAt: new Date() }
      });
      if (claimed.count === 0) return null;

      return tx.message.create({
        data: {
          conversationId,
          senderId: scheduled.senderId,
          clientMessageId: `scheduled-${scheduled.id}`,
          kind: 'text',
          body: scheduled.body,
          serverTimestamp: scheduled.sendAt
        },
        include: {
          attachments: true,
          sender: { select: { username: true, profile: { select: { displayName: true } } } }
        }
      });
    });

    if (!message) continue;
    await notifyPartner(partnership, scheduled.senderId, {
      type: 'message.created',
      title: 'رسالة مجدولة وصلت',
      body: scheduled.body.slice(0, 120),
      payload: { messageId: message.id, scheduledMessageId: scheduled.id }
    });
  }
}

function relationshipSummaryRange(period: string, reference: Date, startedAt: Date | null) {
  const ref = startOfUtcDay(reference);
  if (period === 'week') {
    const day = ref.getUTCDay();
    const mondayOffset = day === 0 ? -6 : 1 - day;
    const start = addUtcDays(ref, mondayOffset);
    return { start, end: addUtcDays(start, 7) };
  }
  if (period === 'year') {
    const start = new Date(Date.UTC(ref.getUTCFullYear(), 0, 1));
    return { start, end: new Date(Date.UTC(ref.getUTCFullYear() + 1, 0, 1)) };
  }
  if (period === 'anniversary' && startedAt) {
    const start = new Date(Date.UTC(ref.getUTCFullYear(), startedAt.getUTCMonth(), startedAt.getUTCDate()));
    const adjustedStart = start > ref
      ? new Date(Date.UTC(ref.getUTCFullYear() - 1, startedAt.getUTCMonth(), startedAt.getUTCDate()))
      : start;
    return {
      start: adjustedStart,
      end: new Date(Date.UTC(adjustedStart.getUTCFullYear() + 1, startedAt.getUTCMonth(), startedAt.getUTCDate()))
    };
  }
  const start = new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth(), 1));
  return { start, end: new Date(Date.UTC(ref.getUTCFullYear(), ref.getUTCMonth() + 1, 1)) };
}

function relationshipSummaryTitle(period: string, start: Date, end: Date) {
  if (period === 'week') return 'ملخص الأسبوع';
  if (period === 'year') return `ملخص ${start.getUTCFullYear()}`;
  if (period === 'anniversary') return 'ملخص الذكرى السنوية';
  return `ملخص ${start.getUTCFullYear()}-${String(start.getUTCMonth() + 1).padStart(2, '0')}`;
}

async function relationshipSummaryCounts(
  partnershipId: string,
  conversationId: string | undefined,
  start: Date,
  end: Date
) {
  const dateRange = { gte: start, lt: end };
  const [
    messages,
    photos,
    videos,
    treeLeaves,
    songs,
    watchItems,
    places,
    completedGoals
  ] = await Promise.all([
    conversationId
      ? prisma.message.count({
          where: { conversationId, deletedAt: null, serverTimestamp: dateRange }
        })
      : 0,
    prisma.mediaAsset.count({
      where: { partnershipId, deletedAt: null, mimeType: { startsWith: 'image/' }, createdAt: dateRange }
    }),
    prisma.mediaAsset.count({
      where: { partnershipId, deletedAt: null, mimeType: { startsWith: 'video/' }, createdAt: dateRange }
    }),
    prisma.treeLeaf.count({
      where: { createdAt: dateRange, treeDay: { partnershipId } }
    }),
    prisma.musicQueueItem.count({
      where: { musicRoom: { partnershipId } }
    }),
    prisma.watchItem.count({
      where: { watchRoom: { partnershipId } }
    }),
    prisma.place.count({
      where: { partnershipId, createdAt: dateRange }
    }),
    prisma.goal.count({
      where: { partnershipId, completedAt: dateRange }
    })
  ]);

  return {
    messages,
    photos,
    videos,
    treeLeaves,
    songs,
    watchSessions: watchItems,
    places,
    completedGoals
  };
}

async function relationshipSummaryMoods(partnershipId: string, start: Date, end: Date) {
  const grouped = await prisma.mood.groupBy({
    by: ['kind', 'emoji'],
    where: { partnershipId, createdAt: { gte: start, lt: end } },
    _count: { _all: true },
    orderBy: { _count: { kind: 'desc' } },
    take: 5
  });

  return grouped.map((item) => ({
    kind: item.kind,
    emoji: item.emoji,
    count: item._count._all
  }));
}

async function relationshipSummaryHighlights(partnershipId: string, start: Date, end: Date) {
  const posts = await prisma.post.findMany({
    where: { partnershipId, deletedAt: null, createdAt: { gte: start, lt: end } },
    include: { _count: { select: { reactions: true, comments: true } } },
    orderBy: { createdAt: 'desc' },
    take: 20
  });

  return posts
    .sort((a, b) =>
      (b._count.reactions + b._count.comments) - (a._count.reactions + a._count.comments)
    )
    .slice(0, 5)
    .map((post) => ({
      id: post.id,
      title: post.title,
      body: post.body,
      createdAt: post.createdAt,
      reactions: post._count.reactions,
      comments: post._count.comments
    }));
}

async function relationshipSummaryOccasion(partnershipId: string, start: Date, end: Date) {
  const occasion = await prisma.occasion.findFirst({
    where: { partnershipId, date: { gte: start, lt: end } },
    orderBy: { date: 'asc' }
  });
  if (occasion) {
    return {
      id: occasion.id,
      title: occasion.title,
      date: occasion.date,
      type: 'occasion'
    };
  }

  const event = await prisma.calendarEvent.findFirst({
    where: { partnershipId, startsAt: { gte: start, lt: end } },
    orderBy: { startsAt: 'asc' }
  });
  return event
    ? {
        id: event.id,
        title: event.title,
        date: event.startsAt,
        type: 'calendar_event'
      }
    : null;
}

async function relationshipSummaryTimeline(partnershipId: string, start: Date, end: Date) {
  const [posts, events, moods, leaves, goals, places, capsules] = await Promise.all([
    prisma.post.findMany({
      where: { partnershipId, deletedAt: null, createdAt: { gte: start, lt: end } },
      select: { id: true, title: true, body: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: 10
    }),
    prisma.calendarEvent.findMany({
      where: { partnershipId, startsAt: { gte: start, lt: end } },
      select: { id: true, title: true, startsAt: true },
      orderBy: { startsAt: 'desc' },
      take: 10
    }),
    prisma.mood.findMany({
      where: { partnershipId, createdAt: { gte: start, lt: end } },
      select: { id: true, kind: true, emoji: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: 10
    }),
    prisma.treeLeaf.findMany({
      where: { createdAt: { gte: start, lt: end }, treeDay: { partnershipId } },
      select: { id: true, title: true, body: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: 10
    }),
    prisma.goal.findMany({
      where: { partnershipId, completedAt: { gte: start, lt: end } },
      select: { id: true, title: true, completedAt: true },
      orderBy: { completedAt: 'desc' },
      take: 10
    }),
    prisma.place.findMany({
      where: { partnershipId, createdAt: { gte: start, lt: end } },
      select: { id: true, title: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: 10
    }),
    prisma.timeCapsule.findMany({
      where: { partnershipId, createdAt: { gte: start, lt: end } },
      select: { id: true, title: true, createdAt: true },
      orderBy: { createdAt: 'desc' },
      take: 10
    })
  ]);

  return [
    ...posts.map((item) => timelineItem('post', item.id, item.title ?? item.body ?? 'ذكرى', item.createdAt)),
    ...events.map((item) => timelineItem('calendar_event', item.id, item.title, item.startsAt)),
    ...moods.map((item) => timelineItem('mood', item.id, `${item.emoji ?? ''} ${item.kind}`.trim(), item.createdAt)),
    ...leaves.map((item) => timelineItem('tree_leaf', item.id, item.title ?? item.body ?? 'ورقة شجرة', item.createdAt)),
    ...goals.map((item) => timelineItem('goal_completed', item.id, item.title, item.completedAt ?? start)),
    ...places.map((item) => timelineItem('place', item.id, item.title, item.createdAt)),
    ...capsules.map((item) => timelineItem('time_capsule', item.id, item.title, item.createdAt))
  ]
    .sort((a, b) => b.occurredAt.getTime() - a.occurredAt.getTime())
    .slice(0, 30);
}

function timelineItem(type: string, id: string, title: string, occurredAt: Date) {
  return { type, id, title, occurredAt };
}

function addUtcDays(date: Date, days: number) {
  return new Date(date.getTime() + days * 86_400_000);
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

const musicRoomInclude = {
  queueItems: { orderBy: { position: 'asc' as const } },
  playbackEvents: { orderBy: { createdAt: 'desc' as const }, take: 1 }
};

const watchRoomInclude = {
  items: { orderBy: { title: 'asc' as const } },
  playbackEvents: { orderBy: { createdAt: 'desc' as const }, take: 1 }
};

async function ensureMusicRoom(partnershipId: string) {
  const existing = await prisma.musicRoom.findFirst({
    where: { partnershipId },
    include: musicRoomInclude
  });
  if (existing) return existing;

  return prisma.musicRoom.create({
    data: { partnershipId },
    include: musicRoomInclude
  });
}

async function ensureWatchRoom(partnershipId: string) {
  const existing = await prisma.watchRoom.findFirst({
    where: { partnershipId },
    include: watchRoomInclude
  });
  if (existing) return existing;

  return prisma.watchRoom.create({
    data: { partnershipId },
    include: watchRoomInclude
  });
}

function playbackStatus(eventType: 'play' | 'pause' | 'seek' | 'stop') {
  if (eventType === 'play' || eventType === 'seek') return 'playing';
  if (eventType === 'pause') return 'paused';
  return 'idle';
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
