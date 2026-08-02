CREATE TABLE "GameSession" (
    "id" UUID NOT NULL,
    "partnershipId" UUID NOT NULL,
    "gameType" TEXT NOT NULL,
    "status" TEXT NOT NULL DEFAULT 'active',
    "state" JSONB NOT NULL,
    "currentTurnUserId" UUID,
    "winnerUserId" UUID,
    "createdById" UUID NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "GameSession_pkey" PRIMARY KEY ("id")
);

CREATE INDEX "GameSession_partnershipId_updatedAt_idx" ON "GameSession"("partnershipId", "updatedAt");
CREATE INDEX "GameSession_partnershipId_status_idx" ON "GameSession"("partnershipId", "status");

ALTER TABLE "GameSession"
  ADD CONSTRAINT "GameSession_partnershipId_fkey"
  FOREIGN KEY ("partnershipId") REFERENCES "Partnership"("id")
  ON DELETE CASCADE ON UPDATE CASCADE;
