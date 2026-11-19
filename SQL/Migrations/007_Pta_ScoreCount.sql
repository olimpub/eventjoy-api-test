-- ============================================================================
-- Migration 007: PTA Pontszámítás flag (PTA.tblEventPlayer.ScoreCountFlg)
-- Idempotens script (futtatható teszt és éles adatbázison is).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

-- 1. ScoreCountFlg oszlop hozzáadása a PTA.tblEventPlayer táblához (alapérték: 1)
IF COL_LENGTH(N'[PTA].[tblEventPlayer]', N'ScoreCountFlg') IS NULL
BEGIN
    ALTER TABLE [PTA].[tblEventPlayer]
    ADD [ScoreCountFlg] BIT NOT NULL
        CONSTRAINT [DF_tblEventPlayer_ScoreCountFlg] DEFAULT (1);
END

-- 2. A SELECT * alapú spGetEventUserDataSheet oszlop-metaadatának frissítése
IF OBJECT_ID(N'[EJ].[spGetEventUserDataSheet]', N'P') IS NOT NULL
BEGIN
    EXEC sys.sp_refreshsqlmodule N'[EJ].[spGetEventUserDataSheet]';
END

-- 3. EJ.tblEventActionRule: Pta.SetScoreCount felvétele
IF NOT EXISTS (SELECT 1 FROM [EJ].[tblEventActionRule] WHERE [Action] = N'Pta.SetScoreCount')
BEGIN
    INSERT INTO [EJ].[tblEventActionRule] (
        [Action], ToValue,
        OrganizerExecuteFlg, ContributorExecuteFlg, ParticipantExecuteFlg,
        OrganizerNotifyFlg, ContributorNotifyFlg, ParticipantNotifyFlg, UserNotifyFlg, GroupNotifyFlg,
        ActiveFlg, LastUpdatedUserID, createdAt, updatedAt
    )
    VALUES (
        N'Pta.SetScoreCount', NULL,
        1, 0, 0,
        0, 0, 0, 0, 0,
        1, 1, @Now, @Now
    );
END

COMMIT TRANSACTION;
