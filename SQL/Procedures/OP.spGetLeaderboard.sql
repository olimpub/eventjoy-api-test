SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spGetLeaderboard]
    @EventID BIGINT,
    @Board NVARCHAR(50),
    @UserID BIGINT = NULL
AS
BEGIN
    SET NOCOUNT ON;

    -- Szerepkör megállapítása (Játékos nem láthatja a raw-t, és csak published körök F-jét látja)
    DECLARE @IsQM BIT = 0;
    DECLARE @IsOrg BIT = 0;
    IF @UserID IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1) SET @IsOrg = 1;
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 7 AND eu.ActiveFlg = 1) SET @IsQM = 1;
    END

    -- Játékos esetén a "published" szűrő (QM/Org a "closed"-et is látja a boardokon)
    DECLARE @StatusFilter TABLE (StatusID INT);
    INSERT INTO @StatusFilter (StatusID)
    SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'published';

    IF @IsQM = 1 OR @IsOrg = 1 OR @UserID IS NULL
    BEGIN
        -- QM/Org és Display (NULL UserID) látja a closed-et is
        INSERT INTO @StatusFilter (StatusID)
        SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'closed';
    END

    IF @Board = 'main'
    BEGIN
        SELECT 
            t.id AS TeamId,
            k.Name,
            ISNULL(SUM(rs.F), 0) + ISNULL(SUM(p.Points), 0) AS Points,
            RANK() OVER (ORDER BY ISNULL(SUM(rs.F), 0) + ISNULL(SUM(p.Points), 0) DESC) AS Place
        FROM [OP].[tblTeam] t
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        LEFT JOIN [OP].[tblRoundScore] rs ON rs.TeamID = t.id AND rs.RoundID IN (
            SELECT id FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID IN (SELECT StatusID FROM @StatusFilter)
        )
        LEFT JOIN [OP].[tblPenalty] p ON p.TeamID = t.id AND p.ActiveFlg = 1
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        GROUP BY t.id, k.Name
        ORDER BY Place ASC;
    END
    ELSE IF @Board = 'quiz'
    BEGIN
        SELECT 
            t.id AS TeamId,
            k.Name,
            ISNULL(SUM(rs.F), 0) AS Points,
            RANK() OVER (ORDER BY ISNULL(SUM(rs.F), 0) DESC) AS Place
        FROM [OP].[tblTeam] t
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        LEFT JOIN [OP].[tblRoundScore] rs ON rs.TeamID = t.id AND rs.RoundID IN (
            SELECT id FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID IN (SELECT StatusID FROM @StatusFilter)
        )
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        GROUP BY t.id, k.Name
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
            RANK() OVER (ORDER BY ISNULL(SUM(qs.RawS), 0) DESC) AS Place
        FROM [OP].[tblTeam] t
        JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
        LEFT JOIN [OP].[tblQuestionScore] qs ON qs.TeamID = t.id AND qs.EventQuestionID IN (
            SELECT eq.id FROM [OP].[tblEventQuestion] eq 
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id 
            WHERE r.EventID = @EventID
        )
        WHERE t.EventID = @EventID AND t.ActiveFlg = 1
        GROUP BY t.id, k.Name
        ORDER BY Place ASC;
    END
    ELSE IF @Board = 'shadow'
    BEGIN
        SELECT 
            eu.id AS EventUserID,
            CONCAT(u.FirstName, ' ', u.LastName) AS Name,
            ISNULL(SUM(ss.S), 0) AS Points,
            RANK() OVER (ORDER BY ISNULL(SUM(ss.S), 0) DESC) AS Place
        FROM [EJ].[tblEventUser] eu
        JOIN [EJ].[tblUser] u ON eu.UserID = u.id
        JOIN [OP].[tblTeamMember] tm ON eu.id = tm.EventUserID AND tm.ActiveFlg = 1
        JOIN [OP].[tblTeam] t ON tm.TeamID = t.id AND t.EventID = @EventID
        LEFT JOIN [OP].[tblShadowScore] ss ON ss.EventUserID = eu.id AND ss.EventQuestionID IN (
            SELECT eq.id FROM [OP].[tblEventQuestion] eq 
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id 
            WHERE r.EventID = @EventID
        )
        WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1
        GROUP BY eu.id, u.FirstName, u.LastName
        ORDER BY Place ASC;
    END
    ELSE
    BEGIN
        -- Games board majd Extra futamoknál
        SELECT 1 WHERE 1=0;
    END
END
GO
