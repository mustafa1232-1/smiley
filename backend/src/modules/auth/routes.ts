import { Router } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { z } from 'zod';
import type { Prisma } from '@prisma/client';

import { config } from '../../config.js';
import { AppError } from '../../lib/errors.js';
import { prisma } from '../../lib/prisma.js';
import { isReservedUsername, normalizeUsername, usernameRegex } from './username.js';

export const authRouter = Router();

const registerSchema = z.object({
  displayName: z.string().trim().min(1).max(80),
  username: z.string().trim().regex(usernameRegex),
  email: z.string().trim().email(),
  password: z.string().min(10).max(200),
  birthDate: z.string().datetime(),
  timezone: z.string().trim().min(1).max(80),
  language: z.string().trim().min(2).max(12),
  acceptedTerms: z.literal(true)
});

const loginSchema = z.object({
  identifier: z.string().trim().min(1),
  password: z.string().min(1)
});

authRouter.post('/auth/register', async (request, response) => {
  const input = registerSchema.parse(request.body);
  const usernameNormalized = normalizeUsername(input.username);
  if (isReservedUsername(usernameNormalized)) {
    throw new AppError(422, 'username_unavailable', 'اسم المستخدم غير متاح');
  }

  const passwordHash = await bcrypt.hash(input.password, config.bcryptCost);
  const session = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    const exists = await tx.user.findFirst({
      where: {
        OR: [{ emailNormalized: input.email.toLowerCase() }, { usernameNormalized }]
      }
    });
    if (exists) throw new AppError(409, 'account_exists', 'الحساب موجود مسبقًا');

    const user = await tx.user.create({
      data: {
        email: input.email,
        emailNormalized: input.email.toLowerCase(),
        username: input.username,
        usernameNormalized,
        passwordHash,
        profile: {
          create: {
            displayName: input.displayName,
            birthDate: new Date(input.birthDate),
            timezone: input.timezone,
            language: input.language
          }
        },
        usernameHistory: {
          create: {
            username: input.username,
            usernameNormalized
          }
        }
      },
      include: { profile: true }
    });

    return issueSession(user.id, user.username, user.profile?.displayName ?? input.displayName, tx);
  });

  response.status(201).json(session);
});

authRouter.post('/auth/login', async (request, response) => {
  const input = loginSchema.parse(request.body);
  const identifier = input.identifier.toLowerCase();
  const user = await prisma.user.findFirst({
    where: {
      OR: [{ emailNormalized: identifier }, { usernameNormalized: identifier }],
      deletedAt: null
    },
    include: { profile: true }
  });
  if (!user) throw new AppError(401, 'invalid_credentials', 'بيانات الدخول غير صحيحة');

  const valid = await bcrypt.compare(input.password, user.passwordHash);
  if (!valid) throw new AppError(401, 'invalid_credentials', 'بيانات الدخول غير صحيحة');

  const session = await issueSession(
    user.id,
    user.username,
    user.profile?.displayName ?? 'مستخدم',
    prisma
  );
  response.json(session);
});

authRouter.post('/auth/password-reset/request', async (_request, response) => {
  response.status(202).json({ status: 'accepted' });
});

async function issueSession(
  userId: string,
  username: string,
  displayName: string,
  tx: Pick<typeof prisma, 'refreshToken'>
) {
  const accessToken = jwt.sign({ sub: userId, username }, config.jwtAccessSecret, {
    expiresIn: config.jwtAccessTtlSeconds
  });
  const refreshToken = jwt.sign({ sub: userId }, config.jwtRefreshSecret, {
    expiresIn: `${config.jwtRefreshTtlDays}d`
  });
  const tokenHash = await bcrypt.hash(refreshToken, config.bcryptCost);

  await tx.refreshToken.create({
    data: {
      userId,
      tokenHash,
      expiresAt: new Date(Date.now() + config.jwtRefreshTtlDays * 24 * 60 * 60 * 1000)
    }
  });

  return {
    accessToken,
    refreshToken,
    user: { id: userId, username, displayName }
  };
}
