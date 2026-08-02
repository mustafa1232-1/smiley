# Local Development

1. Start PostgreSQL:

```bash
docker compose up -d postgres
```

2. Start the backend:

```bash
cd backend
npm install
cp .env.example .env
npm run prisma:generate
npm run prisma:migrate
npm run dev
```

3. Start Flutter:

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://localhost:3000/api/v1
```

For Android emulator access to the host backend, use:

```bash
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:3000/api/v1
```
