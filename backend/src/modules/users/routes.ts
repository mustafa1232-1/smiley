import { Router } from 'express';

import { prisma } from '../../lib/prisma.js';
import { requireAuth } from '../../middleware/auth.js';

export const usersRouter = Router();

usersRouter.get('/users/search', requireAuth, async (request, response) => {
  const username = String(request.query.username ?? '').trim().toLowerCase();
  if (username.length < 3) {
    response.json({ items: [] });
    return;
  }

  const users = await prisma.user.findMany({
    where: {
      usernameNormalized: { contains: username },
      deletedAt: null,
      id: { not: request.user!.sub },
      profile: { searchable: true }
    },
    include: { profile: true },
    take: 10,
    orderBy: { usernameNormalized: 'asc' }
  });

  response.json({
    items: users.map((user) => ({
      displayName: user.profile?.displayName ?? 'مستخدم',
      username: user.username,
      avatarUrl: user.profile?.avatarUrl,
      canReceiveRequests: user.profile?.canReceivePartnershipRequests ?? false
    }))
  });
});
