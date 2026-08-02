import type { NextFunction, Request, Response } from 'express';
import jwt from 'jsonwebtoken';

import { config } from '../config.js';
import { AppError } from '../lib/errors.js';

export type AccessTokenPayload = {
  sub: string;
  username: string;
  sid?: string;
};

declare global {
  namespace Express {
    interface Request {
      user?: AccessTokenPayload;
    }
  }
}

export function requireAuth(request: Request, _response: Response, next: NextFunction) {
  const header = request.header('authorization');
  const token = header?.startsWith('Bearer ') ? header.slice('Bearer '.length) : null;
  if (!token) throw new AppError(401, 'unauthorized', 'يلزم تسجيل الدخول');

  try {
    request.user = jwt.verify(token, config.jwtAccessSecret) as AccessTokenPayload;
    next();
  } catch {
    throw new AppError(401, 'invalid_token', 'جلسة الدخول غير صالحة');
  }
}
