-- =============================================
-- Author:		EventJoy
-- Create date: 
-- Description:	V2 Refactored get event data (with Section 5 Question Card, Clock & Screen state)
-- =============================================
CREATE OR ALTER PROCEDURE [OP].[spGetEventData]
    @EventID BIGINT,
    @UserID BIGINT = NULL,
    @IsDisplay BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    DECLARE @IsQM BIT = 0;
    DECLARE @IsOrg BIT = 0;
    DECLARE @IsPlayer BIT = 0;
    DECLARE @MyTeamID INT = NULL;
    DECLARE @MyEventUserID BIGINT = NULL;

    IF @UserID IS NULL
    BEGIN
        SET @IsDisplay = 1;
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1) SET @IsOrg = 1;
        IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND (r.id = 7 OR r.RoleTypeID = 2) AND eu.ActiveFlg = 1) SET @IsQM = 1;
        
        SELECT TOP 1 @MyEventUserID = eu.id 
        FROM [EJ].[tblEventUser] eu 
        WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1;
        
        IF @MyEventUserID IS NOT NULL
        BEGIN
            SET @IsPlayer = 1;
            SELECT TOP 1 @MyTeamID = TeamID FROM [OP].[tblTeamMember] WHERE EventUserID = @MyEventUserID AND ActiveFlg = 1;
        END
    END

    DECLARE @BlobBaseUrl NVARCHAR(200) = N'https://eventjoyteststorage.blob.core.windows.net/op-media/' + CAST(@EventID AS NVARCHAR(20)) + N'/';

    -- Dataset: OpSettings
    SELECT 'OpSettings' AS DatasetName;
    SELECT 
        es.DeskCountHint, es.MaxTeamSize, es.PlannedDurationMin, es.ShadowAwardFlg, es.CurrentFlg, es.StateVersion,
        (SELECT TopicID FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID FOR JSON PATH) AS TopicIdsJson,
        CAST('[]' AS NVARCHAR(MAX)) AS ExtraGameIdsJson
    FROM [OP].[tblEventSettings] es 
    WHERE es.EventID = @EventID;

    -- Dataset: OpTeams
    SELECT 'OpTeams' AS DatasetName;
    SELECT 
        t.id, t.EventID, t.KabalaID, k.Name,
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
        u.Nickname,
        TODATETIMEOFFSET(tm.LastSeenUtc, 0) AS LastSeenUtc,
        CAST(CASE WHEN tm.LastSeenUtc IS NOT NULL AND tm.LastSeenUtc >= DATEADD(MINUTE, -3, SYSUTCDATETIME()) THEN 1 ELSE 0 END AS BIT) AS Online
    FROM [OP].[tblTeamMember] tm
    JOIN [OP].[tblTeam] t ON tm.TeamID = t.id
    JOIN [EJ].[tblEventUser] eu ON tm.EventUserID = eu.id
    JOIN [EJ].[tblUser] u ON eu.UserID = u.id
    WHERE t.EventID = @EventID AND tm.ActiveFlg = 1
      AND (@IsQM = 1 OR @IsOrg = 1 OR @IsDisplay = 1 OR tm.TeamID = @MyTeamID);

    -- Dataset: OpRounds
    SELECT 'OpRounds' AS DatasetName;
    SELECT 
        r.id,
        r.EventID,
        r.TopicID,
        COALESCE(topR.Name, rt.Name, N'') AS TopicName,
        r.Mode,
        rs.Code AS StatusCode,
        r.SortIndex,
        rt.Code AS RoundTypeCode
    FROM [OP].[tblRound] r
    JOIN [OP].[tblRoundStatus] rs ON r.RoundStatusID = rs.id
    JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
    LEFT JOIN [OP].[tblTopic] topR ON r.TopicID = topR.id
    WHERE r.EventID = @EventID AND r.ActiveFlg = 1;

    -- Dataset: OpEventQuestions
    -- §5.1: A helyes választ (CorrectJson) csak a staff (QM / Organizer) kapja meg!
    SELECT 'OpEventQuestions' AS DatasetName;
    SELECT 
        eq.id,
        eq.EventID,
        eq.RoundID,
        eq.QuestionID,
        eq.SortIndex,
        eq.StatusCode,
        TODATETIMEOFFSET(eq.StartedAtUtc, 0) AS StartedAtUtc,
        TODATETIMEOFFSET(eq.AnswerStartedAtUtc, 0) AS AnswerStartedAtUtc,
        TODATETIMEOFFSET(eq.StoppedAtUtc, 0) AS StoppedAtUtc,
        (SELECT COUNT(DISTINCT EventUserID) FROM [OP].[tblAnswer] WHERE EventQuestionID = eq.id AND ActiveFlg = 1) AS AnswerCount,
        eq.TimeSec,
        eq.ClockPaused,
        eq.ClockLeftMs,
        q.Prompt,
        q.MediaUrl,
        q.ImageKey,
        q.AudioKey,
        qt.Code AS TypeCode,
        COALESCE(topR.Name, topQ.Name, rt.Name, N'') AS TopicName,
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
    JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
    LEFT JOIN [OP].[tblTopic] topR ON r.TopicID = topR.id
    LEFT JOIN [OP].[tblTopic] topQ ON q.TopicID = topQ.id
    WHERE r.EventID = @EventID AND eq.ActiveFlg = 1
      AND (@IsQM = 1 OR @IsOrg = 1 OR eq.StatusCode IN ('active', 'stopped'));

    -- Dataset: OpLive (1 sor)
    SELECT 'OpLive' AS DatasetName;
    SELECT TOP 1
        es.StateVersion,
        ISNULL(es.PlayerFace, '') AS PlayerFace,
        ISNULL(es.Screen, 'idle') AS Screen,
        ISNULL(es.Screen, 'idle') AS DisplayState,
        es.ScreenJson,
        rActive.id AS ActiveRoundID,
        eq.RoundID AS RoundID,
        eq.id AS ActiveEventQuestionID,
        eq.id AS FocusedEventQuestionID,
        eq.id AS EventQuestionID,
        eq.SortIndex AS ActiveQuestionSortIndex,
        eq.SortIndex AS SortIndex,
        eq.StatusCode AS QuestionStatus,
        (SELECT COUNT(DISTINCT EventUserID) FROM [OP].[tblAnswer] WHERE EventQuestionID = eq.id AND ActiveFlg = 1) AS AnswerCount,
        (SELECT COUNT(DISTINCT tm.EventUserID) FROM [OP].[tblTeamMember] tm JOIN [OP].[tblTeam] t ON tm.TeamID = t.id WHERE t.EventID = @EventID AND t.ActiveFlg = 1 AND tm.ActiveFlg = 1) AS RosterCount,
        TODATETIMEOFFSET(eq.StartedAtUtc, 0) AS StartedAtUtc,
        TODATETIMEOFFSET(COALESCE(eq.AnswerStartedAtUtc, es.AnswerStartedAtUtc), 0) AS AnswerStartedAtUtc,
        eq.TimeSec,
        TODATETIMEOFFSET(eq.StoppedAtUtc, 0) AS StoppedAtUtc,
        eq.ClockPaused,
        eq.ClockLeftMs,
        -- Aktív kérdéslap mezők (§5.2) helyes válasz nélkül:
        q.Prompt,
        qt.Code AS TypeCode,
        COALESCE(topR.Name, topQ.Name, rt.Name, N'') AS TopicName,
        q.ImageKey,
        CASE WHEN q.ImageKey IS NOT NULL AND q.ImageKey != ''
             THEN CASE WHEN q.ImageKey LIKE 'http%' THEN q.ImageKey ELSE @BlobBaseUrl + q.ImageKey END
             ELSE q.MediaUrl
        END AS ImageUrl,
        q.AudioKey,
        CASE WHEN q.AudioKey IS NOT NULL AND q.AudioKey != ''
             THEN CASE WHEN q.AudioKey LIKE 'http%' THEN q.AudioKey ELSE @BlobBaseUrl + q.AudioKey END
             ELSE NULL
        END AS AudioUrl,
        q.MediaUrl,
        CASE WHEN eq.id IS NULL OR qt.Code = 'freetext' THEN '[]'
             ELSE ISNULL((SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(ISNULL(qo.Value, N''), 'json') + '"', ',') WITHIN GROUP (ORDER BY qo.SortIndex ASC, qo.id ASC) + ']' FROM [OP].[tblQuestionOption] qo WHERE qo.QuestionID = q.id AND qo.ListType IN ('options', 'left')), '[]')
        END AS AnswersJson,
        CASE WHEN eq.id IS NULL THEN '[]'
             ELSE ISNULL((SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(ISNULL(qo.Value, N''), 'json') + '"', ',') WITHIN GROUP (ORDER BY qo.SortIndex ASC, qo.id ASC) + ']' FROM [OP].[tblQuestionOption] qo WHERE qo.QuestionID = q.id AND qo.ListType = 'right'), '[]')
        END AS MatchesJson,
        CASE WHEN eq.id IS NOT NULL AND qt.Code = 'category' THEN
             ISNULL((SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(ISNULL(cat.Value, N''), 'json') + '"', ',') WITHIN GROUP (ORDER BY cat.MinSort ASC) + ']' FROM (SELECT qo.Value, MIN(qo.SortIndex) AS MinSort FROM [OP].[tblQuestionOption] qo WHERE qo.QuestionID = q.id AND qo.ListType = 'right' AND qo.Value IS NOT NULL AND LTRIM(RTRIM(qo.Value)) != '' GROUP BY qo.Value) cat), '[]')
             ELSE '[]'
        END AS CategoriesJson,
        eq.MosaicTipEventUserID,
        eq.MosaicTipTeamID,
        ISNULL((SELECT TOP 1 uTip.Nickname FROM [EJ].[tblEventUser] euTip JOIN [EJ].[tblUser] uTip ON euTip.UserID = uTip.id WHERE euTip.id = eq.MosaicTipEventUserID), N'') AS MosaicTipName,
        ISNULL((SELECT TOP 1 kTip.Name FROM [OP].[tblTeam] tTip JOIN [OP].[tblKabala] kTip ON tTip.KabalaID = kTip.id WHERE tTip.id = eq.MosaicTipTeamID), N'') AS MosaicTipTeam,
        ISNULL((
            SELECT '[' + STRING_AGG(CAST(TeamID AS NVARCHAR(20)), ',') + ']'
            FROM (
                SELECT DISTINCT pOut.TeamID
                FROM [OP].[tblPenalty] pOut
                JOIN [OP].[tblPenaltyType] ptOut ON pOut.PenaltyTypeID = ptOut.id
                WHERE pOut.EventID = @EventID AND ptOut.Code = 'mozaik_wrong' AND pOut.ActiveFlg = 1 AND pOut.TeamID IS NOT NULL
            ) outTeams
        ), '[]') AS MosaicOutTeamIdsJson,
        NULL AS ExtraRunID,
        NULL AS ExtraGameId,
        NULL AS ActiveExtraQuestionID,
        NULL AS ExtraQuestionStatus
    FROM [OP].[tblEventSettings] es
    LEFT JOIN [OP].[tblRound] rActive ON rActive.EventID = @EventID AND rActive.ActiveFlg = 1 AND rActive.RoundStatusID = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active')
    LEFT JOIN [OP].[tblEventQuestion] eq ON eq.id = ISNULL(rActive.FocusedEventQuestionID, (
        SELECT TOP 1 id FROM [OP].[tblEventQuestion] 
        WHERE RoundID = rActive.id AND ActiveFlg = 1 
        ORDER BY CASE WHEN StatusCode = 'active' THEN 0 WHEN StatusCode = 'pending' THEN 1 ELSE 2 END, SortIndex ASC
    ))
    LEFT JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
    LEFT JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
    LEFT JOIN [OP].[tblRoundType] rt ON rActive.RoundTypeID = rt.id
    LEFT JOIN [OP].[tblTopic] topR ON rActive.TopicID = topR.id
    LEFT JOIN [OP].[tblTopic] topQ ON q.TopicID = topQ.id
    WHERE es.EventID = @EventID;

    -- Dataset: DisplayCast (1 sor)
    SELECT 'DisplayCast' AS DatasetName;
    SELECT EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc FROM [OP].[DisplayCast] WHERE EventID = @EventID;

    -- Dataset: OpPenalties
    SELECT 'OpPenalties' AS DatasetName;
    SELECT p.id, p.EventID, p.TeamID, p.Points, p.PenaltyTypeID, pt.Code AS PenaltyTypeCode, p.UndoOfID, p.EventUserID, p.CreatedAtUtc
    FROM [OP].[tblPenalty] p
    LEFT JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
    WHERE p.EventID = @EventID
      AND p.ActiveFlg = 1
      AND ISNULL(pt.Code, '') NOT IN ('mozaik_correct', 'karaoke_pro');
END
GO
