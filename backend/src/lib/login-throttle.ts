// In-memory per-identifier login throttle. Provides temporary account lockout
// after repeated failed sign-in attempts, complementing the IP-based rate
// limiter. Single-instance only; a Redis-backed version is planned for the
// multi-instance rollout (see slice 5).

type Attempt = {
  count: number;
  firstAttemptAt: number;
  lockedUntil: number | null;
};

const attempts = new Map<string, Attempt>();

const MAX_ATTEMPTS = 8;
const ATTEMPT_WINDOW_MS = 15 * 60 * 1000;
const LOCK_MS = 15 * 60 * 1000;
const MAX_TRACKED_KEYS = 10_000;

/**
 * Returns the lockout expiry timestamp (ms) if the key is currently locked,
 * otherwise null. Expired locks are cleared lazily.
 */
export function lockedUntil(key: string): number | null {
  const record = attempts.get(key);
  if (!record?.lockedUntil) return null;
  if (record.lockedUntil <= Date.now()) {
    attempts.delete(key);
    return null;
  }
  return record.lockedUntil;
}

/** Records a failed attempt and locks the key once the threshold is reached. */
export function recordFailure(key: string): void {
  const now = Date.now();
  pruneIfNeeded();
  const record = attempts.get(key);

  if (!record || now - record.firstAttemptAt > ATTEMPT_WINDOW_MS) {
    attempts.set(key, { count: 1, firstAttemptAt: now, lockedUntil: null });
    return;
  }

  record.count += 1;
  if (record.count >= MAX_ATTEMPTS) {
    record.lockedUntil = now + LOCK_MS;
  }
}

/** Clears throttle state after a successful sign-in. */
export function recordSuccess(key: string): void {
  attempts.delete(key);
}

// Keeps the map bounded even if many distinct identifiers are probed.
function pruneIfNeeded(): void {
  if (attempts.size < MAX_TRACKED_KEYS) return;
  const now = Date.now();
  for (const [key, record] of attempts) {
    const lockExpired = !record.lockedUntil || record.lockedUntil <= now;
    const windowExpired = now - record.firstAttemptAt > ATTEMPT_WINDOW_MS;
    if (lockExpired && windowExpired) attempts.delete(key);
  }
}

// Exposed for tests to reset shared state.
export function _resetThrottle(): void {
  attempts.clear();
}
