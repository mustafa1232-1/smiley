import type { Prisma, PartnershipStatus } from '@prisma/client';

import { AppError } from './errors.js';
import { prisma } from './prisma.js';

const liveStatuses: PartnershipStatus[] = ['pending_onboarding', 'active'];

export async function getCurrentPartnership(userId: string) {
  return prisma.partnership.findFirst({
    where: {
      status: { in: liveStatuses },
      members: { some: { userId, leftAt: null } }
    },
    include: partnershipInclude,
    orderBy: { createdAt: 'desc' }
  });
}

export async function requireCurrentPartnership(userId: string) {
  const partnership = await getCurrentPartnership(userId);
  if (!partnership) {
    throw new AppError(404, 'partnership_not_found', 'لا توجد علاقة نشطة لهذا الحساب');
  }
  return partnership;
}

export async function requireActivePartnership(userId: string) {
  const partnership = await requireCurrentPartnership(userId);
  if (partnership.status !== 'active') {
    throw new AppError(409, 'onboarding_required', 'أكمل إعداد العلاقة أولاً');
  }
  return partnership;
}

export async function assertNoLivePartnership(
  tx: Prisma.TransactionClient,
  userIds: string[]
) {
  const existing = await tx.partnershipMember.findFirst({
    where: {
      userId: { in: userIds },
      leftAt: null,
      partnership: { status: { in: liveStatuses } }
    }
  });

  if (existing) {
    throw new AppError(409, 'active_partnership_exists', 'يوجد ارتباط فعال بالفعل');
  }
}

export async function ensureConversation(
  tx: Prisma.TransactionClient,
  partnershipId: string,
  userIds: string[]
) {
  const existing = await tx.conversation.findFirst({
    where: { partnershipId },
    include: { members: true }
  });
  if (existing) return existing;

  return tx.conversation.create({
    data: {
      partnershipId,
      members: {
        create: userIds.map((userId) => ({ userId }))
      }
    },
    include: { members: true }
  });
}

export function otherPartnerId(
  partnership: { members: Array<{ userId: string }> },
  userId: string
) {
  return partnership.members.find((member) => member.userId !== userId)?.userId;
}

export const partnershipInclude = {
  settings: true,
  onboarding: true,
  members: {
    include: {
      user: {
        select: {
          id: true,
          username: true,
          profile: {
            select: {
              displayName: true,
              avatarUrl: true
            }
          }
        }
      }
    }
  }
} satisfies Prisma.PartnershipInclude;
