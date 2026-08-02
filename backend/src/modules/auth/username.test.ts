import { describe, expect, it } from 'vitest';

import {
  isReservedUsername,
  isUsernameFormatValid,
  normalizeUsername
} from './username.js';

describe('username policy', () => {
  it('normalizes usernames case-insensitively', () => {
    expect(normalizeUsername(' User.Name_1 ')).toBe('user.name_1');
  });

  it('accepts supported characters only', () => {
    expect(isUsernameFormatValid('user.name_1')).toBe(true);
    expect(isUsernameFormatValid('user name')).toBe(false);
  });

  it('blocks reserved names', () => {
    expect(isReservedUsername('Admin')).toBe(true);
  });
});
