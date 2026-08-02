import cors from 'cors';
import express from 'express';
import rateLimit from 'express-rate-limit';
import helmet from 'helmet';
import { randomUUID } from 'node:crypto';

import { config } from './config.js';
import { errorHandler, notFound } from './lib/errors.js';
import { authRouter } from './modules/auth/routes.js';
import { healthRouter } from './modules/health/routes.js';
import { partnershipsRouter } from './modules/partnerships/routes.js';
import { usersRouter } from './modules/users/routes.js';

export function createApp() {
  const app = express();

  app.use(helmet());
  app.use(cors({ origin: config.corsOrigin === '*' ? true : config.corsOrigin }));
  app.use(express.json({ limit: '1mb' }));
  app.use((request, _response, next) => {
    request.id = request.headers['x-request-id']?.toString() ?? randomUUID();
    request.log = {
      info: (payload, message) =>
        console.info(JSON.stringify({ level: 'info', message, ...asRecord(payload) })),
      error: (payload, message) =>
        console.error(JSON.stringify({ level: 'error', message, ...asRecord(payload) }))
    };
    next();
  });
  app.use(
    '/api/v1',
    rateLimit({
      windowMs: 60_000,
      limit: 120,
      standardHeaders: true,
      legacyHeaders: false
    })
  );

  app.use(healthRouter);
  app.use('/api/v1', authRouter, usersRouter, partnershipsRouter);
  app.use(notFound);
  app.use(errorHandler);

  return app;
}

function asRecord(payload: unknown) {
  return payload && typeof payload === 'object' ? (payload as Record<string, unknown>) : {};
}
