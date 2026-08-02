import { Router } from 'express';

export const healthRouter = Router();

healthRouter.get('/health', (_request, response) => {
  response.json({ status: 'ok' });
});

healthRouter.get('/ready', (_request, response) => {
  response.json({ status: 'ready' });
});

healthRouter.get('/live', (_request, response) => {
  response.json({ status: 'live' });
});
