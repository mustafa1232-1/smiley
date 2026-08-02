import { PutObjectCommand, S3Client } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

import { config } from '../config.js';
import { AppError } from './errors.js';

let client: S3Client | null = null;

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
}) {
  if (!isStorageConfigured()) {
    throw new AppError(
      503,
      'storage_not_configured',
      'لم يتم إعداد تخزين الوسائط بعد'
    );
  }
  if (input.sizeBytes > config.storage.maxUploadBytes) {
    throw new AppError(413, 'upload_too_large', 'حجم الملف أكبر من الحد المسموح');
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
