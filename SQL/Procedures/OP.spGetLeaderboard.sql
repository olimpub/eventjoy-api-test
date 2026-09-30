SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
ALTER PROCEDURE [OP].[spGetLeaderboard]
    @EventID BIGINT,
    @Board NVARCHAR(50),
    @UserID BIGINT = NULL,
    @ExtraGameId NVARCHAR(50) = NULL,
    @RoundID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Szerepkör megállapítása
    DECLARE @IsQM BIT = 0;
    DECLARE @IsOrg BIT = 0;
    IF @UserID IS NOT NULL

    BEGIN
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1) SET @IsOrg = 1;
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.id = 7 AND eu.ActiveFlg = 1) SET @IsQM = 1;
    END

    -- Játékos esetén a "published" szűrő (QM/Org a "closed"-et is látja a boardokon)
    DECLARE @StatusFilter TABLE (StatusID INT);
    INSERT INTO @StatusFilter (StatusID)
    SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'published';

    IF @IsQM = 1 OR @IsOrg = 1 OR @UserID IS NULL
    BEGIN
        INSERT INTO @StatusFilter (StatusID)
        SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'closed';
    END

    IF @Board = 'main'
    BEGIN
        SELECT 
            t.id AS TeamId,
            k.Name,
            ISNULL(rs_agg.F, 0) + ISNULL(p_agg.Points, 0) + ISNULL(es_agg.Points, 0) AS Points,
            ISNULL(db.PreviousPoints, 0) AS PreviousPoints,
            RANK() OVER (ORDER BY ISNULL(rs_agg.F, 0) + ISNULL(p_agg.Points, 0) + ISNULL(es_agg.Points, 0) DESC) AS Place
        FROM [OP].[tblTeam] t
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        OUTER APPLY (
            SELECT SUM(rs.F) AS F FROM [OP].[tblRoundScore] rs WHERE rs.TeamID = t.id AND rs.RoundID IN (
                SELECT id FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID IN (SELECT StatusID FROM @StatusFilter)
            )
        ) rs_agg
        OUTER APPLY (
            SELECT SUM(p.Points) AS Points FROM [OP].[tblPenalty] p WHERE p.TeamID = t.id AND p.ActiveFlg = 1
        ) p_agg
        OUTER APPLY (
            SELECT SUM(es.Points) AS Points FROM [OP].[tblExtraScore] es WHERE es.TeamID = t.id AND es.ExtraRunID IN (
                SELECT id FROM [OP].[tblExtraRun] WHERE EventID = @EventID AND StatusCode = 'closed'
            )
        ) es_agg
        LEFT JOIN [OP].[tblDisplayBoard] db ON db.TeamID = t.id AND db.Board = @Board AND db.EventID = @EventID
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        ORDER BY Place ASC;
    END
    ELSE IF @Board = 'quiz'
    BEGIN
        SELECT 
            t.id AS TeamId,
            k.Name,
            ISNULL(rs_agg.F, 0) AS Points,
            ISNULL(db.PreviousPoints, 0) AS PreviousPoints,
            RANK() OVER (ORDER BY ISNULL(rs_agg.F, 0) DESC) AS Place
        FROM [OP].[tblTeam] t
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        OUTER APPLY (
            SELECT SUM(rs.F) AS F FROM [OP].[tblRoundScore] rs WHERE rs.TeamID = t.id AND rs.RoundID IN (
                SELECT id FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID IN (SELECT StatusID FROM @StatusFilter) AND (@RoundID IS NULL OR id = @RoundID)
            )
        ) rs_agg
        LEFT JOIN [OP].[tblDisplayBoard] db ON db.TeamID = t.id AND db.Board = @Board AND db.EventID = @EventID
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        ORDER BY Place ASC;
    END
    ELSE IF @Board = 'raw'
    BEGIN
        IF @IsQM = 0 AND @IsOrg = 0 AND @UserID IS NOT NULL
        BEGIN
            THROW 50050, N'Játékosként nincs jogosultság a nyers (raw) ranglista lekérdezésére!', 1;
        END

        SELECT 
            t.id AS TeamId,
            k.Name,
            ISNULL(SUM(qs.RawS), 0) AS Points,
            ISNULL(db.PreviousPoints, 0) AS PreviousPoints,
            RANK() OVER (ORDER BY ISNULL(SUM(qs.RawS), 0) DESC) AS Place
        FROM [OP].[tblTeam] t
 
       JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        LEFT JOIN [OP].[tblQuestionScore] qs ON qs.TeamID = t.id AND qs.EventQuestionID IN (
            SELECT eq.id FROM [OP].[tblEventQuestion] eq 
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id 
            WHERE r.EventID = @EventID
        )
        LEFT JOIN [OP].[tblDisplayBoard] db ON db.TeamID = t.id AND db.Board = @Board AND db.EventID = @EventID
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        GROUP BY t.id, k.Name, db.PreviousPoints
        ORDER BY Place ASC;
    END
    ELSE IF @Board = 'games'
    BEGIN
        SELECT 
            t.id AS TeamId,
            k.Name,
            ISNULL(SUM(es.Points), 0) AS Points,
            ISNULL(db.PreviousPoints, 0) AS PreviousPoints,
            RANK() OVER (ORDER BY ISNULL(SUM(es.Points), 0) DESC) AS Place
        FROM [OP].[tblTeam] t
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        LEFT JOIN [OP].[tblExtraScore] es ON es.TeamID = t.id AND es.ExtraRunID IN (
            SELECT id FROM [OP].[tblExtraRun] WHERE EventID = @EventID AND StatusCode = 'closed' AND (@ExtraGameId IS NULL OR ExtraGameId = @ExtraGameId)
        )
        LEFT JOIN [OP].[tblDisplayBoard] db ON db.TeamID = t.id AND db.Board = @Board AND db.EventID = @EventID
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        GROUP BY t.id, k.Name, db.PreviousPoints
   
     ORDER BY Place ASC;
    END
    ELSE IF @Board = 'shadow'
    BEGIN
        SELECT 
            eu.id AS EventUserID,
            ISNULL(u.Nickname, LTRIM(RTRIM(CONCAT(u.FirstName, ' ', u.LastName)))) AS Name,
            ISNULL(srs_agg.F, 0) AS Points,
            ISNULL(db.PreviousPoints, 0) AS PreviousPoints,
            RANK() OVER (ORDER BY ISNULL(srs_agg.F, 0) DESC) AS Place
        FROM [EJ].[tblEventUser] eu
        JOIN [EJ].[tblUser] u ON eu.UserID = u.id
        OUTER APPLY (
            SELECT SUM(srs.F) AS F FROM [OP].[tblShadowRoundScore] srs WHERE srs.EventUserID = eu.id AND srs.RoundID IN (
                SELECT id FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID IN (SELECT StatusID FROM @StatusFilter)
            )
        ) srs_agg
        LEFT JOIN [OP].[tblDisplayBoard] db ON db.TeamID = eu.id AND db.Board = @Board AND db.EventID = @EventID
        WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1
        ORDER BY Place ASC;
    END
END
                                                                                                                                                                                           