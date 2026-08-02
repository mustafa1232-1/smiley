import { Router } from 'express';
import type { Prisma } from '@prisma/client';
import { z } from 'zod';

import { AppError } from '../../lib/errors.js';
import { prisma } from '../../lib/prisma.js';
import { requireAuth } from '../../middleware/auth.js';

export const partnershipsRouter = Router();

const requestSchema = z.object({
  username: z.string().trim().min(3).max(30)
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
    throw new AppError(409, 'requests_disabled', 'لا يمكن استقبال الطلبات حاليًا');
  }

  const requestRecord = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    const activeMembership = await tx.partnershipMember.findFirst({
      where: {
        userId: { in: [requesterId, receiver.id] },
        partnership: { status: { in: ['pending_onboarding', 'active'] } }
      }
    });
    if (activeMembership) {
      throw new AppError(409, 'active_partnership_exists', 'يوجد ارتباط فعال بالفعل');
    }

    const duplicate = await tx.partnershipRequest.findFirst({
      where: {
        requesterId,
        receiverId: receiver.id,
        status: 'pending'
      }
    });
    if (duplicate) return duplicate;

    return tx.partnershipRequest.create({
      data: {
        requesterId,
        receiverId: receiver.id,
        status: 'pending'
      }
    });
  });

  response.status(201).json({ id: requestRecord.id, status: requestRecord.status });
});

partnershipsRouter.get('/partnership-requests', requireAuth, async (request, response) => {
  const userId = request.user!.sub;
  const requests = await prisma.partnershipRequest.findMany({
    where: {
      OR: [{ requesterId: userId }, { receiverId: userId }],
      status: 'pending'
    },
    orderBy: { createdAt: 'desc' },
    take: 50
  });

  response.json({ items: requests });
});
