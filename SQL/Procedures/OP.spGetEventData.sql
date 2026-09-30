SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
ALTER PROCEDURE [OP].[spGetEventData]
    @EventID BIGINT,
    @UserID BIGINT = NULL,
    @IsDisplay BIT = 0
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsQM BIT = 0;
    DECLARE @IsOrg BIT = 0;
    DECLARE @IsPlayer BIT = 0;
    DECLARE @MyTeamID INT = NULL;
    DECLARE @MyEventUserID BIGINT = NULL;

    IF @UserID IS NOT NULL
    BEGIN
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1) SET @IsOrg = 1;
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 7 AND eu.ActiveFlg = 1) SET @IsQM = 1;
        
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
        es.CurrentFlg,
        es.StateVersion,
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
        (SELECT TOP 1 a.BlobUrl FROM [OP].[tblKabalaAsset] a WHERE a.KabalaID = k.id AND a.Slot = 'profile' AND a.ActiveFlg = 1) AS ImageUrl,
        (SELECT COUNT(*) FROM [OP].[tblTeamMember] WHERE TeamID = t.id AND ActiveFlg = 1) AS MemberCount
    FROM [OP].[tblTeam] t
    JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
    WHERE t.EventID = @EventID AND t.ActiveFlg = 1;

        -- Dataset: OpTeamMembers
    SELECT 'OpTeamMembers' AS DatasetName;
    SELECT 
        tm.TeamID, 
        tm.EventUserID,
        u.Nickname
    FROM [OP].[tblTeamMember] tm
    JOIN [OP].[tblTeam] t ON tm.TeamID = t.id
    JOIN [EJ].[tblEventUser] eu ON tm.EventUserID = eu.id
    JOIN [EJ].[tblUser] u ON eu.UserID = u.id
    WHERE t.EventID = @EventID AND tm.ActiveFlg = 1
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
    SELECT 
        eq.id, eq.RoundID, eq.QuestionID, eq.SortIndex, eq.StatusCode, eq.StartedAtUtc, eq.TimeSec, eq.ClockPaused, eq.ClockLeftMs,
        q.Prompt, q.MediaUrl, q.ImageKey, q.AudioKey, qt.Code AS TypeCode,
        (SELECT id, ListType, Value, SortIndex FROM [OP].[tblQuestionOption] WHERE QuestionID = q.id ORDER BY SortIndex FOR JSON PATH) AS OptionsJson,
        CASE 
            WHEN @IsDisplay = 1 THEN NULL 
            WHEN (@IsQM = 1 OR @IsOrg = 1) OR eq.StatusCode IN ('active', 'stopped') THEN 
            (SELECT OptionID, MatchOptionID, SortIndex, TextValue FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = q.id FOR JSON PATH)
            ELSE NULL 
        END AS CorrectJson
    FROM [OP].[tblEventQuestion] eq
    JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
    JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
    JOIN [OP].[tblRound] r ON eq.RoundID = r.id
    WHERE r.EventID = @EventID AND eq.ActiveFlg = 1
      AND (@IsQM = 1 OR @IsOrg = 1 OR eq.StatusCode IN ('active', 'stopped'));

                -- Dataset: OpLive (1 sor)
    SELECT 'OpLive' AS DatasetName;
    SELECT TOP 1
        es.StateVersion,
        eq.RoundID AS ActiveRoundID,
        eq.id AS ActiveEventQuestionID,
        eq.SortIndex AS ActiveQuestionSortIndex,
        eq.StatusCode AS QuestionStatus,
        (SELECT COUNT(DISTINCT EventUserID) FROM [OP].[tblAnswer] WHERE EventQuestionID = eq.id AND ActiveFlg = 1) AS AnswerCount,
        (SELECT COUNT(DISTINCT tm.EventUserID) FROM [OP].[tblTeamMember] tm JOIN [OP].[tblTeam] t ON tm.TeamID = t.id WHERE t.EventID = @EventID AND t.ActiveFlg = 1 AND tm.ActiveFlg = 1) AS RosterCount,
        eq.StartedAtUtc,
        eq.TimeSec,
        eq.StoppedAtUtc,
        eq.ClockPaused,
        eq.ClockLeftMs,
        xr.id AS ExtraRunID,
        xr.ExtraGameId,
        xeq.id AS ActiveExtraQuestionID,
        xeq.StatusCode AS ExtraQuestionStatus
    FROM [OP].[tblEventSettings] es
    LEFT JOIN [OP].[tblRound] rActive ON rActive.EventID = @EventID AND rActive.ActiveFlg = 1 AND rActive.RoundStatusID = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active')
    LEFT JOIN [OP].[tblEventQuestion] eq ON eq.id = ISNULL(rActive.FocusedEventQuestionID, (
        SELECT TOP 1 id FROM [OP].[tblEventQuestion] WHERE RoundID = rActive.id AND ActiveFlg = 1 ORDER BY CASE StatusCode WHEN 'active' THEN 1 WHEN 'stopped' THEN 2 ELSE 3 END ASC, SortIndex ASC
    ))
    LEFT JOIN [OP].[tblExtraRun] xr ON xr.EventID = @EventID AND xr.StatusCode = 'active'
    LEFT JOIN [OP].[tblExtraQuestion] xeq ON xeq.ExtraRunID = xr.id AND xeq.StatusCode IN ('active', 'stopped')
    WHERE es.EventID = @EventID;


    

    
    -- Dataset: OpExtraPool
    SELECT 'OpExtraPool' AS DatasetName;
    SELECT 
        xeq.id, xr.ExtraGameId, xeq.SortIndex, xeq.StatusCode, xeq.StartedAtUtc, xeq.StoppedAtUtc,
        xeq.Prompt, qt.Code AS TypeCode, xeq.TimeSec,
        (SELECT id, ListType, Value, SortIndex FROM [OP].[tblExtraQuestionOption] WHERE ExtraQuestionID = xeq.id ORDER BY SortIndex FOR JSON PATH) AS OptionsJson,
        CASE WHEN (@IsQM = 1 OR @IsOrg = 1 OR @IsPlayer = 1) THEN 
            (SELECT OptionID, MatchOptionID, SortIndex, TextValue FROM [OP].[tblExtraQuestionCorrectAnswer] WHERE ExtraQuestionID = xeq.id FOR JSON PATH)
        ELSE NULL END AS CorrectJson
    FROM [OP].[tblExtraQuestion] xeq
    JOIN [OP].[tblExtraRun] xr ON xeq.ExtraRunID = xr.id
    JOIN [OP].[tblQuestionType] qt ON xeq.QuestionTypeID = qt.id
    WHERE xr.EventID = @EventID AND xr.StatusCode = 'active';

    -- Dataset: DisplayCast (1 sor)
    SELECT 'DisplayCast' AS DatasetName;
    SELECT 
        Face, PayloadJson, StateVersion, UpdatedAtUtc
    FROM [OP].[DisplayCast]
    WHERE EventID = @EventID;

    -- Dataset: OpPenalties
    SELECT 'OpPenalties' AS DatasetName;
    SELECT 
        p.id, p.TeamID, p.Points, p.UndoOfID, p.CreatedAtUtc
    FROM [OP].[tblPenalty] p
    WHERE p.EventID = @EventID AND p.ActiveFlg = 1
      AND (@IsQM = 1 OR @IsOrg = 1 OR @IsDisplay = 1);

    
END
GO
