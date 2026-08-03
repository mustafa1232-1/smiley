import request from 'supertest';
import jwt from 'jsonwebtoken';
import { beforeEach, describe, expect, it, vi } from 'vitest';

const mockPrisma = {
  user: {
    findFirst: vi.fn()
  },
  partnership: {
    findFirst: vi.fn()
  },
  timeCapsule: {
    findFirst: vi.fn(),
    update: vi.fn()
  }
};

vi.mock('./lib/prisma.js', () => ({ prisma: mockPrisma }));

const { createApp } = await import('./app.js');
const { _resetThrottle } = await import('./lib/login-throttle.js');

function accessTokenFor(sub: string, username = 'tester') {
  return jwt.sign({ sub, username }, 'dev-access-secret');
}

describe('api app contract', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    _resetThrottle();
    mockPrisma.user.findFirst.mockResolvedValue(null);
    mockPrisma.partnership.findFirst.mockResolvedValue(null);
    mockPrisma.timeCapsule.findFirst.mockResolvedValue(null);
    mockPrisma.timeCapsule.update.mockResolvedValue(null);
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

  it('does not reveal or open time capsules before their opening date', async () => {
    const accessToken = jwt.sign(
      { sub: '11111111-1111-4111-8111-111111111111', username: 'tester' },
      'dev-access-secret'
    );
    const opensAt = new Date(Date.now() + 86_400_000);
    mockPrisma.partnership.findFirst.mockResolvedValue({
      id: '22222222-2222-4222-8222-222222222222',
      status: 'active'
    });
    mockPrisma.timeCapsule.findFirst.mockResolvedValue({
      id: '33333333-3333-4333-8333-333333333333',
      partnershipId: '22222222-2222-4222-8222-222222222222',
      creatorId: '11111111-1111-4111-8111-111111111111',
      title: 'locked',
      body: 'secret',
      opensAt,
      openedAt: null,
      createdAt: new Date()
    });

    const response = await request(createApp())
      .post('/api/v1/time-capsules/33333333-3333-4333-8333-333333333333/open')
      .set('authorization', `Bearer ${accessToken}`);

    expect(response.status).toBe(409);
    expect(response.body).toMatchObject({
      code: 'time_capsule_locked',
      details: { opensAt: opensAt.toISOString() }
    });
    expect(response.text).not.toContain('secret');
    expect(mockPrisma.timeCapsule.update).not.toHaveBeenCalled();
  });

  it('rejects presign requests for disallowed upload types', async () => {
    const response = await request(createApp())
      .post('/api/v1/uploads/presign')
      .set('authorization', `Bearer ${accessTokenFor('44444444-4444-4444-8444-444444444444')}`)
      .send({ mimeType: 'text/html', sizeBytes: 1024 });

    expect(response.status).toBe(422);
    expect(response.body).toMatchObject({ code: 'validation_failed' });
  });

  it('requires a password to delete the account', async () => {
    const response = await request(createApp())
      .delete('/api/v1/me')
      .set('authorization', `Bearer ${accessTokenFor('55555555-5555-4555-8555-555555555555')}`)
      .send({});

    expect(response.status).toBe(422);
    expect(response.body).toMatchObject({ code: 'validation_failed' });
    expect(mockPrisma.user.findFirst).not.toHaveBeenCalled();
  });

  it('locks the account after repeated failed login attempts', async () => {
    const app = createApp();
    const attempt = () =>
      request(app)
        .post('/api/v1/auth/login')
        .send({ identifier: 'locktest', password: 'wrong-password' });

    for (let i = 0; i < 8; i += 1) {
      const failed = await attempt();
      expect(failed.status).toBe(401);
    }

    const locked = await attempt();
    expect(locked.status).toBe(429);
    expect(locked.body).toMatchObject({ code: 'account_locked' });
  });
});
