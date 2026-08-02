# Integrations

## Firebase Cloud Messaging

Required variables:

- `FIREBASE_PROJECT_ID`
- `FIREBASE_CLIENT_EMAIL`
- `FIREBASE_PRIVATE_KEY`
- `PUSH_TOKEN_ENCRYPTION_KEY`

The backend uses Firebase Cloud Messaging HTTP v1. Device tokens are stored encrypted with `PUSH_TOKEN_ENCRYPTION_KEY`; keep it stable across deploys or existing device tokens cannot be decrypted.

Keep private keys outside source control. Use separate Firebase projects for staging and production.

## Apple Notifications

Required variables:

- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_BUNDLE_ID`

APNs can be routed through FCM or implemented directly later.

## Cloudflare R2

Required variables:

- `R2_ACCOUNT_ID`
- `R2_ACCESS_KEY_ID`
- `R2_SECRET_ACCESS_KEY`
- `R2_BUCKET`
- `R2_PUBLIC_BASE_URL`
- `STORAGE_SIGNED_URL_TTL_SECONDS`
- `STORAGE_MAX_UPLOAD_BYTES`

Media uploads use signed PUT URLs: the app asks the API for `/uploads/presign`, uploads directly to R2/S3, then calls `/uploads/:id/complete` before attaching the returned asset to posts or albums.

Private media must be served through signed URLs. Do not expose raw private object keys to unrelated users.

## Railway

Set the same backend environment variables in Railway:

- `DATABASE_URL`
- `REDIS_URL`
- JWT secrets and TTLs
- CORS origin
- Storage variables
- Notification variables

Run Prisma migrations as a release step before exposing a production deployment.

## Backups

Use managed PostgreSQL backups in the deployment provider. Keep a tested restore process for staging before enabling production deletion flows.
