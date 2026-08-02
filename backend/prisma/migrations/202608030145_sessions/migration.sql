ALTER TABLE "RefreshToken" ADD COLUMN "sessionId" UUID;

CREATE INDEX "RefreshToken_sessionId_idx" ON "RefreshToken"("sessionId");

ALTER TABLE "RefreshToken"
  ADD CONSTRAINT "RefreshToken_sessionId_fkey"
  FOREIGN KEY ("sessionId") REFERENCES "UserSession"("id")
  ON DELETE SET NULL ON UPDATE CASCADE;
