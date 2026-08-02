import { Router } from 'express';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';

import {
  assertNoLivePartnership,
  ensureConversation,
  getCurrentPartnership
} from '../../lib/access.js';
import { AppError } from '../../lib/errors.js';
import { prisma } from '../../lib/prisma.js';
import { sendPushToUser } from '../../lib/push.js';
import { requireAuth } from '../../middleware/auth.js';
import { emitToUser } from '../../realtime/server.js';

export const partnershipsRouter = Router();

const requestSchema = z.object({
  username: z.string().trim().min(3).max(30)
});

const occasionSchema = z.object({
  title: z.string().trim().min(1).max(80),
  date: z.coerce.date(),
  recurrence: z.string().trim().max(40).optional()
});

const onboardingSchema = z.object({
  startDate: z.coerce.date(),
  worldName: z.string().trim().min(1).max(80),
  themeColor: z.string().trim().min(4).max(32).optional(),
  answers: z.record(z.string(), z.unknown()).optional(),
  occasions: z.array(occasionSchema).max(20).optional()
});

partnershipsRouter.post('/partnership-requests', requireAuth, async (request, response) => {
  const input = requestSchema.parse(request.body);
  const requesterId = request.user!.sub;
  const receiver = await prisma.user.findUnique({
    where: { usernameNormalized: input.username.toLowerCase() },
    include: { profile: true }
  });

  if (!receiver || receiver.id === requesterId || receiver.deletedAt) {
    throw new AppError(404, 'user_not_found', 'لا يمكن إرسال الطلب');
  }
  if (!receiver.profile?.canReceivePartnershipRequests) {
    throw new AppError(409, 'requests_disabled', 'لا يمكن استقبال الطلبات حالياً');
  }

  const result = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    await assertNoLivePartnership(tx, [requesterId, receiver.id]);

    const duplicate = await tx.partnershipRequest.findFirst({
      where: {
        OR: [
          { requesterId, receiverId: receiver.id },
          { requesterId: receiver.id, receiverId: requesterId }
        ],
        status: 'pending'
      }
    });
    if (duplicate) return { requestRecord: duplicate, notification: null };

    const created = await tx.partnershipRequest.create({
      data: {
        requesterId,
        receiverId: receiver.id,
        status: 'pending'
      }
    });

    const notification = await tx.notification.create({
      data: {
        userId: receiver.id,
        type: 'partnership.requested',
        title: 'طلب ارتباط جديد',
        body: 'يوجد طلب ارتباط بانتظار قرارك',
        payload: { requestId: created.id }
      }
    });

    return { requestRecord: created, notification };
  });

  response.status(201).json({ id: result.requestRecord.id, status: result.requestRecord.status });
  emitToUser(receiver.id, 'partnership.requested', requesterId, {
    requestId: result.requestRecord.id,
    username: input.username
  });
  emitToUser(receiver.id, 'notification.created', requesterId, {
    type: 'partnership.requested',
    requestId: result.requestRecord.id
  });
  if (result.notification) {
    void sendPushToUser(receiver.id, {
      notificationId: result.notification.id,
      type: 'partnership.requested',
      title: result.notification.title,
      body: result.notification.body,
      payload: { requestId: result.requestRecord.id }
    }).catch((error) => {
      console.error(JSON.stringify({ level: 'error', message: 'push_send_failed', error }));
    });
  }
});

partnershipsRouter.get('/partnership-requests', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const requests = await prisma.partnershipRequest.findMany({
    where: {
      OR: [{ requesterId: userId }, { receiverId: userId }],
      status: 'pending'
    },
    include: requestInclude,
    orderBy: { createdAt: 'desc' },
    take: 50
  });

  response.json({
    items: requests.map((item) => serializeRequest(item, userId))
  });
});

partnershipsRouter.get('/partnerships/current', requireAuth, async (request, response) => {
  const partnership = await getCurrentPartnership(request.user!.sub);
  response.json({ partnership: partnership ? serializePartnership(partnership) : null });
});

partnershipsRouter.post(
  '/partnership-requests/:id/accept',
  requireAuth,
  async (request, response) => {
    const userId = request.user!.sub;
    const requestId = routeParam(request.params.id);
    const result = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
      const requestRecord = await tx.partnershipRequest.findUnique({
        where: { id: requestId }
      });

      if (!requestRecord || requestRecord.receiverId !== userId || requestRecord.status !== 'pending') {
        throw new AppError(404, 'request_not_found', 'طلب الارتباط غير موجود');
      }

      await assertNoLivePartnership(tx, [requestRecord.requesterId, requestRecord.receiverId]);

      const partnership = await tx.partnership.create({
        data: {
          status: 'pending_onboarding',
          members: {
            create: [
              { userId: requestRecord.requesterId },
              { userId: requestRecord.receiverId }
            ]
          },
          settings: { create: {} },
          onboarding: { create: {} }
        },
        include: { members: true }
      });

      await ensureConversation(tx, partnership.id, [
        requestRecord.requesterId,
        requestRecord.receiverId
      ]);

      await tx.partnershipRequest.update({
        where: { id: requestRecord.id },
        data: { status: 'accepted', decidedAt: new Date() }
      });

      await tx.partnershipRequest.updateMany({
        where: {
          id: { not: requestRecord.id },
          status: 'pending',
          OR: [
            { requesterId: requestRecord.requesterId },
            { receiverId: requestRecord.requesterId },
            { requesterId: requestRecord.receiverId },
            { receiverId: requestRecord.receiverId }
          ]
        },
        data: { status: 'cancelled', decidedAt: new Date() }
      });

      await tx.notification.create({
        data: {
          userId: requestRecord.requesterId,
          partnershipId: partnership.id,
          type: 'partnership.accepted',
          title: 'تم قبول طلب الارتباط',
          body: 'يمكنكما الآن إكمال إعداد عالم Smiley',
          payload: { partnershipId: partnership.id }
        }
      });

      return partnership;
    });

    response.json({ partnership: { id: result.id, status: result.status } });
    for (const member of result.members) {
      emitToUser(member.userId, 'partnership.accepted', userId, {
        partnershipId: result.id
      });
    }
  }
);

