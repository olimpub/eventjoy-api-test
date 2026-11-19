-- ============================================================================
-- Migration 005: PTA Négyes Döntő (3 fordulós + döntő) törzsadat és szabályok
-- Idempotens script (futtatható teszt és éles adatbázison is).
-- ============================================================================
SET NOCOUNT ON;
SET XACT_ABORT ON;

BEGIN TRANSACTION;

DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

-- 1. A meglévő '3 fordulós alap' (GameTypeID = 1) fordulóin FinalRoundFlg = 0 biztosítása,
--    hogy a régi játéktípus viselkedése változatlan maradjon.
UPDATE [PTA].[tblGameTypeRounds]
SET FinalRoundFlg = 0,
    updatedAt = @Now
WHERE GameTypeID = 1
  AND FinalRoundFlg = 1;

-- 2. Új játéktípus: '3 fordulós + döntő'
DECLARE @FinalFourGameTypeID INT = (
    SELECT TOP 1 GameTypeID
    FROM [PTA].[tblGameType]
    WHERE GName = N'3 fordulós + döntő'
);

IF @FinalFourGameTypeID IS NULL
BEGIN
    INSERT INTO [PTA].[tblGameType] (GName, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
    VALUES (N'3 fordulós + döntő', 1, 0, @Now, @Now);

    SET @FinalFourGameTypeID = SCOPE_IDENTITY();
END

-- 3. A 4 forduló sablon felvétele / szinkronizálása az új játéktípushoz
IF NOT EXISTS (SELECT 1 FROM [PTA].[tblGameTypeRounds] WHERE GameTypeID = @FinalFourGameTypeID AND OrderIndex = 1)
BEGIN
    INSERT INTO [PTA].[tblGameTypeRounds] (GameTypeID, OrderIndex, RName, QualifyToNextRound, ResultsVisibleFlg, FinalRoundFlg, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
    VALUES (@FinalFourGameTypeID, 1, N'1. forduló', NULL, 1, 0, 1, 0, @Now, @Now);
END

IF NOT EXISTS (SELECT 1 FROM [PTA].[tblGameTypeRounds] WHERE GameTypeID = @FinalFourGameTypeID AND OrderIndex = 2)
BEGIN
    INSERT INTO [PTA].[tblGameTypeRounds] (GameTypeID, OrderIndex, RName, QualifyToNextRound, ResultsVisibleFlg, FinalRoundFlg, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
    VALUES (@FinalFourGameTypeID, 2, N'2. forduló', NULL, 1, 0, 1, 0, @Now, @Now);
END

IF NOT EXISTS (SELECT 1 FROM [PTA].[tblGameTypeRounds] WHERE GameTypeID = @FinalFourGameTypeID AND OrderIndex = 3)
BEGIN
    INSERT INTO [PTA].[tblGameTypeRounds] (GameTypeID, OrderIndex, RName, QualifyToNextRound, ResultsVisibleFlg, FinalRoundFlg, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
    VALUES (@FinalFourGameTypeID, 3, N'3. forduló', 4, 1, 0, 1, 0, @Now, @Now);
END
ELSE
BEGIN
    UPDATE [PTA].[tblGameTypeRounds]
    SET QualifyToNextRound = 4, FinalRoundFlg = 0, updatedAt = @Now
    WHERE GameTypeID = @FinalFourGameTypeID AND OrderIndex = 3;
END

IF NOT EXISTS (SELECT 1 FROM [PTA].[tblGameTypeRounds] WHERE GameTypeID = @FinalFourGameTypeID AND OrderIndex = 4)
BEGIN
    INSERT INTO [PTA].[tblGameTypeRounds] (GameTypeID, OrderIndex, RName, QualifyToNextRound, ResultsVisibleFlg, FinalRoundFlg, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
    VALUES (@FinalFourGameTypeID, 4, N'Döntő', NULL, 0, 1, 1, 0, @Now, @Now);
END
ELSE
BEGIN
    UPDATE [PTA].[tblGameTypeRounds]
    SET QualifyToNextRound = NULL, FinalRoundFlg = 1, updatedAt = @Now
    WHERE GameTypeID = @FinalFourGameTypeID AND OrderIndex = 4;
END

-- 4. EJ.tblEventActionRule: Pta.SeatFinal felvétele (Notify flagek = 0, hogy a szabálytábla ne duplikálja a gamer üzenetet)
IF NOT EXISTS (SELECT 1 FROM [EJ].[tblEventActionRule] WHERE [Action] = N'Pta.SeatFinal')
BEGIN
    INSERT INTO [EJ].[tblEventActionRule] (
        [Action], ToValue,
        OrganizerExecuteFlg, ContributorExecuteFlg, ParticipantExecuteFlg,
        OrganizerNotifyFlg, ContributorNotifyFlg, ParticipantNotifyFlg, UserNotifyFlg, GroupNotifyFlg,
        ActiveFlg, LastUpdatedUserID, createdAt, updatedAt
    )
    VALUES (
        N'Pta.SeatFinal', NULL,
        1, 0, 0,
        0, 0, 0, 0, 0,
        1, 1, @Now, @Now
    );
END

COMMIT TRANSACTION;
