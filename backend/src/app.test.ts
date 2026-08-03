import request from 'supertest';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockPrisma = {
  user: {
    findFirst: vi.fn()
  }
};

vi.mock('./lib/prisma.js', () => ({ prisma: mockPrisma }));

const { createApp } = await import('./app.js');

describe('api app contract', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    mockPrisma.user.findFirst.mockResolvedValue(null);
  });

  it('returns standardized errors with requestId for protected routes', async () => {
    const response = await request(createApp())
      .get('/api/v1/me')
      .set('x-request-id', 'test-request-id');

    expect(response.status).toBe(401);
    expect(response.body).toMatchObject({
      code: 'unauthorized',
      message: 'يلزم تسجيل الدخول',
      requestId: 'test-request-id'
    });
    expect(response.body).toHaveProperty('details');
  });

  it('validates optional avatar URL during registration before database writes', async () => {
    const response = await request(createApp())
      .post('/api/v1/auth/register')
      .set('x-request-id', 'avatar-validation')
      .send({
        displayName: 'مستخدم',
        username: 'avatar_user',
        email: 'avatar@example.com',
        avatarUrl: 'not-a-url',
        password: 'strong-password',
        birthDate: '2000-01-01T00:00:00.000Z',
        timezone: 'Asia/Baghdad',
        language: 'ar',
        acceptedTerms: true
      });

    expect(response.status).toBe(422);
    expect(response.body).toMatchObject({
      code: 'validation_failed',
      requestId: 'avatar-validation'
    });
    expect(response.body.details).toEqual(
      expect.arrayContaining([
        expect.objectContaining({ path: ['avatarUrl'] })
      ])
    );
    expect(mockPrisma.user.findFirst).not.toHaveBeenCalled();
  });

  it('does not enumerate accounts in password reset requests', async () => {
    const response = await request(createApp())
      .post('/api/v1/auth/password-reset/request')
      .send({ identifier: '+9647000000000' });

    expect(response.status).toBe(202);
    expect(response.body).toEqual({ status: 'accepted' });
    expect(mockPrisma.user.findFirst).toHaveBeenCalledWith({
      where: {
        OR: [
          { emailNormalized: '+9647000000000' },
          { usernameNormalized: '+9647000000000' },
          { phoneNormalized: '+9647000000000' }
        ],
        deletedAt: null
      }
    });
  });
});
