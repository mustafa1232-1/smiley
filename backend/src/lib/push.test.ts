import { describe, expect, test } from 'vitest';

import { decryptPushToken, encryptPushToken, hashPushToken } from './push.js';

describe('push token protection', () => {
  test('encrypts and decrypts device tokens', () => {
    const token = 'device-token-for-tests-1234567890';
    const encrypted = encryptPushToken(token);

    expect(encrypted).not.toBe(token);
    expect(decryptPushToken(encrypted)).toBe(token);
  });

  test('hashes are stable and do not expose the token', () => {
    const token = 'device-token-for-tests-1234567890';

    expect(hashPushToken(token)).toBe(hashPushToken(token));
    expect(hashPushToken(token)).not.toContain(token);
  });
});
