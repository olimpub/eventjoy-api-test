SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [PTA].[spGetEventDisplayData]
    @EventID INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Results TABLE (ResultNo SMALLINT, ResultName NVARCHAR(100));

    INSERT INTO @Results (ResultNo, ResultName)
    VALUES
        (1,  N'ReturnStatus'),
        (2,  N'ResultList'),
        (3,  N'Events'),
        (4,  N'EventSettings'),
        (5,  N'EventRounds'),
        (6,  N'EventRoundDesks'),
        (7,  N'GameSchedules'),
        (8,  N'EventPlayers'),
        (9,  N'PtaDisplayState'),
        (10, N'EventSpecialPrizes');

    -- RS 1: ReturnStatus
    SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID;

    -- RS 2: ResultList
    SELECT * FROM @Results ORDER BY ResultNo;

    -- RS 3: Events
    SELECT id, Title, EventUID, EventStatusID, EventTypeID 
    FROM [EJ].[tblEvent] WHERE id = @EventID AND ActiveFlg = 1;

    -- RS 4: EventSettings
    SELECT * FROM [PTA].[tblEventSettings] WHERE EventID = @EventID;

    -- RS 5: EventRounds (Minden statusz)
    SELECT r.*, s.SName 
    FROM [PTA].[tblEventRound] r
    JOIN [PTA].[tblEventRoundStatus] s ON r.EventRoundStatusID = s.EventRoundStatusID
    WHERE r.EventID = @EventID;

    -- RS 6: EventRoundDesks (Minden statusz)
    SELECT erd.*, ed.DeskNumber,
           CASE WHEN erd.CompletedAtUtc IS NOT NULL THEN N'Lezárt' ELSE N'Folyamatban' END AS SName
    FROM [PTA].[tblEventRoundDesk] erd
    INNER JOIN [PTA].[tblEventRound] er ON er.EventRoundID = erd.EventRoundID
    LEFT JOIN [PTA].[tblEventDesk] ed ON erd.EventDeskID = ed.EventDeskID
    WHERE er.EventID = @EventID AND erd.ActiveFlg = 1;

    -- RS 7: GameSchedules (Minden statusz)
    SELECT 
        gs.GameScheduleID,
        gs.EventRoundDeskID,
        gs.PlayerID,
        gs.PlayColorHex,
        CASE WHEN er.EventRoundStatusID IN (4, 5) THEN gs.Amount ELSE NULL END AS Amount,
        CASE WHEN er.EventRoundStatusID IN (4, 5) THEN gs.OnTrack ELSE NULL END AS OnTrack,
        CASE WHEN er.EventRoundStatusID IN (4, 5) THEN gs.Position ELSE NULL END AS Position,
        CASE WHEN er.EventRoundStatusID IN (4, 5) THEN gs.ResultPoint ELSE NULL END AS ResultPoint,
        CASE WHEN er.EventRoundStatusID IN (4, 5) THEN gs.FinalPoint ELSE NULL END AS FinalPoint,
        gs.ActiveFlg,
        gs.LastUpdatedUserID,
        gs.createdAt,
        gs.updatedAt
    FROM [PTA].[tblGameSchedule] gs
    INNER JOIN [PTA].[tblEventRoundDesk] erd ON erd.EventRoundDeskID = gs.EventRoundDeskID
    INNER JOIN [PTA].[tblEventRound] er ON er.EventRoundID = erd.EventRoundID
    WHERE er.EventID = @EventID AND gs.ActiveFlg = 1;

    -- RS 8: EventPlayers
    SELECT ep.EventPlayerID, ep.EventID, ep.EventUserID, ep.NickName AS Name, ep.TeamName, ep.OrganizationName, ep.RegionName, ep.CompanyName,
           ep.ScoreCountFlg,
           u.FirstName, u.LastName
    FROM [PTA].[tblEventPlayer] ep
    JOIN [EJ].[tblEventUser] eu ON ep.EventUserID = eu.id
    JOIN [EJ].[tblUser] u ON eu.UserID = u.id
    WHERE ep.EventID = @EventID AND ep.ActiveFlg = 1;

    -- RS 9: PtaDisplayState
    SELECT *, RoundId AS EventRoundID FROM [PTA].[tblPtaDisplayState] WHERE EventID = @EventID;

    -- RS 10: EventSpecialPrizes
    SELECT EventID, PrizeKind, PrizeName, WinnerEventPlayerID
    FROM [PTA].[tblEventSpecialPrize]
    WHERE EventID = @EventID;

END
GO
