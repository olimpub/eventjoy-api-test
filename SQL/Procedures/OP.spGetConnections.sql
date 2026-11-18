CREATE OR ALTER PROCEDURE [OP].[spGetConnections]
    @EventID BIGINT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @IsAuthorized BIT = 0;

    IF @UserID IS NOT NULL
    BEGIN
        IF EXISTS (
            SELECT 1
            FROM [EJ].[tblEventUser] eu
            JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
            JOIN [EJ].[tblRole] r ON er.RoleID = r.id
            WHERE eu.EventID = @EventID
              AND eu.UserID = @UserID
              AND eu.ActiveFlg = 1
              AND (r.RoleTypeID IN (1, 2) OR r.id = 7)
        )
        BEGIN
            SET @IsAuthorized = 1;
        END
    END

    IF @IsAuthorized = 0
    BEGIN
        THROW 50030, N'Nincs megfelelő jogosultságod a kapcsolatok megtekintéséhez!', 1;
    END

    DECLARE @NowUtc DATETIME2 = SYSUTCDATETIME();
    DECLARE @CutoffUtc DATETIME2 = DATEADD(MINUTE, -5, @NowUtc);

    -- 1. Players
    ;WITH ActiveTeamMembers AS (
        SELECT
            tm.EventUserID,
            tm.TeamID,
            k.Name AS TeamName,
            tm.LastSeenUtc,
            ROW_NUMBER() OVER (PARTITION BY tm.EventUserID ORDER BY tm.LastSeenUtc DESC, tm.id DESC) AS rn
        FROM [OP].[tblTeamMember] tm
        JOIN [OP].[tblTeam] t ON tm.TeamID = t.id
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1 AND tm.ActiveFlg = 1
    ),
    GamerConnections AS (
        SELECT
            cc.EventUserID,
            SUM(CASE WHEN cc.ActiveFlg = 1 THEN 1 ELSE 0 END) AS DeviceCount,
            MAX(cc.LastSeenUtc) AS LastSeenUtc
        FROM [OP].[tblClientConnection] cc
        WHERE cc.EventID = @EventID
          AND cc.RoleGroup = 'gamer'
          AND cc.EventUserID IS NOT NULL
          AND (cc.ActiveFlg = 1 OR cc.LastSeenUtc >= @CutoffUtc)
        GROUP BY cc.EventUserID
    ),
    AllPlayerIds AS (
        SELECT EventUserID FROM ActiveTeamMembers WHERE rn = 1
        UNION
        SELECT EventUserID FROM GamerConnections
    )
    SELECT
        p.EventUserID,
        u.Nickname,
        atm.TeamID,
        atm.TeamName,
        CAST(CASE WHEN ISNULL(gc.DeviceCount, 0) > 0 THEN 1 ELSE 0 END AS BIT) AS Online,
        ISNULL(gc.DeviceCount, 0) AS DeviceCount,
        TODATETIMEOFFSET(
            CASE
                WHEN gc.LastSeenUtc IS NOT NULL AND (atm.LastSeenUtc IS NULL OR gc.LastSeenUtc >= atm.LastSeenUtc) THEN gc.LastSeenUtc
                ELSE atm.LastSeenUtc
            END,
            0
        ) AS LastSeenUtc
    INTO #PlayersOut
    FROM AllPlayerIds p
    JOIN [EJ].[tblEventUser] eu ON p.EventUserID = eu.id
    JOIN [EJ].[tblUser] u ON eu.UserID = u.id
    LEFT JOIN ActiveTeamMembers atm ON atm.EventUserID = p.EventUserID AND atm.rn = 1
    LEFT JOIN GamerConnections gc ON gc.EventUserID = p.EventUserID
    WHERE atm.TeamID IS NOT NULL
       OR ISNULL(gc.DeviceCount, 0) > 0
       OR COALESCE(gc.LastSeenUtc, atm.LastSeenUtc) >= @CutoffUtc;

    -- 2. Displays
    ;WITH DisplayConnections AS (
        SELECT
            cc.DisplayID,
            SUM(CASE WHEN cc.ActiveFlg = 1 THEN 1 ELSE 0 END) AS ConnectionCount,
            MIN(cc.ConnectedAtUtc) AS ConnectedAtUtc,
            MAX(cc.LastSeenUtc) AS LastSeenUtc
        FROM [OP].[tblClientConnection] cc
        WHERE cc.EventID = @EventID
          AND cc.RoleGroup = 'display'
          AND cc.DisplayID IS NOT NULL
          AND (cc.ActiveFlg = 1 OR cc.LastSeenUtc >= @CutoffUtc)
        GROUP BY cc.DisplayID
    )
    SELECT
        dt.id AS DisplayID,
        ISNULL(dt.Label, N'Kijelző ' + CAST(ROW_NUMBER() OVER (ORDER BY dt.id ASC) AS NVARCHAR(20))) AS Label,
        CAST(CASE WHEN ISNULL(dc.ConnectionCount, 0) > 0 THEN 1 ELSE 0 END AS BIT) AS Online,
        ISNULL(dc.ConnectionCount, 0) AS ConnectionCount,
        TODATETIMEOFFSET(COALESCE(dc.ConnectedAtUtc, dt.ConnectedAtUtc), 0) AS ConnectedAtUtc,
        TODATETIMEOFFSET(
            CASE
                WHEN dc.LastSeenUtc IS NOT NULL AND (dt.LastSeenUtc IS NULL OR dc.LastSeenUtc >= dt.LastSeenUtc) THEN dc.LastSeenUtc
                ELSE dt.LastSeenUtc
            END,
            0
        ) AS LastSeenUtc
    INTO #DisplaysOut
    FROM [PTA].[tblEventDisplayToken] dt
    LEFT JOIN DisplayConnections dc ON dc.DisplayID = dt.id
    WHERE dt.EventID = @EventID
      AND dt.Module = 'op'
      AND (
          ISNULL(dc.ConnectionCount, 0) > 0
          OR (
              dt.TokenActiveFlg = 1
              AND (dt.ConnectedAtUtc IS NOT NULL OR dc.ConnectedAtUtc IS NOT NULL)
              AND COALESCE(dc.LastSeenUtc, dt.LastSeenUtc) >= @CutoffUtc
          )
      );

    SELECT EventUserID, Nickname, TeamID, TeamName, Online, DeviceCount, LastSeenUtc
    FROM #PlayersOut
    ORDER BY Online DESC, TeamName ASC, Nickname ASC;

    SELECT DisplayID, Label, Online, ConnectionCount, ConnectedAtUtc, LastSeenUtc
    FROM #DisplaysOut
    ORDER BY Online DESC, DisplayID ASC;

    SELECT
        (SELECT COUNT(*) FROM #PlayersOut WHERE Online = 1) AS PlayersOnline,
        (SELECT COUNT(*) FROM #PlayersOut WHERE TeamID IS NOT NULL) AS PlayersInTeams,
        (SELECT COUNT(*) FROM #DisplaysOut WHERE Online = 1) AS DisplaysOnline;
END
GO
