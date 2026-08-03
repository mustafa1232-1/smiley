import { Router, type Request } from 'express';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { createHash, randomBytes } from 'node:crypto';
import { z } from 'zod';
import type { Prisma } from '@prisma/client';

import { config } from '../../config.js';
import { AppError } from '../../lib/errors.js';
import { prisma } from '../../lib/prisma.js';
import { requireAuth } from '../../middleware/auth.js';
import { isReservedUsername, normalizeUsername, usernameRegex } from './username.js';

export const authRouter = Router();

const registerSchema = z.object({
  displayName: z.string().trim().min(1).max(80),
  username: z.string().trim().regex(usernameRegex),
  email: z.string().trim().email(),
  password: z.string().min(10).max(200),
  birthDate: z.string().datetime(),
  gender: z.string().trim().max(40).optional(),
  timezone: z.string().trim().min(1).max(80),
  language: z.string().trim().min(2).max(12),
  acceptedTerms: z.literal(true)
});

const loginSchema = z.object({
  identifier: z.string().trim().min(1),
  password: z.string().min(1)
});

const refreshSchema = z.object({
  refreshToken: z.string().trim().min(1)
});

const passwordResetRequestSchema = z.object({
  identifier: z.string().trim().min(1).max(255)
});

const passwordResetConfirmSchema = z.object({
  token: z.string().trim().min(20).max(500),
  password: z.string().min(10).max(200)
});

const sessionParamSchema = z.string().uuid();

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
            gender: input.gender,
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

    return issueSession(
      user.id,
      user.username,
      user.profile?.displayName ?? input.displayName,
      tx,
      sessionMeta(request)
    );
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
    prisma,
    sessionMeta(request)
  );
  response.json(session);
});

authRouter.post('/auth/password-reset/request', async (request, response) => {
  const input = passwordResetRequestSchema.parse(request.body);
  const identifier = input.identifier.toLowerCase();
  const user = await prisma.user.findFirst({
    where: {
      OR: [{ emailNormalized: identifier }, { usernameNormalized: identifier }],
      deletedAt: null
    }
  });

  let resetToken: string | undefined;
  if (user) {
    resetToken = randomBytes(32).toString('base64url');
    await prisma.passwordResetToken.create({
      data: {
        userId: user.id,
        tokenHash: await bcrypt.hash(resetToken, config.bcryptCost),
        expiresAt: new Date(Date.now() + 30 * 60 * 1000)
      }
    });
    request.log?.info({ userId: user.id }, 'password reset token created');
  }

  response.status(202).json({
    status: 'accepted',
    ...(config.exposeAuthDebugTokens && resetToken ? { resetToken } : {})
  });
});

authRouter.post('/auth/password-reset/confirm', async (request, response) => {
  const input = passwordResetConfirmSchema.parse(request.body);
  const candidates = await prisma.passwordResetToken.findMany({
    where: {
      usedAt: null,
      expiresAt: { gt: new Date() }
    },
    orderBy: { createdAt: 'desc' },
    take: 100
  });

  let matched: (typeof candidates)[number] | undefined;
  for (const candidate of candidates) {
    if (await bcrypt.compare(input.token, candidate.tokenHash)) {
      matched = candidate;
      break;
    }
  }

  if (!matched) {
    throw new AppError(400, 'invalid_reset_token', 'رمز استعادة كلمة المرور غير صالح');
  }

  const passwordHash = await bcrypt.hash(input.password, config.bcryptCost);
  await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    await tx.user.update({
      where: { id: matched.userId },
      data: { passwordHash }
    });
    await tx.passwordResetToken.update({
      where: { id: matched.id },
      data: { usedAt: new Date() }
    });
    await tx.passwordResetToken.updateMany({
      where: { userId: matched.userId, usedAt: null, id: { not: matched.id } },
      data: { usedAt: new Date() }
    });
    await tx.refreshToken.updateMany({
      where: { userId: matched.userId, revokedAt: null },
      data: { revokedAt: new Date() }
    });
    await tx.userSession.updateMany({
      where: { userId: matched.userId, revokedAt: null },
      data: { revokedAt: new Date() }
    });
  });

  response.status(204).send();
});

authRouter.post('/auth/refresh', async (request, response) => {
  const input = refreshSchema.parse(request.body);
  const payload = verifyRefreshToken(input.refreshToken);
  const user = await prisma.user.findFirst({
    where: { id: payload.sub, deletedAt: null },
    include: { profile: true }
  });
  if (!user) {
    throw new AppError(401, 'invalid_refresh_token', 'جلسة الدخول غير صالحة');
  }

  const session = await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    const activeTokens = await tx.refreshToken.findMany({
      where: {
        userId: user.id,
        revokedAt: null,
        expiresAt: { gt: new Date() }
      }
    });

    for (const token of activeTokens) {
      const matches = await bcrypt.compare(input.refreshToken, token.tokenHash);
      if (!matches) continue;

      await tx.refreshToken.update({
        where: { id: token.id },
        data: { revokedAt: new Date() }
      });

      return issueSession(
        user.id,
        user.username,
        user.profile?.displayName ?? 'مستخدم',
        tx,
        sessionMeta(request),
        token.sessionId ?? payload.sid
      );
    }

    await tx.refreshToken.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date() }
    });
    throw new AppError(401, 'refresh_token_reuse_detected', 'جلسة الدخول غير صالحة');
  });

  response.json(session);
});

