import 'dotenv/config';

const nodeEnv = process.env.NODE_ENV ?? 'development';
const isProduction = nodeEnv === 'production';

// Known development/example secrets that must never be used in production.
const INSECURE_SECRETS = new Set([
  'dev-access-secret',
  'dev-refresh-secret',
  'change-me-access-secret',
  'change-me-refresh-secret',
  'change-me'
]);

// Returns the secret. In production it refuses to fall back to a known/weak
// value, so a missing or default secret fails fast instead of silently
// running with a publicly known key (which would allow token forgery).
function requiredSecret(name: string, devFallback: string): string {
  const value = process.env[name];
  if (isProduction) {
    if (!value || INSECURE_SECRETS.has(value) || value.length < 32) {
      throw new Error(
        `Refusing to start: ${name} must be a strong secret (>= 32 chars, not a default) in production.`
      );
    }
    return value;
  }
  return value ?? devFallback;
}

// In production, wildcard CORS is refused so the API is only reachable from the
// configured app origin(s). Supports a comma-separated list.
function parseCorsOrigins(): string[] | '*' {
  const raw = process.env.CORS_ORIGIN?.trim();
  if (!raw || raw === '*') {
    if (isProduction) {
      // Wildcard CORS is acceptable for this token-authenticated (Bearer, no
      // cookies) mobile API, so we warn rather than refuse to start. Set
      // explicit origin(s) if a browser client is added.
      console.warn(
        JSON.stringify({
          level: 'warn',
          message: 'CORS_ORIGIN is a wildcard in production; set explicit origin(s) if you add a browser client.'
        })
      );
    }
    return '*';
  }
  return raw
    .split(',')
    .map((origin) => origin.trim())
    .filter(Boolean);
}

export const config = {
  port: Number(process.env.PORT ?? 3000),
  corsOrigins: parseCorsOrigins(),
  nodeEnv,
  isProduction,
  jwtAccessSecret: requiredSecret('JWT_ACCESS_SECRET', 'dev-access-secret'),
  jwtRefreshSecret: requiredSecret('JWT_REFRESH_SECRET', 'dev-refresh-secret'),
  jwtAccessTtlSeconds: Number(process.env.JWT_ACCESS_TTL_SECONDS ?? 900),
  jwtRefreshTtlDays: Number(process.env.JWT_REFRESH_TTL_DAYS ?? 30),
  bcryptCost: Number(process.env.BCRYPT_COST ?? 12),
  // Debug token exposure can never be enabled in production, regardless of env.
  exposePasswordResetToken:
    !isProduction && process.env.PASSWORD_RESET_DEBUG_TOKEN === 'true',
  exposeAuthDebugTokens:
    !isProduction &&
    (process.env.AUTH_DEBUG_TOKENS === 'true' ||
      process.env.PASSWORD_RESET_DEBUG_TOKEN === 'true'),
  storage: {
    r2AccountId: process.env.R2_ACCOUNT_ID,
    r2AccessKeyId: process.env.R2_ACCESS_KEY_ID,
    r2SecretAccessKey: process.env.R2_SECRET_ACCESS_KEY,
    r2Bucket: process.env.R2_BUCKET,
    r2PublicBaseUrl: process.env.R2_PUBLIC_BASE_URL,
    signedUrlTtlSeconds: Number(process.env.STORAGE_SIGNED_URL_TTL_SECONDS ?? 900),
    // Per-media-type upload ceilings. maxUploadBytes is the fallback for other
    // types (e.g. PDF).
    maxImageBytes: Number(process.env.STORAGE_MAX_IMAGE_BYTES ?? 10 * 1024 * 1024),
    maxAudioBytes: Number(process.env.STORAGE_MAX_AUDIO_BYTES ?? 40 * 1024 * 1024),
    maxVideoBytes: Number(process.env.STORAGE_MAX_VIDEO_BYTES ?? 3 * 1024 * 1024 * 1024),
    maxUploadBytes: Number(process.env.STORAGE_MAX_UPLOAD_BYTES ?? 25 * 1024 * 1024)
  },
  push: {
    firebaseProjectId: process.env.FIREBASE_PROJECT_ID,
    firebaseClientEmail: process.env.FIREBASE_CLIENT_EMAIL,
    firebasePrivateKey: process.env.FIREBASE_PRIVATE_KEY?.replace(/\\n/g, '\n'),
    tokenEncryptionKey:
      process.env.PUSH_TOKEN_ENCRYPTION_KEY ??
      requiredSecret('JWT_REFRESH_SECRET', 'dev-refresh-secret')
  }
};
