-- ============================================================================
-- Migration 006: PTA Különdíjak (surprise & weighted) tábla, jogosultság, szabály
-- Idempotens script (futtatható teszt és éles adatbázison is).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

-- 1. Új tábla: PTA.tblEventSpecialPrize
IF OBJECT_ID(N'[PTA].[tblEventSpecialPrize]', N'U') IS NULL
BEGIN
    CREATE TABLE [PTA].[tblEventSpecialPrize] (
        [EventSpecialPrizeID] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
        [EventID] INT NOT NULL,
        [PrizeKind] NVARCHAR(16) NOT NULL,
        [PrizeName] NVARCHAR(150) NOT NULL,
        [WinnerEventPlayerID] INT NULL,
        [LastUpdatedUserID] BIGINT NULL,
        [createdAt] DATETIMEOFFSET(0) NOT NULL CONSTRAINT [DF_tblEventSpecialPrize_createdAt] DEFAULT (SYSDATETIMEOFFSET()),
        [updatedAt] DATETIMEOFFSET(0) NOT NULL CONSTRAINT [DF_tblEventSpecialPrize_updatedAt] DEFAULT (SYSDATETIMEOFFSET()),
        CONSTRAINT [UQ_tblEventSpecialPrize_Event_Kind] UNIQUE ([EventID], [PrizeKind]),
        CONSTRAINT [CK_tblEventSpecialPrize_Kind] CHECK ([PrizeKind] IN (N'surprise', N'weighted'))
    );
END

-- 2. Alkalmazás DB user jogosultságai az új táblán
IF DATABASE_PRINCIPAL_ID(N'eventjoyapi') IS NOT NULL
BEGIN
    GRANT SELECT, INSERT, UPDATE, DELETE ON [PTA].[tblEventSpecialPrize] TO [eventjoyapi];
END

-- 3. EJ.tblEventActionRule: Pta.SetSpecialPrizeWinner felvétele
IF NOT EXISTS (SELECT 1 FROM [EJ].[tblEventActionRule] WHERE [Action] = N'Pta.SetSpecialPrizeWinner')
BEGIN
    INSERT INTO [EJ].[tblEventActionRule] (
        [Action], ToValue,
        OrganizerExecuteFlg, ContributorExecuteFlg, ParticipantExecuteFlg,
        OrganizerNotifyFlg, ContributorNotifyFlg, ParticipantNotifyFlg, UserNotifyFlg, GroupNotifyFlg,
        ActiveFlg, LastUpdatedUserID, createdAt, updatedAt
    )
    VALUES (
        N'Pta.SetSpecialPrizeWinner', NULL,
        1, 0, 0,
        0, 0, 0, 0, 0,
        1, 1, @Now, @Now
    );
END

COMMIT TRANSACTION;