authRouter.post('/auth/logout', async (request, response) => {
  const input = refreshSchema.safeParse(request.body);
  if (input.success) {
    const payload = safeVerifyRefreshToken(input.data.refreshToken);
    if (payload) {
      const activeTokens = await prisma.refreshToken.findMany({
        where: {
          userId: payload.sub,
          revokedAt: null,
          expiresAt: { gt: new Date() }
        }
      });
      for (const token of activeTokens) {
        if (await bcrypt.compare(input.data.refreshToken, token.tokenHash)) {
          await prisma.refreshToken.update({
            where: { id: token.id },
            data: { revokedAt: new Date() }
          });
          if (token.sessionId) {
            await prisma.userSession.updateMany({
              where: { id: token.sessionId, userId: payload.sub, revokedAt: null },
              data: { revokedAt: new Date() }
            });
          }
          break;
        }
      }
    }
  }
  response.status(204).send();
});

authRouter.post('/auth/logout-all', requireAuth, async (request, response) => {
  await prisma.refreshToken.updateMany({
    where: {
      userId: request.user!.sub,
      revokedAt: null
    },
    data: { revokedAt: new Date() }
  });
  await prisma.userSession.updateMany({
    where: {
      userId: request.user!.sub,
      revokedAt: null
    },
    data: { revokedAt: new Date() }
  });
  response.status(204).send();
});

authRouter.get('/auth/sessions', requireAuth, async (request, response) => {
  const items = await prisma.userSession.findMany({
    where: { userId: request.user!.sub },
    include: { device: true },
    orderBy: { updatedAt: 'desc' },
    take: 50
  });

  response.json({
    items: items.map((item) => ({
      id: item.id,
      current: item.id === request.user!.sid,
      revokedAt: item.revokedAt,
      createdAt: item.createdAt,
      updatedAt: item.updatedAt,
      userAgent: item.userAgent,
      device: item.device
        ? {
            id: item.device.id,
            platform: item.device.platform,
            deviceName: item.device.deviceName,
            lastSeenAt: item.device.lastSeenAt
          }
        : null
    }))
  });
});

authRouter.delete('/auth/sessions/:id', requireAuth, async (request, response) => {
  const sessionId = sessionParamSchema.parse(request.params.id);
  await prisma.$transaction(async (tx: Prisma.TransactionClient) => {
    await tx.userSession.updateMany({
      where: { id: sessionId, userId: request.user!.sub, revokedAt: null },
      data: { revokedAt: new Date() }
    });
    await tx.refreshToken.updateMany({
      where: { sessionId, userId: request.user!.sub, revokedAt: null },
      data: { revokedAt: new Date() }
    });
  });
  response.status(204).send();
});

async function issueSession(
  userId: string,
  username: string,
  displayName: string,
  tx: Prisma.TransactionClient | typeof prisma,
  meta: SessionMeta = { platform: 'unknown' },
  sessionId?: string
) {
  const activeSessionId = await ensureSession(userId, tx, meta, sessionId);
  const accessToken = jwt.sign({ sub: userId, username, sid: activeSessionId }, config.jwtAccessSecret, {
    expiresIn: config.jwtAccessTtlSeconds
  });
  const refreshToken = jwt.sign({ sub: userId, sid: activeSessionId }, config.jwtRefreshSecret, {
    expiresIn: `${config.jwtRefreshTtlDays}d`
  });
  const tokenHash = await bcrypt.hash(refreshToken, config.bcryptCost);

  await tx.refreshToken.create({
    data: {
      userId,
      sessionId: activeSessionId,
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

type SessionMeta = {
  platform: string;
  deviceName?: string;
  userAgent?: string;
  ipHash?: string;
};

async function ensureSession(
  userId: string,
  tx: Prisma.TransactionClient | typeof prisma,
  meta: SessionMeta,
  sessionId?: string
) {
  if (sessionId) {
    const existing = await tx.userSession.findFirst({
      where: { id: sessionId, userId, revokedAt: null }
    });
    if (existing) {
      await tx.userSession.update({
        where: { id: existing.id },
        data: {
          ipHash: meta.ipHash,
          userAgent: meta.userAgent
        }
      });
      return existing.id;
    }
  }

  const device = await tx.userDevice.create({
    data: {
      userId,
      platform: meta.platform,
      deviceName: meta.deviceName,
      lastSeenAt: new Date()
    }
  });
  const session = await tx.userSession.create({
    data: {
      userId,
      deviceId: device.id,
      ipHash: meta.ipHash,
      userAgent: meta.userAgent
    }
  });
  return session.id;
}

function sessionMeta(request: Request): SessionMeta {
  const userAgent = request.header('user-agent')?.slice(0, 500);
  const platform = request.header('x-device-platform')?.slice(0, 20) ?? 'unknown';
  const deviceName = request.header('x-device-name')?.slice(0, 120);
  return {
    platform,
    deviceName,
    userAgent,
    ipHash: request.ip ? createHash('sha256').update(request.ip).digest('hex') : undefined
  };
}

type RefreshTokenPayload = {
  sub: string;
  sid?: string;
};

function verifyRefreshToken(token: string) {
  try {
    return jwt.verify(token, config.jwtRefreshSecret) as RefreshTokenPayload;
  } catch {
    throw new AppError(401, 'invalid_refresh_token', 'جلسة الدخول غير صالحة');
  }
}

function safeVerifyRefreshToken(token: string) {
  try {
    return jwt.verify(token, config.jwtRefreshSecret) as RefreshTokenPayload;
  } catch {
    return null;
  }
}
