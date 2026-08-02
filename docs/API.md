# API

Base path: `/api/v1`

## Auth

### `POST /auth/register`

Creates a user and returns an auth session.

Request:

```json
{
  "displayName": "مستخدم",
  "username": "user.name",
  "email": "user@example.com",
  "password": "strong-password",
  "birthDate": "2000-01-01T00:00:00.000Z",
  "timezone": "Asia/Baghdad",
  "language": "ar",
  "acceptedTerms": true
}
```

### `POST /auth/login`

Request:

```json
{
  "identifier": "user.name",
  "password": "strong-password"
}
```

### `POST /auth/password-reset/request`

Always returns `202` to avoid account enumeration.

## Users

### `GET /users/search?username=value`

Requires bearer token. Returns public limited profile fields:

- `displayName`
- `username`
- `avatarUrl`
- `canReceiveRequests`

## Partnerships

### `POST /partnership-requests`

Requires bearer token.

```json
{
  "username": "partner.username"
}
```

### `GET /partnership-requests`

Requires bearer token. Returns pending requests for the current user.

## Error Shape

```json
{
  "code": "validation_failed",
  "message": "المدخلات غير صالحة",
  "details": [],
  "requestId": "request-id"
}
```
