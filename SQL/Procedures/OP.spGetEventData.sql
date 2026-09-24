SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spGetEventData]
    @EventID BIGINT,
    @UserID BIGINT = NULL,     -- Játékos vagy QM/Szervező
    @IsDisplay BIT = 0         -- Kivető (csak publikus adatokat lát, CorrectJson NÉLKÜL)
AS
BEGIN
    SET NOCOUNT ON;

    -- Szerepkör megállapítása
    DECLARE @IsQM BIT = 0;
    DECLARE @IsOrg BIT = 0;
    DECLARE @IsPlayer BIT = 0;
    DECLARE @MyTeamID INT = NULL;
    DECLARE @MyEventUserID BIGINT = NULL;

    IF @UserID IS NOT NULL
    BEGIN
        -- Szerepkörök kikeresése
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1) SET @IsOrg = 1;
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 7 AND eu.ActiveFlg = 1) SET @IsQM = 1;
        
        -- Keresünk játékos profilt, hogy megkapja a saját csapatát
        SELECT TOP 1 @MyEventUserID = eu.id 
        FROM [EJ].[tblEventUser] eu 
        WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1;
        
        IF @MyEventUserID IS NOT NULL
        BEGIN
            SET @IsPlayer = 1;
            SELECT TOP 1 @MyTeamID = TeamID FROM [OP].[tblTeamMember] WHERE EventUserID = @MyEventUserID AND ActiveFlg = 1;
        END
    END

    -- Dataset: OpSettings
    SELECT 'OpSettings' AS DatasetName;
    SELECT 
        es.DeskCountHint, 
        es.MaxTeamSize, 
        es.PlannedDurationMin, 
        es.ShadowAwardFlg,
        (SELECT TopicID FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID FOR JSON PATH) AS TopicIdsJson,
        (SELECT ExtraGameId FROM [OP].[tblEventSettingExtraGame] WHERE EventID = @EventID FOR JSON PATH) AS ExtraGameIdsJson
    FROM [OP].[tblEventSettings] es 
    WHERE es.EventID = @EventID;

    -- Dataset: OpTeams
    SELECT 'OpTeams' AS DatasetName;
    SELECT 
        t.id, 
        t.EventID, 
        t.KabalaID, 
        k.Name,
        k.ImageUrl,
        (SELECT COUNT(*) FROM [OP].[tblTeamMember] WHERE TeamID = t.id AND ActiveFlg = 1) AS MemberCount
    FROM [OP].[tblTeam] t
    JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
    WHERE t.EventID = @EventID AND t.ActiveFlg = 1;

    -- Dataset: OpTeamMembers
    SELECT 'OpTeamMembers' AS DatasetName;
    SELECT 
        tm.TeamID, 
        tm.EventUserID
    FROM [OP].[tblTeamMember] tm
    JOIN [OP].[tblTeam] t ON tm.TeamID = t.id
    WHERE t.EventID = @EventID AND tm.ActiveFlg = 1
      -- Ha Játékos (és NEM QM/Org), akkor csak a saját csapatát látja
      AND (@IsQM = 1 OR @IsOrg = 1 OR @IsDisplay = 1 OR tm.TeamID = @MyTeamID);

    -- Dataset: OpRounds
    SELECT 'OpRounds' AS DatasetName;
    SELECT 
        r.id, r.EventID, r.TopicID, r.Mode, rs.Code AS StatusCode, r.SortIndex
    FROM [OP].[tblRound] r
    JOIN [OP].[tblRoundStatus] rs ON r.RoundStatusID = rs.id
    WHERE r.EventID = @EventID AND r.ActiveFlg = 1;

    -- Dataset: OpEventQuestions
    SELECT 'OpEventQuestions' AS DatasetName;
    
    -- Előkészítjük a kérdéseket JSON formában (Opciókkal és Helyes válaszokkal)
    SELECT 
        eq.id, eq.RoundID, eq.QuestionID, eq.SortIndex, eq.StatusCode, eq.StartedAtUtc, eq.TimeSec,
        q.Prompt, q.MediaUrl, qt.Code AS TypeCode,
        (
            SELECT id, ListType, Value, SortIndex 
            FROM [OP].[tblQuestionOption] 
            WHERE QuestionID = q.id 
            ORDER BY SortIndex 
            FOR JSON PATH
        ) AS OptionsJson,
        CASE 
            -- Kivető soha nem látja a helyes választ!
            WHEN @IsDisplay = 1 THEN NULL 
            -- Játékos csak akkor, ha a kérdés active, stopped
            WHEN (@IsQM = 1 OR @IsOrg = 1) OR eq.StatusCode IN ('active', 'stopped') THEN 
            (
                SELECT OptionID, MatchOptionID, SortIndex, TextValue 
                FROM [OP].[tblQuestionCorrectAnswer] 
                WHERE QuestionID = q.id 
                FOR JSON PATH
            )
            ELSE NULL 
        END AS CorrectJson
    FROM [OP].[tblEventQuestion] eq
    JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
    JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
    JOIN [OP].[tblRound] r ON eq.RoundID = r.id
    WHERE r.EventID = @EventID AND eq.ActiveFlg = 1
      -- Játékos / Kivetítő csak azt látja, ami minimum active
      AND (@IsQM = 1 OR @IsOrg = 1 OR eq.StatusCode IN ('active', 'stopped'));

    -- Dataset: OpLive (1 sor)
    SELECT 'OpLive' AS DatasetName;
    SELECT TOP 1
        'idle' AS DisplayState, -- alapértelmezett, a frontend felülírhatja
        (SELECT TOP 1 id FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active') AND ActiveFlg = 1) AS ActiveRoundID,
        (SELECT TOP 1 eq.id FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblRound] r ON eq.RoundID = r.id WHERE r.EventID = @EventID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1) AS ActiveEventQuestionID
        -- ExtraRun később implementálva
    FROM [EJ].[tblEvent] WHERE id = @EventID;

    -- Dataset: OpPenalties
    SELECT 'OpPenalties' AS DatasetName;
    SELECT 
        p.id, p.TeamID, p.Points, p.UndoOfID, p.CreatedAtUtc
    FROM [OP].[tblPenalty] p
    WHERE p.EventID = @EventID AND p.ActiveFlg = 1
      -- Játékos nem kapja meg a büntetés-logot, csak a leaderboardot
      AND (@IsQM = 1 OR @IsOrg = 1 OR @IsDisplay = 1);

END
GO
