import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import { config } from '../config.js';
import { AppError } from './errors.js';

let client: S3Client | null = null;

// Returns the max upload size for a given content type, per the configured
// per-media-type ceilings (image/audio/video), falling back to the general cap.
export function maxUploadBytesForMime(mimeType: string): number {
  const type = mimeType.toLowerCase();
  if (type.startsWith('image/')) return config.storage.maxImageBytes;
  if (type.startsWith('audio/')) return config.storage.maxAudioBytes;
  if (type.startsWith('video/')) return config.storage.maxVideoBytes;
  return config.storage.maxUploadBytes;
}

/** Public URL for a stored object, or null when no public base URL is set. */
export function mediaPublicUrl(objectKey: string): string | null {
  const base = config.storage.r2PublicBaseUrl;
  if (!base) return null;
  return `${base.replace(/\/$/, '')}/${objectKey}`;
}

export function formatBytes(bytes: number): string {
  if (bytes >= 1024 * 1024 * 1024) {
    return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} غيغابايت`;
  }
  return `${Math.round(bytes / 1024 / 1024)} ميغابايت`;
}

export function isStorageConfigured() {
  return Boolean(
    config.storage.r2AccountId &&
      config.storage.r2AccessKeyId &&
      config.storage.r2SecretAccessKey &&
      config.storage.r2Bucket
  );
}

export async function createPutUploadUrl(input: {
  objectKey: string;
  mimeType: string;
  sizeBytes: number;
  maxBytes?: number;
}) {
  if (!isStorageConfigured()) {
    throw new AppError(
      503,
      'storage_not_configured',
      'لم يتم إعداد تخزين الوسائط بعد'
    );
  }
  const maxBytes = input.maxBytes ?? config.storage.maxUploadBytes;
  if (input.sizeBytes > maxBytes) {
    throw new AppError(
      413,
      'upload_too_large',
      `حجم الملف أكبر من الحد المسموح (${formatBytes(maxBytes)})`
    );
  }

  const command = new PutObjectCommand({
    Bucket: config.storage.r2Bucket!,
    Key: input.objectKey,
    ContentType: input.mimeType,
    ContentLength: input.sizeBytes
  });

  const uploadUrl = await getSignedUrl(getClient(), command, {
    expiresIn: config.storage.signedUrlTtlSeconds
  });

  return {
    uploadUrl,
    headers: {
      'content-type': input.mimeType
    },
    expiresIn: config.storage.signedUrlTtlSeconds,
    publicUrl: config.storage.r2PublicBaseUrl
      ? `${config.storage.r2PublicBaseUrl.replace(/\/$/, '')}/${input.objectKey}`
      : null
  };
}

function getClient() {
  if (client) return client;

  client = new S3Client({
    region: 'auto',
    endpoint: `https://${config.storage.r2AccountId}.r2.cloudflarestorage.com`,
    credentials: {
      accessKeyId: config.storage.r2AccessKeyId!,
      secretAccessKey: config.storage.r2SecretAccessKey!
    }
  });
  return client;
}