partnershipsRouter.post(
  '/partnership-requests/:id/reject',
  requireAuth,
  async (request, response) => {
    const userId = request.user!.sub;
    const requestId = routeParam(request.params.id);
    await prisma.partnershipRequest.updateMany({
      where: { id: requestId, receiverId: userId, status: 'pending' },
      data: { status: 'rejected', decidedAt: new Date() }
    });
    response.status(204).send();
  }
);

partnershipsRouter.post(
  '/partnership-requests/:id/cancel',
  requireAuth,
  async (request, response) => {
    const userId = request.user!.sub;
    const requestId = routeParam(request.params.id);
    await prisma.partnershipRequest.updateMany({
      where: { id: requestId, requesterId: userId, status: 'pending' },
      data: { status: 'cancelled', decidedAt: new Date() }
    });
    response.status(204).send();
  }
);

partnershipsRouter.post('/partnerships/:id/onboarding', requireAuth, async (request, response) => {
  const input = onboardingSchema.parse(request.body);
  const userId = request.user!.sub;
  const partnershipId = routeParam(request.params.id);

  await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    const membership = await tx.partnershipMember.findFirst({
      where: {
        userId,
        leftAt: null,
        partnershipId,
        partnership: { status: 'pending_onboarding' }
      }
    });

    if (!membership) {
      throw new AppError(404, 'partnership_not_found', 'العلاقة غير موجودة أو مكتملة');
    }

    await tx.partnership.update({
      where: { id: partnershipId },
      data: {
        status: 'active',
        startedAt: input.startDate
      }
    });

    await tx.partnershipSettings.upsert({
      where: { partnershipId },
      update: {
        worldName: input.worldName,
        themeColor: input.themeColor
      },
      create: {
        partnershipId,
        worldName: input.worldName,
        themeColor: input.themeColor
      }
    });

    await tx.relationshipOnboarding.upsert({
      where: { partnershipId },
      update: {
        answers: input.answers as Prisma.InputJsonValue | undefined,
        completedAt: new Date()
      },
      create: {
        partnershipId,
        answers: input.answers as Prisma.InputJsonValue | undefined,
        completedAt: new Date()
      }
    });

    await tx.relationshipDate.create({
      data: {
        partnershipId,
        title: 'بداية العلاقة',
        kind: 'start',
        date: input.startDate
      }
    });

    await tx.occasion.createMany({
      data: (input.occasions ?? []).map((occasion) => ({
        partnershipId,
        title: occasion.title,
        date: occasion.date,
        recurrence: occasion.recurrence
      }))
    });

    await tx.treeDay.upsert({
      where: {
        partnershipId_date: {
          partnershipId,
          date: startOfUtcDay(input.startDate)
        }
      },
      update: {},
      create: {
        partnershipId,
        date: startOfUtcDay(input.startDate)
      }
    });

    const members = await tx.partnershipMember.findMany({
      where: { partnershipId },
      select: { userId: true }
    });
    await ensureConversation(
      tx,
      partnershipId,
      members.map((member) => member.userId)
    );
  });

  const result = await getCurrentPartnership(userId);
  if (!result) {
    throw new AppError(404, 'partnership_not_found', 'العلاقة غير موجودة');
  }
  response.json({ partnership: serializePartnership(result) });
});

const requestInclude = {
  requester: {
    select: {
      id: true,
      username: true,
      profile: { select: { displayName: true, avatarUrl: true } }
    }
  },
  receiver: {
    select: {
      id: true,
      username: true,
      profile: { select: { displayName: true, avatarUrl: true } }
    }
  }
} satisfies Prisma.PartnershipRequestInclude;

type RequestWithUsers = Prisma.PartnershipRequestGetPayload<{ include: typeof requestInclude }>;

function serializeRequest(item: RequestWithUsers, currentUserId: string) {
  const incoming = item.receiverId === currentUserId;
  const otherUser = incoming ? item.requester : item.receiver;
  return {
    id: item.id,
    status: item.status,
    direction: incoming ? 'incoming' : 'outgoing',
    createdAt: item.createdAt,
    otherUser: {
      id: otherUser.id,
      username: otherUser.username,
      displayName: otherUser.profile?.displayName ?? 'مستخدم',
      avatarUrl: otherUser.profile?.avatarUrl
    }
  };
}

type PartnershipPayload = Awaited<ReturnType<typeof getCurrentPartnership>>;

function serializePartnership(partnership: NonNullable<PartnershipPayload>) {
  return {
    id: partnership.id,
    status: partnership.status,
    startedAt: partnership.startedAt,
    worldName: partnership.settings?.worldName,
    themeColor: partnership.settings?.themeColor,
    members: partnership.members.map((member) => ({
      id: member.user.id,
      username: member.user.username,
      displayName: member.user.profile?.displayName ?? 'مستخدم',
      avatarUrl: member.user.profile?.avatarUrl
    })),
    onboardingCompleted: Boolean(partnership.onboarding?.completedAt)
  };
}

function startOfUtcDay(date: Date) {
  return new Date(Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), date.getUTCDate()));
}

function routeParam(value: string | string[]) {
  return Array.isArray(value) ? value[0] : value;
}
