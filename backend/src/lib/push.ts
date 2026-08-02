import { createCipheriv, createDecipheriv, createHash, createHmac, randomBytes } from 'node:crypto';
import jwt from 'jsonwebtoken';

import { config } from '../config.js';
import { prisma } from './prisma.js';

type PushPayload = {
  notificationId: string;
  type: string;
  title: string;
  body?: string | null;
  payload?: Record<string, unknown> | null;
};

let accessTokenCache: { token: string; expiresAt: number } | null = null;

export function isPushConfigured() {
  return Boolean(
    config.push.firebaseProjectId &&
      config.push.firebaseClientEmail &&
      config.push.firebasePrivateKey
  );
}

export function hashPushToken(token: string) {
  return createHmac('sha256', encryptionKey()).update(token).digest('hex');
}

export function encryptPushToken(token: string) {
  const iv = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', encryptionKey(), iv);
  const ciphertext = Buffer.concat([cipher.update(token, 'utf8'), cipher.final()]);
  const tag = cipher.getAuthTag();
  return [
    'v1',
    iv.toString('base64url'),
    tag.toString('base64url'),
    ciphertext.toString('base64url')
  ].join(':');
}

export function decryptPushToken(value: string) {
  const [version, ivText, tagText, ciphertextText] = value.split(':');
  if (version !== 'v1' || !ivText || !tagText || !ciphertextText) return null;

  const decipher = createDecipheriv(
    'aes-256-gcm',
    encryptionKey(),
    Buffer.from(ivText, 'base64url')
  );
  decipher.setAuthTag(Buffer.from(tagText, 'base64url'));
  return Buffer.concat([
    decipher.update(Buffer.from(ciphertextText, 'base64url')),
    decipher.final()
  ]).toString('utf8');
}

export async function sendPushToUser(userId: string, input: PushPayload) {
  if (!isPushConfigured()) return;

  const tokens = await prisma.pushToken.findMany({
    where: {
      userId,
      revokedAt: null,
      tokenCiphertext: { not: null }
    },
    take: 20
  });
  if (tokens.length === 0) return;

  await Promise.all(
    tokens.map(async (item) => {
      const token = item.tokenCiphertext ? decryptPushToken(item.tokenCiphertext) : null;
      if (!token) return;

      try {
        await sendFcm(token, input);
        await prisma.pushToken.update({
          where: { id: item.id },
          data: { failureCount: 0, lastSeenAt: new Date() }
        });
      } catch (error) {
        const revokedAt = isPermanentFcmFailure(error) ? new Date() : undefined;
        await prisma.pushToken.update({
          where: { id: item.id },
          data: {
            failureCount: { increment: 1 },
            ...(revokedAt ? { revokedAt } : {})
          }
        });
      }
    })
  );
}

async function sendFcm(token: string, input: PushPayload) {
  const accessToken = await getFcmAccessToken();
  const response = await fetch(
    `https://fcm.googleapis.com/v1/projects/${config.push.firebaseProjectId}/messages:send`,
    {
      method: 'POST',
      headers: {
        authorization: `Bearer ${accessToken}`,
        'content-type': 'application/json'
      },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: input.title,
            body: input.body ?? undefined
          },
          data: {
            notificationId: input.notificationId,
            type: input.type,
            payload: JSON.stringify(input.payload ?? {})
          }
        }
      })
    }
  );

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`fcm_${response.status}:${body}`);
  }
}

async function getFcmAccessToken() {
  const now = Math.floor(Date.now() / 1000);
  if (accessTokenCache && accessTokenCache.expiresAt - 60 > now) {
    return accessTokenCache.token;
  }

  const assertion = jwt.sign(
    {
      iss: config.push.firebaseClientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      iat: now,
      exp: now + 3600
    },
    config.push.firebasePrivateKey!,
    { algorithm: 'RS256' }
  );

  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion
    })
  });

  if (!response.ok) {
    throw new Error(`fcm_oauth_${response.status}:${await response.text()}`);
  }

  const json = (await response.json()) as { access_token: string; expires_in: number };
  accessTokenCache = {
    token: json.access_token,
    expiresAt: now + json.expires_in
  };
  return accessTokenCache.token;
}

function isPermanentFcmFailure(error: unknown) {
  const message = error instanceof Error ? error.message : String(error);
  return (
    message.includes('UNREGISTERED') ||
    message.includes('INVALID_ARGUMENT') ||
    message.includes('SENDER_ID_MISMATCH') ||
    message.startsWith('fcm_404')
  );
}

function encryptionKey() {
  return createHash('sha256').update(config.push.tokenEncryptionKey).digest();
}
