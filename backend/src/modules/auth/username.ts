const usernameRegex = /^[a-zA-Z0-9._]{3,30}$/;
const reservedUsernames = new Set(['admin', 'support', 'system', 'root', 'smiley']);

export function normalizeUsername(username: string) {
  return username.trim().toLowerCase();
}

export function isUsernameFormatValid(username: string) {
  return usernameRegex.test(username);
}

export function isReservedUsername(username: string) {
  return reservedUsernames.has(normalizeUsername(username));
}

export { usernameRegex };
