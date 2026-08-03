import type { NextFunction, Request, Response } from 'express';
import { ZodError } from 'zod';

declare global {
  namespace Express {
    interface Request {
      id: string;
      log: {
        error: (payload: unknown, message: string) => void;
        info: (payload: unknown, message: string) => void;
      };
    }
  }
}

export class AppError extends Error {
  constructor(
    public readonly status: number,
    public readonly code: string,
    message: string,
    public readonly details?: unknown
  ) {
    super(message);
  }
}

export function notFound(_request: Request, _response: Response, next: NextFunction) {
  next(new AppError(404, 'not_found', 'المورد غير موجود'));
}

export function errorHandler(
  error: unknown,
  request: Request,
  response: Response,
  _next: NextFunction
) {
  const appError =
    error instanceof AppError
      ? error
      : error instanceof ZodError
        ? new AppError(422, 'validation_failed', 'المدخلات غير صالحة', error.issues)
      : new AppError(500, 'internal_error', 'حدث خطأ غير متوقع');

  request.log.error({ err: error, requestId: request.id }, appError.message);
  response.status(appError.status).json({
    code: appError.code,
    message: appError.message,
    details: appError.details ?? null,
    requestId: request.id
  });
}
