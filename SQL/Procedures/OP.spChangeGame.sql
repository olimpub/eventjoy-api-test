CREATE OR ALTER PROCEDURE [OP].[spChangeGame]
    @Json NVARCHAR(MAX),
    @UserID BIGINT,
    @EventID BIGINT = NULL,
    @Action NVARCHAR(100) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    BEGIN TRY
        DECLARE @Now DATETIMEOFFSET = TODATETIMEOFFSET(SYSUTCDATETIME(), 0);
        DECLARE @NowUtc DATETIME2 = SYSUTCDATETIME();
        IF @EventID IS NULL SET @EventID = JSON_VALUE(@Json, '$.EventID');
        IF @Action IS NULL SET @Action = JSON_VALUE(@Json, '$.Action');

        IF @EventID IS NULL OR @Action IS NULL
        BEGIN
            THROW 50010, N'EventID vagy Action hiányzik a JSON-ből.', 1;
        END

        DECLARE @IsQM BIT = 0;
        DECLARE @IsOrg BIT = 0;
        DECLARE @CallerEventUserID BIGINT = NULL;
        IF @UserID IS NOT NULL
        BEGIN
            SELECT
                @IsOrg = CAST(MAX(CASE WHEN r.RoleTypeID = 1 THEN 1 ELSE 0 END) AS BIT),
                @IsQM = CAST(MAX(CASE WHEN r.id = 7 OR r.RoleTypeID = 2 THEN 1 ELSE 0 END) AS BIT),
                @CallerEventUserID = MAX(eu.id)
            FROM [EJ].[tblEventUser] eu
            LEFT JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
            LEFT JOIN [EJ].[tblRole] r ON er.RoleID = r.id
            WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1;

            SET @IsOrg = ISNULL(@IsOrg, 0);
            SET @IsQM = ISNULL(@IsQM, 0);
        END

        IF @Action NOT IN (N'Op.SubmitAnswer', N'Op.JoinTeam', N'Op.LeaveTeam', N'Op.React', N'Op.MosaicBuzz')
        BEGIN
            IF @IsQM = 0 AND @IsOrg = 0
            BEGIN
                THROW 50030, N'Nincs megfelelő jogosultságod!', 1;
            END
        END

        DECLARE @CurrentStateVersion BIGINT;
        SELECT @CurrentStateVersion = ISNULL(StateVersion, 0) FROM [OP].[tblEventSettings] WHERE EventID = @EventID;
        IF @CurrentStateVersion IS NULL SET @CurrentStateVersion = 0;

        DECLARE @NextStateVersion BIGINT = @CurrentStateVersion + 1;
        DECLARE @BlobBaseUrl NVARCHAR(200) = N'https://eventjoyteststorage.blob.core.windows.net/op-media/' + CAST(@EventID AS NVARCHAR(20)) + N'/';

        DECLARE @SignalRTargets TABLE (TargetGroup NVARCHAR(100), EventName NVARCHAR(50), CustomPayload NVARCHAR(MAX));
        DECLARE @OutPing NVARCHAR(MAX) = NULL;
        DECLARE @CardEQID INT = NULL;

        BEGIN TRANSACTION;

        IF @Action = N'Op.SetPlayerFace'
        BEGIN
            DECLARE @PF_Face NVARCHAR(50) = ISNULL(JSON_VALUE(@Json, '$.Payload.Face'), '');
            UPDATE [OP].[tblEventSettings]
            SET PlayerFace = @PF_Face, UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @PF_Face AS Face,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @PF_Face AS Face, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.SetCurrent'
        BEGIN
            DECLARE @Current BIT = JSON_VALUE(@Json, '$.Payload.Current');
            IF @Current = 1
            BEGIN
                UPDATE [OP].[tblEventSettings] SET CurrentFlg = 0;
                UPDATE [OP].[tblEventSettings] SET CurrentFlg = 1, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                UPDATE [OP].[tblEventSettings] SET CurrentFlg = 0, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            END

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @Current AS [Current],
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @Current AS [Current], @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.ShowLobby'
        BEGIN
            DECLARE @LobbyTeamsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.Payload.Teams');
            IF @LobbyTeamsJson IS NULL
            BEGIN
                SET @LobbyTeamsJson = ISNULL((
                    SELECT
                        t.id AS TeamID,
                        t.id AS id,
                        t.KabalaID,
                        k.Name,
                        (SELECT COUNT(*) FROM [OP].[tblTeamMember] tmC WHERE tmC.TeamID = t.id AND tmC.ActiveFlg = 1) AS MemberCount,
                        ISNULL((
                            SELECT
                                tm.EventUserID,
                                u.Nickname,
                                CAST(CASE WHEN tm.LastSeenUtc IS NOT NULL AND tm.LastSeenUtc >= DATEADD(MINUTE, -3, @NowUtc) THEN 1 ELSE 0 END AS BIT) AS Online
                            FROM [OP].[tblTeamMember] tm
                            JOIN [EJ].[tblEventUser] eu ON tm.EventUserID = eu.id
                            JOIN [EJ].[tblUser] u ON eu.UserID = u.id
                            WHERE tm.TeamID = t.id AND tm.ActiveFlg = 1
                            FOR JSON PATH
                        ), '[]') AS Members
                    FROM [OP].[tblTeam] t
                    JOIN [OP].[tblKabala] k ON t.KabalaID = k.id
                    WHERE t.EventID = @EventID AND t.ActiveFlg = 1
                    FOR JSON PATH
                ), '[]');
            END

            DECLARE @LobbyScreenJson NVARCHAR(MAX) = (
                SELECT
                    'lobby' AS Screen,
                    'lobby' AS Face,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@LobbyTeamsJson) AS Teams
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE [OP].[tblEventSettings]
            SET Screen = 'lobby', ScreenJson = @LobbyScreenJson, UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
                UPDATE [OP].[DisplayCast] SET Face = 'lobby', PayloadJson = @LobbyScreenJson, StateVersion = @NextStateVersion, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            ELSE
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, 'lobby', @LobbyScreenJson, @NextStateVersion, @Now);

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    'lobby' AS Screen,
                    'lobby' AS Face,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@LobbyTeamsJson) AS Teams,
                    JSON_QUERY(@LobbyScreenJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.ShowTopics'
        BEGIN
            DECLARE @ST_Kind NVARCHAR(32) = ISNULL(JSON_VALUE(@Json, '$.Payload.Kind'), 'quiz');
            DECLARE @ST_TopicsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.Payload.Topics');
            IF @ST_TopicsJson IS NULL
            BEGIN
                SET @ST_TopicsJson = ISNULL((
                    SELECT
                        r.id AS RoundID,
                        r.TopicID,
                        COALESCE(topR.Name, rt.Name, N'') AS Title,
                        COALESCE(topR.Name, rt.Name, N'') AS Name,
                        rs.Code AS StatusCode,
                        r.SortIndex
                    FROM [OP].[tblRound] r
                    JOIN [OP].[tblRoundStatus] rs ON r.RoundStatusID = rs.id
                    JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
                    LEFT JOIN [OP].[tblTopic] topR ON r.TopicID = topR.id
                    WHERE r.EventID = @EventID AND r.ActiveFlg = 1
                    ORDER BY r.SortIndex ASC
                    FOR JSON PATH
                ), '[]');
            END

            DECLARE @TopicsScreenJson NVARCHAR(MAX) = (
                SELECT
                    'topics' AS Screen,
                    'topics' AS Face,
                    @ST_Kind AS Kind,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@ST_TopicsJson) AS Topics
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE [OP].[tblEventSettings]
            SET Screen = 'topics', ScreenJson = @TopicsScreenJson, UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
                UPDATE [OP].[DisplayCast] SET Face = 'topics', PayloadJson = @TopicsScreenJson, StateVersion = @NextStateVersion, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            ELSE
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, 'topics', @TopicsScreenJson, @NextStateVersion, @Now);

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    'topics' AS Screen,
                    'topics' AS Face,
                    @ST_Kind AS Kind,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@ST_TopicsJson) AS Topics,
                    JSON_QUERY(@TopicsScreenJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.ShowDraw'
        BEGIN
            DECLARE @SD_Kind NVARCHAR(32) = ISNULL(JSON_VALUE(@Json, '$.Payload.Kind'), 'quiz');
            DECLARE @SD_TopicsJson NVARCHAR(MAX) = ISNULL(JSON_QUERY(@Json, '$.Payload.Topics'), '[]');
            DECLARE @SD_WinnerRoundID INT = JSON_VALUE(@Json, '$.Payload.WinnerRoundID');
            DECLARE @SD_WinnerTitle NVARCHAR(200) = JSON_VALUE(@Json, '$.Payload.WinnerTitle');

            DECLARE @DrawScreenJson NVARCHAR(MAX) = (
                SELECT
                    'draw' AS Screen,
                    'draw' AS Face,
                    @SD_Kind AS Kind,
                    @SD_WinnerRoundID AS WinnerRoundID,
                    @SD_WinnerTitle AS WinnerTitle,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@SD_TopicsJson) AS Topics
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE [OP].[tblEventSettings]
            SET Screen = 'draw', ScreenJson = @DrawScreenJson, UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
                UPDATE [OP].[DisplayCast] SET Face = 'draw', PayloadJson = @DrawScreenJson, StateVersion = @NextStateVersion, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            ELSE
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, 'draw', @DrawScreenJson, @NextStateVersion, @Now);

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    'draw' AS Screen,
                    'draw' AS Face,
                    @SD_Kind AS Kind,
                    @SD_WinnerRoundID AS WinnerRoundID,
                    @SD_WinnerTitle AS WinnerTitle,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@SD_TopicsJson) AS Topics,
                    JSON_QUERY(@DrawScreenJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.CastDisplay'
        BEGIN
            DECLARE @Face NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Face');
            DECLARE @PayloadJsonObj NVARCHAR(MAX) = ISNULL(JSON_QUERY(@Json, '$.Payload'), @Json);

            DECLARE @CD_ClockPhase NVARCHAR(32) = COALESCE(JSON_VALUE(@PayloadJsonObj, '$.ClockPhase'), JSON_VALUE(@PayloadJsonObj, '$.clockPhase'));
            DECLARE @CD_ClockHold BIT = CAST(COALESCE(
                JSON_VALUE(@PayloadJsonObj, '$.ClockHold'),
                JSON_VALUE(@PayloadJsonObj, '$.clockHold'),
                JSON_VALUE(@PayloadJsonObj, '$.Hold'),
                JSON_VALUE(@PayloadJsonObj, '$.hold')
            ) AS BIT);
            DECLARE @CD_ClockLeftMs INT = COALESCE(
                TRY_CAST(JSON_VALUE(@PayloadJsonObj, '$.ClockLeftMs') AS INT),
                TRY_CAST(JSON_VALUE(@PayloadJsonObj, '$.clockLeftMs') AS INT),
                TRY_CAST(JSON_VALUE(@PayloadJsonObj, '$.LeftMs') AS INT),
                TRY_CAST(JSON_VALUE(@PayloadJsonObj, '$.leftMs') AS INT)
            );
            DECLARE @CD_ClockTotalMs INT = COALESCE(
                TRY_CAST(JSON_VALUE(@PayloadJsonObj, '$.ClockTotalMs') AS INT),
                TRY_CAST(JSON_VALUE(@PayloadJsonObj, '$.clockTotalMs') AS INT)
            );
            DECLARE @CD_TipName NVARCHAR(100) = COALESCE(JSON_VALUE(@PayloadJsonObj, '$.TipName'), JSON_VALUE(@PayloadJsonObj, '$.tipName'));
            DECLARE @CD_TipTeam NVARCHAR(100) = COALESCE(JSON_VALUE(@PayloadJsonObj, '$.TipTeam'), JSON_VALUE(@PayloadJsonObj, '$.tipTeam'));
            DECLARE @CD_MosaicBlocked BIT = CAST(COALESCE(
                JSON_VALUE(@PayloadJsonObj, '$.MosaicBlocked'),
                JSON_VALUE(@PayloadJsonObj, '$.mosaicBlocked'),
                JSON_VALUE(@PayloadJsonObj, '$.Blocked')
            ) AS BIT);
            DECLARE @CD_MosaicOutTeamIds NVARCHAR(MAX) = COALESCE(
                JSON_QUERY(@PayloadJsonObj, '$.MosaicOutTeamIds'),
                JSON_QUERY(@PayloadJsonObj, '$.mosaicOutTeamIds')
            );

            IF @CD_ClockLeftMs IS NOT NULL
            BEGIN
                UPDATE eq
                SET eq.ClockLeftMs = @CD_ClockLeftMs
                FROM [OP].[tblEventQuestion] eq
                JOIN [OP].[tblRound] r ON eq.RoundID = r.id
                JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
                WHERE r.EventID = @EventID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1 AND rt.Code = 'manual_display';
            END

            IF @Face = 'results'
            BEGIN
                DECLARE @CD_Board NVARCHAR(50) = ISNULL(JSON_VALUE(@Json, '$.Payload.Board'), 'main');
                DECLARE @CD_RoundID INT = COALESCE(
                    CAST(JSON_VALUE(@Json, '$.Payload.RoundID') AS INT),
                    CAST(JSON_VALUE(@Json, '$.Payload.RoundId') AS INT),
                    CAST(JSON_VALUE(@Json, '$.Payload.roundId') AS INT)
                );
                DECLARE @CD_ExtraGameId NVARCHAR(100) = COALESCE(
                    JSON_VALUE(@Json, '$.Payload.ExtraGameId'),
                    JSON_VALUE(@Json, '$.Payload.extraGameId'),
                    JSON_VALUE(@Json, '$.Payload.ExtraGameID')
                );
                DECLARE @CD_BoardKey NVARCHAR(100) = @CD_Board
                    + CASE WHEN @CD_RoundID IS NOT NULL THEN N':r' + CAST(@CD_RoundID AS NVARCHAR(20)) ELSE N'' END
                    + CASE WHEN @CD_ExtraGameId IS NOT NULL AND LTRIM(RTRIM(@CD_ExtraGameId)) != N'' THEN N':e' + LOWER(LTRIM(RTRIM(@CD_ExtraGameId))) ELSE N'' END;

                CREATE TABLE #TempBoardCD (TeamID BIGINT, Name NVARCHAR(200), Points DECIMAL(12,4), PreviousPoints DECIMAL(12,4), Place BIGINT);
                INSERT INTO #TempBoardCD EXEC [OP].[spGetLeaderboard] @EventID = @EventID, @Board = @CD_Board, @UserID = @UserID, @RoundID = @CD_RoundID, @ExtraGameId = @CD_ExtraGameId;

                MERGE INTO [OP].[tblDisplayBoard] AS target
                USING #TempBoardCD AS source
                ON target.EventID = @EventID AND target.Board = @CD_BoardKey AND target.TeamID = source.TeamID
                WHEN MATCHED AND target.DisplayedPoints != source.Points THEN
                    UPDATE SET PreviousPoints = target.DisplayedPoints, DisplayedPoints = source.Points
                WHEN NOT MATCHED THEN
                    INSERT (EventID, Board, TeamID, DisplayedPoints, PreviousPoints, ActiveFlg)
                    VALUES (@EventID, @CD_BoardKey, source.TeamID, source.Points, 0, 1);

                DROP TABLE #TempBoardCD;
            END

            IF @Face IN ('lobby', 'topics', 'draw', 'results', 'idle', 'join')
            BEGIN
                UPDATE [OP].[tblEventSettings]
                SET Screen = @Face, ScreenJson = @PayloadJsonObj, UpdatedAtUtc = @Now
                WHERE EventID = @EventID;
            END

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
            BEGIN
                UPDATE [OP].[DisplayCast] SET Face = @Face, PayloadJson = @PayloadJsonObj, StateVersion = @NextStateVersion, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, @Face, @PayloadJsonObj, @NextStateVersion, @Now);
            END

            DECLARE @CD_InnerPayload NVARCHAR(MAX) = (
                SELECT
                    @Face AS Face,
                    @Face AS Screen,
                    @NextStateVersion AS StateVersion,
                    @CD_ClockPhase AS ClockPhase,
                    @CD_ClockHold AS ClockHold,
                    @CD_ClockHold AS Hold,
                    @CD_ClockLeftMs AS ClockLeftMs,
                    @CD_ClockLeftMs AS LeftMs,
                    @CD_ClockTotalMs AS ClockTotalMs,
                    @CD_TipName AS TipName,
                    @CD_TipTeam AS TipTeam,
                    @CD_MosaicBlocked AS MosaicBlocked,
                    JSON_QUERY(@CD_MosaicOutTeamIds) AS MosaicOutTeamIds
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @Face AS Face,
                    @Face AS Screen,
                    @NextStateVersion AS StateVersion,
                    @CD_ClockPhase AS ClockPhase,
                    @CD_ClockHold AS ClockHold,
                    @CD_ClockHold AS Hold,
                    @CD_ClockLeftMs AS ClockLeftMs,
                    @CD_ClockLeftMs AS LeftMs,
                    @CD_ClockTotalMs AS ClockTotalMs,
                    @CD_TipName AS TipName,
                    @CD_TipTeam AS TipTeam,
                    @CD_MosaicBlocked AS MosaicBlocked,
                    JSON_QUERY(@CD_MosaicOutTeamIds) AS MosaicOutTeamIds,
                    JSON_QUERY(@CD_InnerPayload) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.ShowLeaderboard'
        BEGIN
            DECLARE @Board NVARCHAR(50) = ISNULL(JSON_VALUE(@Json, '$.Payload.Board'), 'main');
            DECLARE @Lbd_RoundID INT = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.RoundID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.RoundId') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.roundId') AS INT)
            );
            DECLARE @Lbd_ExtraGameId NVARCHAR(100) = COALESCE(
                JSON_VALUE(@Json, '$.Payload.ExtraGameId'),
                JSON_VALUE(@Json, '$.Payload.extraGameId'),
                JSON_VALUE(@Json, '$.Payload.ExtraGameID')
            );
            DECLARE @Lbd_BoardKey NVARCHAR(100) = @Board
                + CASE WHEN @Lbd_RoundID IS NOT NULL THEN N':r' + CAST(@Lbd_RoundID AS NVARCHAR(20)) ELSE N'' END
                + CASE WHEN @Lbd_ExtraGameId IS NOT NULL AND LTRIM(RTRIM(@Lbd_ExtraGameId)) != N'' THEN N':e' + LOWER(LTRIM(RTRIM(@Lbd_ExtraGameId))) ELSE N'' END;

            CREATE TABLE #TempBoard (TeamID BIGINT, Name NVARCHAR(200), Points DECIMAL(12,4), PreviousPoints DECIMAL(12,4), Place BIGINT);
            INSERT INTO #TempBoard EXEC [OP].[spGetLeaderboard] @EventID = @EventID, @Board = @Board, @UserID = @UserID, @RoundID = @Lbd_RoundID, @ExtraGameId = @Lbd_ExtraGameId;

            MERGE INTO [OP].[tblDisplayBoard] AS target
            USING #TempBoard AS source
            ON target.EventID = @EventID AND target.Board = @Lbd_BoardKey AND target.TeamID = source.TeamID
            WHEN MATCHED AND target.DisplayedPoints != source.Points THEN
                UPDATE SET PreviousPoints = target.DisplayedPoints, DisplayedPoints = source.Points
            WHEN NOT MATCHED THEN
                INSERT (EventID, Board, TeamID, DisplayedPoints, PreviousPoints, ActiveFlg)
                VALUES (@EventID, @Lbd_BoardKey, source.TeamID, source.Points, 0, 1);

            DROP TABLE #TempBoard;

            DECLARE @LbdScreenJson NVARCHAR(MAX) = (
                SELECT
                    'results' AS Screen,
                    'results' AS Face,
                    @Board AS Board,
                    @Lbd_RoundID AS RoundID,
                    @Lbd_RoundID AS RoundId,
                    @Lbd_ExtraGameId AS ExtraGameId,
                    @NextStateVersion AS StateVersion
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            UPDATE [OP].[tblEventSettings]
            SET Screen = 'results', ScreenJson = @LbdScreenJson, UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
                UPDATE [OP].[DisplayCast] SET Face = 'results', PayloadJson = @LbdScreenJson, StateVersion = @NextStateVersion, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            ELSE
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, 'results', @LbdScreenJson, @NextStateVersion, @Now);

            SET @OutPing = (
                SELECT
                    @EventID AS EventID,
                    @Action AS Action,
                    'leaderboard' AS State,
                    'results' AS Screen,
                    @Board AS Board,
                    @Lbd_RoundID AS RoundID,
                    @Lbd_RoundID AS RoundId,
                    @Lbd_ExtraGameId AS ExtraGameId,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@LbdScreenJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.StartRound'
        BEGIN
            DECLARE @SR_RoundID INT = COALESCE(JSON_VALUE(@Json, '$.Payload.RoundID'), JSON_VALUE(@Json, '$.Payload.RoundId'));
            DECLARE @ActiveStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active');

            IF EXISTS (SELECT 1 FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID = @ActiveStatusID AND ActiveFlg = 1 AND id != @SR_RoundID)
            BEGIN
                THROW 50031, N'Már van aktív forduló!', 1;
            END

            UPDATE [OP].[tblRound] SET RoundStatusID = @ActiveStatusID, FocusedEventQuestionID = NULL WHERE id = @SR_RoundID AND EventID = @EventID;

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @SR_RoundID AS RoundID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @SR_RoundID AS RoundID, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action IN (N'Op.StartQuestion', N'Op.StartExtraQuestion')
        BEGIN
            SET @CardEQID = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionId') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionID') AS INT)
            );

            DECLARE @SQ_StartRoundType VARCHAR(50), @SQ_QuestionType VARCHAR(50);
            SELECT @SQ_StartRoundType = rt.Code, @SQ_QuestionType = qt.Code
            FROM [OP].[tblEventQuestion] eq
            JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
            JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id
            JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
            WHERE eq.id = @CardEQID;

            DECLARE @SQ_InitPaused BIT = CASE WHEN @SQ_QuestionType = 'no_options' OR ISNULL(@SQ_StartRoundType, 'main_quiz') = 'main_quiz' THEN 1 ELSE 0 END;
            DECLARE @SQ_InitAnswerUtc DATETIME2 = CASE WHEN @SQ_InitPaused = 0 THEN @NowUtc ELSE NULL END;

            UPDATE p
            SET p.ActiveFlg = 0
            FROM [OP].[tblPenalty] p
            JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
            WHERE p.EventID = @EventID AND pt.Code = 'mozaik_wrong' AND p.ActiveFlg = 1;

            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'active',
                StartedAtUtc = @Now,
                AnswerStartedAtUtc = @SQ_InitAnswerUtc,
                StoppedAtUtc = NULL,
                ClockPaused = @SQ_InitPaused,
                ClockLeftMs = (TimeSec * 1000),
                MosaicTipEventUserID = NULL,
                MosaicTipTeamID = NULL
            WHERE id = @CardEQID AND EventID = @EventID;

            UPDATE [OP].[tblRound]
            SET FocusedEventQuestionID = @CardEQID
            WHERE id = (SELECT RoundID FROM [OP].[tblEventQuestion] WHERE id = @CardEQID) AND EventID = @EventID;

            UPDATE [OP].[tblEventSettings]
            SET AnswerStartedAtUtc = @SQ_InitAnswerUtc,
                Screen = 'question',
                UpdatedAtUtc = @Now
            WHERE EventID = @EventID;
        END
        ELSE IF @Action = N'Op.NextQuestion'
        BEGIN
            DECLARE @NQ_RoundID INT = COALESCE(JSON_VALUE(@Json, '$.Payload.RoundID'), JSON_VALUE(@Json, '$.Payload.RoundId'));

            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @NQ_RoundID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50036, N'Előbb állítsd meg az aktuális kérdést!', 1;
            END

            SET @CardEQID = (SELECT TOP 1 id FROM [OP].[tblEventQuestion] WHERE RoundID = @NQ_RoundID AND StatusCode = 'pending' AND ActiveFlg = 1 ORDER BY SortIndex ASC);

            IF @CardEQID IS NOT NULL
            BEGIN
                DECLARE @NQ_RoundType VARCHAR(50), @NQ_QuestionType VARCHAR(50);
                SELECT @NQ_RoundType = rt.Code, @NQ_QuestionType = qt.Code
                FROM [OP].[tblEventQuestion] eq
                JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
                JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
                JOIN [OP].[tblRound] r ON eq.RoundID = r.id
                JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
                WHERE eq.id = @CardEQID;

                DECLARE @NQ_InitPaused BIT = CASE WHEN @NQ_QuestionType = 'no_options' OR ISNULL(@NQ_RoundType, 'main_quiz') = 'main_quiz' THEN 1 ELSE 0 END;
                DECLARE @NQ_InitAnswerUtc DATETIME2 = CASE WHEN @NQ_InitPaused = 0 THEN @NowUtc ELSE NULL END;

                UPDATE p
                SET p.ActiveFlg = 0
                FROM [OP].[tblPenalty] p
                JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
                WHERE p.EventID = @EventID AND pt.Code = 'mozaik_wrong' AND p.ActiveFlg = 1;

                UPDATE [OP].[tblEventQuestion]
                SET StatusCode = 'active',
                    StartedAtUtc = @Now,
                    AnswerStartedAtUtc = @NQ_InitAnswerUtc,
                    StoppedAtUtc = NULL,
                    ClockPaused = @NQ_InitPaused,
                    ClockLeftMs = (TimeSec * 1000),
                    MosaicTipEventUserID = NULL,
                    MosaicTipTeamID = NULL
                WHERE id = @CardEQID AND EventID = @EventID;

                UPDATE [OP].[tblRound]
                SET FocusedEventQuestionID = @CardEQID
                WHERE id = @NQ_RoundID AND EventID = @EventID;

                UPDATE [OP].[tblEventSettings]
                SET AnswerStartedAtUtc = @NQ_InitAnswerUtc,
                    Screen = 'question',
                    UpdatedAtUtc = @Now
                WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                THROW 50037, N'A kérdéskör véget ért.', 1;
            END
        END
        ELSE IF @Action = N'Op.ReopenQuestion'
        BEGIN
            SET @CardEQID = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionID') AS INT)
            );
            DELETE FROM [OP].[tblAnswerItem] WHERE AnswerID IN (SELECT id FROM [OP].[tblAnswer] WHERE EventQuestionID = @CardEQID);
            DELETE FROM [OP].[tblAnswer] WHERE EventQuestionID = @CardEQID;
            DELETE FROM [OP].[tblQuestionScore] WHERE EventQuestionID = @CardEQID;
            DELETE FROM [OP].[tblShadowScore] WHERE EventQuestionID = @CardEQID;

            DECLARE @RQ_RoundType VARCHAR(50), @RQ_QuestionType VARCHAR(50);
            SELECT @RQ_RoundType = rt.Code, @RQ_QuestionType = qt.Code
            FROM [OP].[tblEventQuestion] eq
            JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
            JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id
            JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
            WHERE eq.id = @CardEQID;

            DECLARE @RQ_InitPaused BIT = CASE WHEN @RQ_QuestionType = 'no_options' OR ISNULL(@RQ_RoundType, 'main_quiz') = 'main_quiz' THEN 1 ELSE 0 END;
            DECLARE @RQ_InitAnswerUtc DATETIME2 = CASE WHEN @RQ_InitPaused = 0 THEN @NowUtc ELSE NULL END;

            UPDATE p
            SET p.ActiveFlg = 0
            FROM [OP].[tblPenalty] p
            JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
            WHERE p.EventID = @EventID AND pt.Code = 'mozaik_wrong' AND p.ActiveFlg = 1;

            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'active',
                StartedAtUtc = @Now,
                AnswerStartedAtUtc = @RQ_InitAnswerUtc,
                StoppedAtUtc = NULL,
                ClockPaused = @RQ_InitPaused,
                ClockLeftMs = (TimeSec * 1000),
                MosaicTipEventUserID = NULL,
                MosaicTipTeamID = NULL
            WHERE id = @CardEQID AND EventID = @EventID;

            UPDATE [OP].[tblRound]
            SET FocusedEventQuestionID = @CardEQID
            WHERE id = (SELECT RoundID FROM [OP].[tblEventQuestion] WHERE id = @CardEQID) AND EventID = @EventID;

            UPDATE [OP].[tblEventSettings]
            SET AnswerStartedAtUtc = @RQ_InitAnswerUtc,
                Screen = 'question',
                UpdatedAtUtc = @Now
            WHERE EventID = @EventID;
        END
        ELSE IF @Action = N'Op.StartClock'
        BEGIN
            DECLARE @SC_EventQuestionID INT = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionId') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionID') AS INT)
            );
            IF @SC_EventQuestionID IS NULL
            BEGIN
                SELECT TOP 1 @SC_EventQuestionID = eq.id
                FROM [OP].[tblEventQuestion] eq
                WHERE eq.EventID = @EventID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1
                ORDER BY eq.StartedAtUtc DESC, eq.id DESC;
            END

            -- §5.3: AnswerStartedAtUtc = most, ClockPaused = 0, StateVersion++
            UPDATE [OP].[tblEventQuestion]
            SET AnswerStartedAtUtc = @NowUtc,
                ClockPaused = 0,
                ClockLeftMs = NULL
            WHERE id = @SC_EventQuestionID AND EventID = @EventID;

            UPDATE [OP].[tblEventSettings]
            SET AnswerStartedAtUtc = @NowUtc,
                Screen = 'question',
                UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            DECLARE @SC_TimeSec INT, @SC_RoundID INT, @SC_StartedAt DATETIMEOFFSET;
            SELECT @SC_TimeSec = TimeSec, @SC_RoundID = RoundID, @SC_StartedAt = TODATETIMEOFFSET(StartedAtUtc, 0)
            FROM [OP].[tblEventQuestion]
            WHERE id = @SC_EventQuestionID;

            DECLARE @SC_InnerJson NVARCHAR(MAX) = (
                SELECT
                    @SC_EventQuestionID AS EventQuestionID,
                    @SC_EventQuestionID AS ActiveEventQuestionID,
                    @SC_RoundID AS RoundID,
                    'question' AS Screen,
                    'active' AS QuestionStatus,
                    @SC_StartedAt AS StartedAtUtc,
                    @Now AS AnswerStartedAtUtc,
                    @SC_TimeSec AS TimeSec,
                    CAST(0 AS BIT) AS ClockPaused,
                    CAST(0 AS BIT) AS Hold,
                    @NextStateVersion AS StateVersion
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @SC_EventQuestionID AS EventQuestionID,
                    @SC_EventQuestionID AS ActiveEventQuestionID,
                    @SC_RoundID AS RoundID,
                    'question' AS Screen,
                    'active' AS QuestionStatus,
                    @SC_StartedAt AS StartedAtUtc,
                    @Now AS AnswerStartedAtUtc,
                    @SC_TimeSec AS TimeSec,
                    CAST(0 AS BIT) AS ClockPaused,
                    CAST(0 AS BIT) AS Hold,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@SC_InnerJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action IN (N'Op.PauseClock', N'Op.PauseQuestion')
        BEGIN
            DECLARE @PQ_EQID INT = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionId') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionId') AS INT)
            );
            IF @PQ_EQID IS NULL
            BEGIN
                SELECT TOP 1 @PQ_EQID = id FROM [OP].[tblEventQuestion] WHERE EventID = @EventID AND StatusCode = 'active' AND ActiveFlg = 1 ORDER BY id DESC;
            END

            DECLARE @PQ_Hold BIT = ISNULL(CAST(JSON_VALUE(@Json, '$.Payload.Hold') AS BIT), 1);
            DECLARE @PQ_LeftMs INT = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.ClockLeftMs') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.LeftMs') AS INT)
            );

            IF NOT EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @PQ_EQID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50030, N'A kérdés nem aktív.', 1;
            END

            DECLARE @PQ_AnswerStartedAt DATETIMEOFFSET;

            IF @PQ_Hold = 1
            BEGIN
                UPDATE [OP].[tblEventQuestion]
                SET ClockPaused = 1, ClockLeftMs = @PQ_LeftMs
                WHERE id = @PQ_EQID AND EventID = @EventID;

                SELECT @PQ_AnswerStartedAt = TODATETIMEOFFSET(AnswerStartedAtUtc, 0) FROM [OP].[tblEventQuestion] WHERE id = @PQ_EQID;
            END
            ELSE
            BEGIN
                DECLARE @PQ_TimeSec INT = (SELECT TimeSec FROM [OP].[tblEventQuestion] WHERE id = @PQ_EQID);
                DECLARE @PQ_ElapsedMs INT = (@PQ_TimeSec * 1000) - ISNULL(@PQ_LeftMs, 0);
                DECLARE @PQ_NewAnswerStartedUtc DATETIME2 = DATEADD(MILLISECOND, -@PQ_ElapsedMs, @NowUtc);
                SET @PQ_AnswerStartedAt = TODATETIMEOFFSET(@PQ_NewAnswerStartedUtc, 0);

                UPDATE [OP].[tblEventQuestion]
                SET ClockPaused = 0, ClockLeftMs = NULL, AnswerStartedAtUtc = @PQ_NewAnswerStartedUtc
                WHERE id = @PQ_EQID AND EventID = @EventID;

                UPDATE [OP].[tblEventSettings]
                SET AnswerStartedAtUtc = @PQ_NewAnswerStartedUtc, UpdatedAtUtc = @Now
                WHERE EventID = @EventID;
            END

            DECLARE @PQ_InnerJson NVARCHAR(MAX) = (
                SELECT
                    @PQ_EQID AS EventQuestionID,
                    @PQ_Hold AS Hold,
                    @PQ_Hold AS ClockPaused,
                    @PQ_LeftMs AS LeftMs,
                    @PQ_LeftMs AS ClockLeftMs,
                    @PQ_AnswerStartedAt AS AnswerStartedAtUtc,
                    @NextStateVersion AS StateVersion
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @PQ_EQID AS EventQuestionID,
                    @PQ_Hold AS Hold,
                    @PQ_Hold AS ClockPaused,
                    @PQ_LeftMs AS LeftMs,
                    @PQ_LeftMs AS ClockLeftMs,
                    @PQ_AnswerStartedAt AS AnswerStartedAtUtc,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@PQ_InnerJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action IN (N'Op.StopQuestion', N'Op.StopExtraQuestion')
        BEGIN
            DECLARE @StopEventQuestionID INT = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionId') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionID') AS INT)
            );
            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'stopped',
                StoppedAtUtc = @Now,
                ClockPaused = 0,
                ClockLeftMs = 0,
                MosaicTipEventUserID = NULL,
                MosaicTipTeamID = NULL
            WHERE id = @StopEventQuestionID AND EventID = @EventID;

            UPDATE p
            SET p.ActiveFlg = 0
            FROM [OP].[tblPenalty] p
            JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
            WHERE p.EventID = @EventID AND pt.Code = 'mozaik_wrong' AND p.ActiveFlg = 1;

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID AND ISJSON(PayloadJson) = 1)
            BEGIN
                UPDATE [OP].[DisplayCast]
                SET PayloadJson = JSON_MODIFY(
                        JSON_MODIFY(
                            JSON_MODIFY(
                                JSON_MODIFY(
                                    JSON_MODIFY(PayloadJson, '$.TipName', N''),
                                    '$.TipTeam', N''
                                ),
                                '$.ClockPhase', N'done'
                            ),
                            '$.ClockHold', CAST(0 AS BIT)
                        ),
                        '$.MosaicOutTeamIds', JSON_QUERY('[]')
                    ),
                    StateVersion = @NextStateVersion,
                    UpdatedAtUtc = @Now
                WHERE EventID = @EventID AND ISJSON(PayloadJson) = 1;
            END

            DECLARE @TimeSec INT, @StartedAtUtc DATETIMEOFFSET, @TypeCode NVARCHAR(16), @SQ_RoundID INT, @RawsMode VARCHAR(20), @FGivenMode VARCHAR(20), @FPointMode VARCHAR(20), @RoundTypeID INT;

            SELECT @TimeSec = eq.TimeSec, @StartedAtUtc = eq.StartedAtUtc, @TypeCode = qt.Code, @SQ_RoundID = r.id,
                   @RawsMode = rt.RawsMode, @FGivenMode = rt.FGivenMode, @FPointMode = rt.FPointMode, @RoundTypeID = rt.id
            FROM [OP].[tblEventQuestion] eq
            JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
            JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id
            JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
            WHERE eq.id = @StopEventQuestionID;

            SELECT a.EventUserID, tm.TeamID, a.id AS AnswerID, a.ReceivedAtUtc, ISNULL(a.Ratio, 0.0) AS Ratio, ISNULL(a.ElapsedMs, 0) AS ElapsedMs, ISNULL(a.CorrectFlg, 0) AS CorrectFlg
            INTO #LatestAnswers
            FROM (SELECT EventUserID, MAX(id) AS id FROM [OP].[tblAnswer] WHERE EventQuestionID = @StopEventQuestionID AND ActiveFlg = 1 GROUP BY EventUserID) latest
            JOIN [OP].[tblAnswer] a ON latest.id = a.id
            LEFT JOIN [OP].[tblTeamMember] tm ON a.EventUserID = tm.EventUserID AND tm.ActiveFlg = 1;

            IF @TypeCode != 'no_options' AND @RawsMode = 'team'
            BEGIN
                DECLARE @P_alap DECIMAL(12,4) = CASE @TypeCode WHEN 'single' THEN 80 WHEN 'multi' THEN 90 WHEN 'order' THEN 100 WHEN 'match' THEN 100 WHEN 'category' THEN 110 WHEN 'freetext' THEN 120 ELSE 80 END;

                DELETE FROM [OP].[tblShadowScore] WHERE EventQuestionID = @StopEventQuestionID;
                INSERT INTO [OP].[tblShadowScore] (EventQuestionID, EventUserID, S)
                SELECT @StopEventQuestionID, EventUserID,
                    @P_alap * Ratio * (1.0 + 0.3 * (
                        CASE WHEN ElapsedMs > (@TimeSec * 1000.0) THEN 0
                             WHEN ElapsedMs < 0 THEN 1.0
                             ELSE CAST((@TimeSec * 1000.0) - ElapsedMs AS DECIMAL(10,4)) / (@TimeSec * 1000.0)
                        END))
                FROM #LatestAnswers;

                SELECT TeamID, SUM(CASE WHEN Ratio = 1.0 THEN 1 ELSE 0 END) AS C, SUM(CASE WHEN Ratio = 0.0 THEN 1 ELSE 0 END) AS W, MIN(CASE WHEN Ratio = 1.0 THEN (ElapsedMs / 1000.0) ELSE NULL END) AS FastestCorrectSec
                INTO #TeamStats
                FROM #LatestAnswers
                WHERE TeamID IS NOT NULL
                GROUP BY TeamID;

                DELETE FROM [OP].[tblQuestionScore] WHERE EventQuestionID = @StopEventQuestionID;
                INSERT INTO [OP].[tblQuestionScore] (EventQuestionID, TeamID, RawS, C, W, SpeedT)
                SELECT @StopEventQuestionID, t.id,
                    CASE WHEN ISNULL(ts.C, 0) = 0 THEN 0.0
                    ELSE @P_alap
                        * (1.0 + 0.3 * (
                             CASE WHEN ts.FastestCorrectSec IS NULL THEN 0
                                  WHEN ts.FastestCorrectSec > @TimeSec THEN 0
                                  WHEN ts.FastestCorrectSec < 0 THEN 1.0
                                  ELSE CAST(@TimeSec - ts.FastestCorrectSec AS DECIMAL(10,4)) / @TimeSec
                             END))
                        * (1.0 + 0.5 * (CAST(ts.C AS DECIMAL(10,4)) / (ts.C + ts.W)))
                    END,
                    ISNULL(ts.C, 0), ISNULL(ts.W, 0), ISNULL(ts.FastestCorrectSec, 999.0)
                FROM [OP].[tblTeam] t
                LEFT JOIN #TeamStats ts ON t.id = ts.TeamID
                WHERE t.EventID = @EventID AND t.ActiveFlg = 1;
            END
            ELSE IF @TypeCode != 'no_options' AND @RawsMode = 'fastest'
            BEGIN
                SELECT
                    TeamID,
                    MIN(ElapsedMs) AS MinElapsedMs,
                    MAX(Ratio * (100000.0 - CASE WHEN ElapsedMs > 99999 THEN 99999 WHEN ElapsedMs < 0 THEN 0 ELSE ElapsedMs END)) AS BestRawS
                INTO #FastestTeams
                FROM #LatestAnswers
                WHERE TeamID IS NOT NULL AND Ratio > 0
                GROUP BY TeamID;

                DELETE FROM [OP].[tblQuestionScore] WHERE EventQuestionID = @StopEventQuestionID;
                INSERT INTO [OP].[tblQuestionScore] (EventQuestionID, TeamID, RawS, C, W, SpeedT)
                SELECT @StopEventQuestionID, TeamID, BestRawS, 1, 0, (MinElapsedMs / 1000.0)
                FROM #FastestTeams;
            END

            IF @TypeCode != 'no_options' AND @FGivenMode = 'after_question' AND @FPointMode = 'fixed'
            BEGIN
                SELECT TeamID, RawS, ROW_NUMBER() OVER (ORDER BY RawS DESC) AS Rnk
                INTO #QuestionWinners
                FROM [OP].[tblQuestionScore]
                WHERE EventQuestionID = @StopEventQuestionID AND RawS > 0;

                MERGE INTO [OP].[tblRoundScore] AS target
                USING (
                    SELECT qw.TeamID, qw.RawS, f.Points
                    FROM #QuestionWinners qw
                    JOIN [OP].[tblRoundTypeFixedPoints] f ON f.RoundTypeID = @RoundTypeID AND f.RankPlace = qw.Rnk
                ) AS source
                ON target.RoundID = @SQ_RoundID AND target.TeamID = source.TeamID
                WHEN MATCHED THEN
                    UPDATE SET F = target.F + source.Points, RawSSum = target.RawSSum + source.RawS
                WHEN NOT MATCHED THEN
                    INSERT (RoundID, TeamID, RawSSum, Place, F)
                    VALUES (@SQ_RoundID, source.TeamID, source.RawS, 1, source.Points);

                ;WITH RankedDuel AS (
                    SELECT Place, RANK() OVER (ORDER BY F DESC, RawSSum DESC) AS NewPlace
                    FROM [OP].[tblRoundScore]
                    WHERE RoundID = @SQ_RoundID
                )
                UPDATE RankedDuel
                SET Place = NewPlace;
            END

            DECLARE @StInnerJson NVARCHAR(MAX) = (
                SELECT
                    @StopEventQuestionID AS EventQuestionID,
                    @StopEventQuestionID AS ActiveEventQuestionID,
                    @SQ_RoundID AS RoundID,
                    'question' AS Screen,
                    'stopped' AS QuestionStatus,
                    @Now AS StoppedAtUtc,
                    CAST(0 AS BIT) AS ClockPaused,
                    0 AS ClockLeftMs,
                    @NextStateVersion AS StateVersion
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @StopEventQuestionID AS EventQuestionID,
                    @StopEventQuestionID AS ActiveEventQuestionID,
                    @SQ_RoundID AS RoundID,
                    'question' AS Screen,
                    'stopped' AS QuestionStatus,
                    @Now AS StoppedAtUtc,
                    CAST(0 AS BIT) AS ClockPaused,
                    0 AS ClockLeftMs,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@StInnerJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.CloseRound'
        BEGIN
            DECLARE @CR_RoundID INT = COALESCE(JSON_VALUE(@Json, '$.Payload.RoundID'), JSON_VALUE(@Json, '$.Payload.RoundId'));

            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND StatusCode != 'stopped' AND ActiveFlg = 1)
            BEGIN
                THROW 50035, N'Még van nyitott vagy indítatlan kérdés a fordulóban!', 1;
            END

            DECLARE @CR_FGivenMode VARCHAR(20), @CR_FPointMode VARCHAR(20), @CR_RoundTypeID INT;
            SELECT @CR_FGivenMode = rt.FGivenMode, @CR_FPointMode = rt.FPointMode, @CR_RoundTypeID = rt.id
            FROM [OP].[tblRound] r JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id WHERE r.id = @CR_RoundID;

            IF @CR_FGivenMode = 'after_round'
            BEGIN
                -- Az F pontot csak azok a csapatok kapják / azokhoz mérjük, ahol legalább egy játékos
                -- beküldött választ a forduló valamelyik kérdésére. A többi csapat F = 0 és a rangsor végén áll.
                SELECT DISTINCT tm.TeamID
                INTO #CR_Participants
                FROM [OP].[tblAnswer] a
                JOIN [OP].[tblEventQuestion] eqP ON a.EventQuestionID = eqP.id AND eqP.RoundID = @CR_RoundID AND eqP.ActiveFlg = 1
                JOIN [OP].[tblTeamMember] tm ON a.EventUserID = tm.EventUserID AND tm.ActiveFlg = 1
                JOIN [OP].[tblTeam] tp ON tp.id = tm.TeamID AND tp.EventID = @EventID AND tp.ActiveFlg = 1
                WHERE a.ActiveFlg = 1;

                DECLARE @N INT = (SELECT COUNT(*) FROM #CR_Participants);
                IF @N = 0 SET @N = 1;

                SELECT t.id AS TeamID,
                       ISNULL(SUM(qs.RawS), 0) AS RawSSum,
                       CAST(CASE WHEN p.TeamID IS NULL THEN 0 ELSE 1 END AS BIT) AS Participated
                INTO #CR_TeamBase
                FROM [OP].[tblTeam] t
                LEFT JOIN #CR_Participants p ON p.TeamID = t.id
                LEFT JOIN [OP].[tblQuestionScore] qs ON t.id = qs.TeamID AND qs.EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND ActiveFlg = 1)
                WHERE t.EventID = @EventID AND t.ActiveFlg = 1
                GROUP BY t.id, p.TeamID;

                SELECT TeamID, RawSSum, Participated,
                       CASE WHEN Participated = 1
                            THEN RANK() OVER (PARTITION BY Participated ORDER BY RawSSum DESC)
                            ELSE @N + 1 END AS Place
                INTO #CR_TeamScores
                FROM #CR_TeamBase;

                DELETE FROM [OP].[tblRoundScore] WHERE RoundID = @CR_RoundID;

                IF @CR_FPointMode = 'dynamic'
                BEGIN
                    DECLARE @P_max FLOAT = 100.0;
                    DECLARE @P_min FLOAT = CASE WHEN @N <= 5 THEN 50.0 WHEN @N <= 10 THEN 40.0 WHEN @N <= 20 THEN 30.0 ELSE 20.0 END;

                    INSERT INTO [OP].[tblRoundScore] (RoundID, TeamID, RawSSum, Place, F)
                    SELECT @CR_RoundID, TeamID, RawSSum, Place,
                        CASE WHEN Participated = 0 THEN 0
                             WHEN @N = 1 THEN @P_max
                             ELSE ROUND(@P_min + (@P_max - @P_min) * CAST((@N - Place) AS FLOAT) / CAST((@N - 1) AS FLOAT), 0) END AS F
                    FROM #CR_TeamScores;

                    SELECT DISTINCT a.EventUserID
                    INTO #CR_UserParticipants
                    FROM [OP].[tblAnswer] a
                    JOIN [OP].[tblEventQuestion] eqU ON a.EventQuestionID = eqU.id AND eqU.RoundID = @CR_RoundID AND eqU.ActiveFlg = 1
                    WHERE a.ActiveFlg = 1;

                    DECLARE @M INT = (SELECT COUNT(*) FROM #CR_UserParticipants);
                    IF @M = 0 SET @M = 1;
                    DECLARE @SP_min FLOAT = CASE WHEN @M <= 5 THEN 50.0 WHEN @M <= 10 THEN 40.0 WHEN @M <= 20 THEN 30.0 ELSE 20.0 END;

                    SELECT eu.id AS EventUserID,
                           ISNULL(SUM(ss.S), 0) AS RawSSum,
                           CAST(CASE WHEN up.EventUserID IS NULL THEN 0 ELSE 1 END AS BIT) AS Participated
                    INTO #CR_ShadowBase
                    FROM [EJ].[tblEventUser] eu
                    LEFT JOIN #CR_UserParticipants up ON up.EventUserID = eu.id
                    LEFT JOIN [OP].[tblShadowScore] ss ON eu.id = ss.EventUserID AND ss.EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND ActiveFlg = 1)
                    WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1
                    GROUP BY eu.id, up.EventUserID;

                    SELECT EventUserID, RawSSum, Participated,
                           CASE WHEN Participated = 1
                                THEN RANK() OVER (PARTITION BY Participated ORDER BY RawSSum DESC)
                                ELSE @M + 1 END AS Place
                    INTO #CR_ShadowScores
                    FROM #CR_ShadowBase;

                    DELETE FROM [OP].[tblShadowRoundScore] WHERE RoundID = @CR_RoundID;
                    INSERT INTO [OP].[tblShadowRoundScore] (RoundID, EventUserID, RawSSum, Place, F)
                    SELECT @CR_RoundID, EventUserID, RawSSum, Place,
                        CASE WHEN Participated = 0 THEN 0
                             WHEN @M = 1 THEN @P_max
                             ELSE ROUND(@SP_min + (@P_max - @SP_min) * CAST((@M - Place) AS FLOAT) / CAST((@M - 1) AS FLOAT), 0) END AS F
                    FROM #CR_ShadowScores;
                END
                ELSE IF @CR_FPointMode = 'fixed'
                BEGIN
                    INSERT INTO [OP].[tblRoundScore] (RoundID, TeamID, RawSSum, Place, F)
                    SELECT @CR_RoundID, rs.TeamID, rs.RawSSum, rs.Place, CASE WHEN rs.Participated = 1 THEN ISNULL(fp.Points, 0) ELSE 0 END
                    FROM #CR_TeamScores rs
                    LEFT JOIN [OP].[tblRoundTypeFixedPoints] fp ON fp.RoundTypeID = @CR_RoundTypeID AND fp.RankPlace = rs.Place;
                END
            END
            ELSE
            BEGIN
                -- manual_display (pl. Mozaik, Karaoke) és after_question (pl. duel_speed) körök lezárásakor
                -- biztosítjuk, hogy minden aktív csapat szerepeljen a tblRoundScore-ban, és a Place helyes legyen.
                SELECT
                    t.id AS TeamID,
                    ISNULL(rsExisting.RawSSum, ISNULL(qsAgg.RawSSum, ISNULL(rsExisting.F, 0))) AS RawSSum,
                    ISNULL(rsExisting.F, 0) AS F
                INTO #CR_ManualBase
                FROM [OP].[tblTeam] t
                LEFT JOIN [OP].[tblRoundScore] rsExisting ON rsExisting.RoundID = @CR_RoundID AND rsExisting.TeamID = t.id
                OUTER APPLY (
                    SELECT SUM(qs.RawS) AS RawSSum
                    FROM [OP].[tblQuestionScore] qs
                    JOIN [OP].[tblEventQuestion] eqM ON qs.EventQuestionID = eqM.id
                    WHERE eqM.RoundID = @CR_RoundID AND eqM.ActiveFlg = 1 AND qs.TeamID = t.id
                ) qsAgg
                WHERE t.EventID = @EventID AND t.ActiveFlg = 1;

                DELETE FROM [OP].[tblRoundScore] WHERE RoundID = @CR_RoundID;

                INSERT INTO [OP].[tblRoundScore] (RoundID, TeamID, RawSSum, Place, F)
                SELECT
                    @CR_RoundID,
                    mb.TeamID,
                    mb.RawSSum,
                    RANK() OVER (ORDER BY mb.F DESC, mb.RawSSum DESC) AS Place,
                    mb.F
                FROM #CR_ManualBase mb;
            END

            DECLARE @ClosedStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'closed');
            UPDATE [OP].[tblRound] SET RoundStatusID = @ClosedStatusID WHERE id = @CR_RoundID AND EventID = @EventID;

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @CR_RoundID AS RoundID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @CR_RoundID AS RoundID, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.PublishRound'
        BEGIN
            DECLARE @PR_RoundID INT = COALESCE(JSON_VALUE(@Json, '$.Payload.RoundID'), JSON_VALUE(@Json, '$.Payload.RoundId'));
            DECLARE @PubStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'published');
            UPDATE [OP].[tblRound] SET RoundStatusID = @PubStatusID WHERE id = @PR_RoundID AND EventID = @EventID;

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @PR_RoundID AS RoundID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @PR_RoundID AS RoundID, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.SubmitAnswer'
        BEGIN
            DECLARE @SUB_EventQuestionID INT = COALESCE(
                CAST(JSON_VALUE(@Json, '$.Payload.EventQuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.ExtraQuestionId') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionID') AS INT),
                CAST(JSON_VALUE(@Json, '$.Payload.QuestionId') AS INT)
            );
            DECLARE @SUB_ElapsedMs INT = JSON_VALUE(@Json, '$.Payload.ElapsedMs');

            IF NOT EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @SUB_EventQuestionID AND EventID = @EventID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50032, N'A kérdés már le van zárva vagy nem is aktív!', 1;
            END

            IF EXISTS (
                SELECT 1 FROM [OP].[tblEventQuestion] eq
                JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
                JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
                WHERE eq.id = @SUB_EventQuestionID AND qt.Code = 'no_options'
            )
            BEGIN
                COMMIT TRANSACTION;
                SELECT 1 AS ReturnValue, N'Opció nélküli kérdéshez nem tartozik válaszbeküldés.' AS ReturnDescription;
                SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
                RETURN;
            END

            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @SUB_EventQuestionID AND ClockPaused = 1)
            BEGIN
                THROW 50032, N'A kérdés szünetel vagy még felolvasás alatt van!', 1;
            END

            DECLARE @MyEventUserID2 BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            IF @MyEventUserID2 IS NULL THROW 50033, N'Nem vagy bejelentkezve az eseményre!', 1;

            UPDATE [OP].[tblTeamMember]
            SET LastSeenUtc = @NowUtc
            WHERE EventUserID = @MyEventUserID2 AND ActiveFlg = 1
              AND (LastSeenUtc IS NULL OR LastSeenUtc < DATEADD(SECOND, -60, @NowUtc));

            UPDATE [OP].[tblAnswer] SET ActiveFlg = 0 WHERE EventUserID = @MyEventUserID2 AND EventQuestionID = @SUB_EventQuestionID;

            DECLARE @AnsId INT;
            INSERT INTO [OP].[tblAnswer] (EventQuestionID, EventUserID, ReceivedAtUtc, ElapsedMs, ActiveFlg)
            VALUES (@SUB_EventQuestionID, @MyEventUserID2, @Now, @SUB_ElapsedMs, 1);
            SET @AnsId = SCOPE_IDENTITY();

            DECLARE @ItemsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.Payload.Items');
            IF @ItemsJson IS NOT NULL
            BEGIN
                INSERT INTO [OP].[tblAnswerItem] (AnswerID, OptionID, MatchOptionID, SortIndex, TextValue)
                SELECT @AnsId,
                    JSON_VALUE(value, '$.OptionID'),
                    JSON_VALUE(value, '$.MatchOptionID'),
                    JSON_VALUE(value, '$.SortIndex'),
                    JSON_VALUE(value, '$.TextValue')
                FROM OPENJSON(@ItemsJson);
            END

            DECLARE @CorrectFlg BIT = JSON_VALUE(@Json, '$.Payload.Correct');
            DECLARE @Ratio DECIMAL(12,4) = JSON_VALUE(@Json, '$.Payload.Ratio');

            -- Szerveroldali kiértékelés ha a játékos kliens nem kapta meg a CorrectJson-t (§5.1)
            IF (@CorrectFlg IS NULL OR @CorrectFlg = 0) AND (@Ratio IS NULL OR @Ratio = 0) AND EXISTS (SELECT 1 FROM [OP].[tblAnswerItem] WHERE AnswerID = @AnsId)
            BEGIN
                DECLARE @SubQID INT, @SubTypeCode NVARCHAR(16);
                SELECT @SubQID = eq.QuestionID, @SubTypeCode = qt.Code
                FROM [OP].[tblEventQuestion] eq
                JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
                JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
                WHERE eq.id = @SUB_EventQuestionID;

                IF @SubTypeCode = 'single'
                BEGIN
                    IF EXISTS (
                        SELECT 1 FROM [OP].[tblAnswerItem] ai
                        JOIN [OP].[tblQuestionCorrectAnswer] ca ON ca.QuestionID = @SubQID AND ca.OptionID = ai.OptionID
                        WHERE ai.AnswerID = @AnsId
                    )
                    BEGIN
                        SET @CorrectFlg = 1;
                        SET @Ratio = 1.0;
                    END
                END
                ELSE IF @SubTypeCode = 'multi'
                BEGIN
                    DECLARE @TotalCorr INT = (SELECT COUNT(*) FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @SubQID);
                    DECLARE @HitCorr INT = (
                        SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
                        JOIN [OP].[tblQuestionCorrectAnswer] ca ON ca.QuestionID = @SubQID AND ca.OptionID = ai.OptionID
                        WHERE ai.AnswerID = @AnsId
                    );
                    DECLARE @WrongPick INT = (
                        SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
                        WHERE ai.AnswerID = @AnsId AND NOT EXISTS (
                            SELECT 1 FROM [OP].[tblQuestionCorrectAnswer] ca WHERE ca.QuestionID = @SubQID AND ca.OptionID = ai.OptionID
                        )
                    );
                    IF @TotalCorr > 0
                    BEGIN
                        SET @Ratio = CASE WHEN @HitCorr - @WrongPick <= 0 THEN 0.0 ELSE CAST(@HitCorr - @WrongPick AS DECIMAL(12,4)) / @TotalCorr END;
                        SET @CorrectFlg = CASE WHEN @HitCorr = @TotalCorr AND @WrongPick = 0 THEN 1 ELSE 0 END;
                    END
                END
                ELSE IF @SubTypeCode = 'order'
                BEGIN
                    DECLARE @OrdTotal INT = (SELECT COUNT(*) FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @SubQID);
                    DECLARE @OrdHits INT = (
                        SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
                        JOIN [OP].[tblQuestionCorrectAnswer] ca ON ca.QuestionID = @SubQID AND ca.OptionID = ai.OptionID AND ca.SortIndex = ai.SortIndex
                        WHERE ai.AnswerID = @AnsId
                    );
                    IF @OrdTotal > 0
                    BEGIN
                        SET @Ratio = CAST(@OrdHits AS DECIMAL(12,4)) / @OrdTotal;
                        SET @CorrectFlg = CASE WHEN @OrdHits = @OrdTotal THEN 1 ELSE 0 END;
                    END
                END
                ELSE IF @SubTypeCode IN ('match', 'category')
                BEGIN
                    DECLARE @MatchTotal INT = (SELECT COUNT(*) FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @SubQID);
                    DECLARE @MatchHits INT = (
                        SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
                        JOIN [OP].[tblQuestionCorrectAnswer] ca ON ca.QuestionID = @SubQID AND ca.OptionID = ai.OptionID AND ca.MatchOptionID = ai.MatchOptionID
                        WHERE ai.AnswerID = @AnsId
                    );
                    IF @MatchTotal > 0
                    BEGIN
                        SET @Ratio = CAST(@MatchHits AS DECIMAL(12,4)) / @MatchTotal;
                        SET @CorrectFlg = CASE WHEN @MatchHits = @MatchTotal THEN 1 ELSE 0 END;
                    END
                END
                ELSE IF @SubTypeCode = 'freetext'
                BEGIN
                    DECLARE @SubmittedText NVARCHAR(500) = LOWER(LTRIM(RTRIM(ISNULL((SELECT TOP 1 TextValue FROM [OP].[tblAnswerItem] WHERE AnswerID = @AnsId), N''))));
                    DECLARE @AcceptedPipe NVARCHAR(MAX) = (SELECT TOP 1 TextValue FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @SubQID);
                    IF @SubmittedText != N'' AND @AcceptedPipe IS NOT NULL AND EXISTS (
                        SELECT 1 FROM STRING_SPLIT(@AcceptedPipe, '|') s
                        WHERE LOWER(LTRIM(RTRIM(s.value))) = @SubmittedText
                    )
                    BEGIN
                        SET @CorrectFlg = 1;
                        SET @Ratio = 1.0;
                    END
                END
            END

            IF @Ratio IS NULL
            BEGIN
                SET @Ratio = CASE WHEN @CorrectFlg = 1 THEN 1.0 ELSE 0.0 END;
            END
            IF @CorrectFlg IS NULL
            BEGIN
                SET @CorrectFlg = CASE WHEN @Ratio >= 1.0 THEN 1 ELSE 0 END;
            END

            UPDATE [OP].[tblAnswer] SET CorrectFlg = @CorrectFlg, Ratio = @Ratio WHERE id = @AnsId;

            DECLARE @AnswerCount INT = (SELECT COUNT(DISTINCT EventUserID) FROM [OP].[tblAnswer] WHERE EventQuestionID = @SUB_EventQuestionID AND ActiveFlg = 1);
            DECLARE @RosterCount INT = (SELECT COUNT(DISTINCT tm.EventUserID) FROM [OP].[tblTeamMember] tm JOIN [OP].[tblTeam] t ON tm.TeamID = t.id WHERE t.EventID = @EventID AND t.ActiveFlg = 1 AND tm.ActiveFlg = 1);

            -- §5.4: EventQuestionID, AnswerCount, StateVersion mind a 4 csoportba (választott opció nélkül)
            DECLARE @SAPing NVARCHAR(MAX) = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @SUB_EventQuestionID AS EventQuestionID,
                    @CurrentStateVersion AS StateVersion,
                    @AnswerCount AS AnswerCount,
                    @RosterCount AS RosterCount,
                    JSON_QUERY((SELECT @SUB_EventQuestionID AS EventQuestionID, @CurrentStateVersion AS StateVersion, @AnswerCount AS AnswerCount, @RosterCount AS RosterCount FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SAPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SAPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @SAPing);

            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres válaszadás' AS ReturnDescription;
            SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
            RETURN;
        END
        ELSE IF @Action = N'Op.AdjustTeam'
        BEGIN
            DECLARE @ADJ_TeamID INT = JSON_VALUE(@Json, '$.Payload.TeamID');
            DECLARE @PenaltyTypeCode VARCHAR(50) = JSON_VALUE(@Json, '$.Payload.PenaltyTypeCode');
            DECLARE @ADJ_Direction NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Direction');

            DECLARE @ADJ_Points INT = JSON_VALUE(@Json, '$.Payload.Points');
            IF @ADJ_Points IS NULL AND @ADJ_Direction IS NOT NULL
            BEGIN
                SET @ADJ_Points = CASE WHEN @ADJ_Direction = 'plus' THEN 10 WHEN @ADJ_Direction = 'minus' THEN -10 ELSE 0 END;
            END
            IF @ADJ_Points IS NULL
            BEGIN
                SET @ADJ_Points = (SELECT DefaultPoints FROM [OP].[tblPenaltyType] WHERE Code = @PenaltyTypeCode);
                IF @ADJ_Points IS NULL SET @ADJ_Points = 0;
            END

            DECLARE @PenaltyTypeID INT = (SELECT id FROM [OP].[tblPenaltyType] WHERE Code = @PenaltyTypeCode);

            DECLARE @ADJ_ActiveManualRoundID INT = (
                SELECT TOP 1 r.id
                FROM [OP].[tblRound] r
                JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
                JOIN [OP].[tblRoundStatus] rs ON r.RoundStatusID = rs.id
                WHERE r.EventID = @EventID AND r.ActiveFlg = 1 AND rs.Code = 'active'
                  AND (
                      rt.Code = 'manual_display'
                      OR EXISTS (
                          SELECT 1 FROM [OP].[tblEventQuestion] eqNo
                          JOIN [OP].[tblQuestion] qNo ON eqNo.QuestionID = qNo.id
                          JOIN [OP].[tblQuestionType] qtNo ON qNo.QuestionTypeID = qtNo.id
                          WHERE eqNo.RoundID = r.id AND eqNo.StatusCode = 'active' AND eqNo.ActiveFlg = 1 AND qtNo.Code = 'no_options'
                      )
                  )
                ORDER BY r.SortIndex ASC, r.id ASC
            );

            IF @PenaltyTypeCode IN ('manual_plus', 'manual_minus') AND @ADJ_ActiveManualRoundID IS NOT NULL
            BEGIN
                -- Ha egy manual_display játék (pl. Karaoke) épp aktív, a +Pont / -Pont gomb annak a játéknak a pontját írja
                SET @PenaltyTypeID = (SELECT id FROM [OP].[tblPenaltyType] WHERE Code = 'karaoke_pro');
            END

            DECLARE @ADJ_EventUser BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            INSERT INTO [OP].[tblPenalty] (EventID, TeamID, Points, PenaltyTypeID, EventUserID, LastCreatedUserID)
            VALUES (@EventID, @ADJ_TeamID, @ADJ_Points, @PenaltyTypeID, @ADJ_EventUser, @UserID);

            IF @PenaltyTypeCode IN ('mozaik_correct', 'karaoke_pro')
               OR (@PenaltyTypeCode IN ('manual_plus', 'manual_minus') AND @ADJ_ActiveManualRoundID IS NOT NULL)
            BEGIN
                DECLARE @ADJ_RoundID INT = COALESCE(
                    TRY_CAST(JSON_VALUE(@Json, '$.Payload.RoundID') AS INT),
                    TRY_CAST(JSON_VALUE(@Json, '$.Payload.RoundId') AS INT),
                    @ADJ_ActiveManualRoundID
                );
                DECLARE @ADJ_EQID INT = NULL;

                IF @ADJ_RoundID IS NULL
                BEGIN
                    SELECT TOP 1 @ADJ_RoundID = r.id, @ADJ_EQID = eq.id
                    FROM [OP].[tblRound] r
                    JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
                    JOIN [OP].[tblRoundStatus] rs ON r.RoundStatusID = rs.id
                    LEFT JOIN [OP].[tblEventQuestion] eq ON eq.RoundID = r.id AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1
                    WHERE r.EventID = @EventID AND r.ActiveFlg = 1 AND rt.Code = 'manual_display'
                    ORDER BY
                        CASE WHEN eq.id IS NOT NULL THEN 0 WHEN rs.Code = 'active' THEN 1 WHEN rs.Code = 'closed' THEN 2 ELSE 3 END,
                        r.SortIndex ASC, r.id ASC;
                END
                ELSE
                BEGIN
                    SELECT TOP 1 @ADJ_EQID = eq.id
                    FROM [OP].[tblEventQuestion] eq
                    WHERE eq.RoundID = @ADJ_RoundID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1
                    ORDER BY eq.SortIndex ASC, eq.id ASC;
                END

                IF @ADJ_EQID IS NOT NULL AND @ADJ_TeamID IS NOT NULL
                BEGIN
                    MERGE INTO [OP].[tblQuestionScore] AS target
                    USING (SELECT @ADJ_EQID AS EventQuestionID, @ADJ_TeamID AS TeamID, CAST(@ADJ_Points AS DECIMAL(10,4)) AS Points) AS source
                    ON target.EventQuestionID = source.EventQuestionID AND target.TeamID = source.TeamID
                    WHEN MATCHED THEN
                        UPDATE SET RawS = target.RawS + source.Points, C = target.C + 1
                    WHEN NOT MATCHED THEN
                        INSERT (EventQuestionID, TeamID, RawS, C, W, SpeedT)
                        VALUES (source.EventQuestionID, source.TeamID, source.Points, 1, 0, 0);
                END

                IF @ADJ_RoundID IS NOT NULL AND @ADJ_TeamID IS NOT NULL
                BEGIN
                    MERGE INTO [OP].[tblRoundScore] AS target
                    USING (SELECT @ADJ_RoundID AS RoundID, @ADJ_TeamID AS TeamID, CAST(@ADJ_Points AS DECIMAL(10,4)) AS RawDelta, @ADJ_Points AS FDelta) AS source
                    ON target.RoundID = source.RoundID AND target.TeamID = source.TeamID
                    WHEN MATCHED THEN
                        UPDATE SET RawSSum = target.RawSSum + source.RawDelta, F = target.F + source.FDelta
                    WHEN NOT MATCHED THEN
                        INSERT (RoundID, TeamID, RawSSum, Place, F)
                        VALUES (source.RoundID, source.TeamID, source.RawDelta, 1, source.FDelta);

                    ;WITH RankedRound AS (
                        SELECT Place, RANK() OVER (ORDER BY F DESC, RawSSum DESC) AS NewPlace
                        FROM [OP].[tblRoundScore]
                        WHERE RoundID = @ADJ_RoundID
                    )
                    UPDATE RankedRound
                    SET Place = NewPlace;
                END
            END

            IF @PenaltyTypeCode = 'mozaik_wrong'
            BEGIN
                UPDATE eq
                SET eq.MosaicTipEventUserID = NULL,
                    eq.MosaicTipTeamID = NULL,
                    eq.ClockPaused = 0,
                    eq.AnswerStartedAtUtc = CASE
                        WHEN eq.ClockLeftMs IS NOT NULL AND eq.TimeSec IS NOT NULL
                        THEN DATEADD(MILLISECOND, -((eq.TimeSec * 1000) - eq.ClockLeftMs), @NowUtc)
                        ELSE ISNULL(eq.AnswerStartedAtUtc, @NowUtc)
                    END
                FROM [OP].[tblEventQuestion] eq
                WHERE eq.EventID = @EventID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1;

                DECLARE @ADJ_OutTeamsJson NVARCHAR(MAX) = ISNULL((
                    SELECT '[' + STRING_AGG(CAST(TeamID AS NVARCHAR(20)), ',') + ']'
                    FROM (
                        SELECT DISTINCT p.TeamID
                        FROM [OP].[tblPenalty] p
                        JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
                        WHERE p.EventID = @EventID AND pt.Code = 'mozaik_wrong' AND p.ActiveFlg = 1 AND p.TeamID IS NOT NULL
                    ) t
                ), '[]');

                IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID AND ISJSON(PayloadJson) = 1)
                BEGIN
                    UPDATE [OP].[DisplayCast]
                    SET PayloadJson = JSON_MODIFY(
                            JSON_MODIFY(
                                JSON_MODIFY(
                                    JSON_MODIFY(
                                        JSON_MODIFY(PayloadJson, '$.TipName', N''),
                                        '$.TipTeam', N''
                                    ),
                                    '$.ClockPhase', N'play'
                                ),
                                '$.ClockHold', CAST(0 AS BIT)
                            ),
                            '$.MosaicOutTeamIds', JSON_QUERY(@ADJ_OutTeamsJson)
                        ),
                        StateVersion = @NextStateVersion,
                        UpdatedAtUtc = @Now
                    WHERE EventID = @EventID AND ISJSON(PayloadJson) = 1;
                END
            END

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @ADJ_TeamID AS TeamID,
                    @ADJ_Points AS Points,
                    @PenaltyTypeCode AS PenaltyTypeCode,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @ADJ_TeamID AS TeamID, @ADJ_Points AS Points, @PenaltyTypeCode AS PenaltyTypeCode, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.JoinTeam'
        BEGIN
            DECLARE @JT_TeamID INT = JSON_VALUE(@Json, '$.Payload.TeamID');
            DECLARE @JT_EventUserID BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);

            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblRound] r ON eq.RoundID = r.id WHERE r.EventID = @EventID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1)
            BEGIN
                THROW 50036, N'A kérdés alatt nem válthatsz csapatot.', 1;
            END

            UPDATE [OP].[tblTeamMember] SET ActiveFlg = 0 WHERE EventUserID = @JT_EventUserID AND ActiveFlg = 1;

            IF NOT EXISTS (SELECT 1 FROM [OP].[tblTeamMember] WHERE TeamID = @JT_TeamID AND EventUserID = @JT_EventUserID)
            BEGIN
                INSERT INTO [OP].[tblTeamMember] (TeamID, EventUserID, ActiveFlg, LastSeenUtc) VALUES (@JT_TeamID, @JT_EventUserID, 1, @NowUtc);
            END
            ELSE
            BEGIN
                UPDATE [OP].[tblTeamMember] SET ActiveFlg = 1, LastSeenUtc = @NowUtc WHERE TeamID = @JT_TeamID AND EventUserID = @JT_EventUserID;
            END

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @JT_TeamID AS TeamID,
                    @JT_EventUserID AS EventUserID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @JT_TeamID AS TeamID, @JT_EventUserID AS EventUserID, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.ResetRound'
        BEGIN
            DECLARE @ResetRoundID INT = COALESCE(JSON_VALUE(@Json, '$.Payload.RoundID'), JSON_VALUE(@Json, '$.Payload.RoundId'));

            DELETE FROM [OP].[tblAnswerItem] WHERE AnswerID IN (SELECT id FROM [OP].[tblAnswer] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID));
            DELETE FROM [OP].[tblAnswer] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID);
            DELETE FROM [OP].[tblQuestionScore] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID);
            DELETE FROM [OP].[tblShadowScore] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID);
            DELETE FROM [OP].[tblRoundScore] WHERE RoundID = @ResetRoundID;
            DELETE FROM [OP].[tblShadowRoundScore] WHERE RoundID = @ResetRoundID;

            UPDATE p
            SET p.ActiveFlg = 0
            FROM [OP].[tblPenalty] p
            JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
            WHERE p.EventID = @EventID
              AND p.ActiveFlg = 1
              AND (
                  pt.Code = 'mozaik_wrong'
                  OR (
                      pt.Code IN ('mozaik_correct', 'karaoke_pro')
                      AND EXISTS (
                          SELECT 1 FROM [OP].[tblRound] rReset
                          JOIN [OP].[tblRoundType] rtReset ON rReset.RoundTypeID = rtReset.id
                          WHERE rReset.id = @ResetRoundID AND rtReset.Code = 'manual_display'
                      )
                  )
              );

            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'pending', StartedAtUtc = NULL, AnswerStartedAtUtc = NULL, StoppedAtUtc = NULL, ClockPaused = 0, ClockLeftMs = NULL, MosaicTipEventUserID = NULL, MosaicTipTeamID = NULL
            WHERE RoundID = @ResetRoundID;

            DECLARE @PendingStID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'pending');
            UPDATE [OP].[tblRound] SET RoundStatusID = @PendingStID, FocusedEventQuestionID = NULL WHERE id = @ResetRoundID AND EventID = @EventID;

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @ResetRoundID AS RoundID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @ResetRoundID AS RoundID, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.LeaveTeam'
        BEGIN
            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblRound] r ON eq.RoundID = r.id WHERE r.EventID = @EventID AND eq.StatusCode = 'active' AND eq.ActiveFlg = 1)
            BEGIN
                THROW 50040, N'A kérdés alatt nem válthatsz csapatot.', 1;
            END

            DECLARE @LT_EventUserID BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            IF @LT_EventUserID IS NOT NULL
            BEGIN
                UPDATE [OP].[tblTeamMember] SET ActiveFlg = 0 WHERE EventUserID = @LT_EventUserID AND ActiveFlg = 1;
            END

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @LT_EventUserID AS EventUserID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @LT_EventUserID AS EventUserID, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.React'
        BEGIN
            DECLARE @Glyph NVARCHAR(16) = JSON_VALUE(@Json, '$.Payload.Glyph');
            DECLARE @ReactPing NVARCHAR(MAX) = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @Glyph AS Glyph,
                    @CurrentStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @Glyph AS Glyph, @CurrentStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @ReactPing);

            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;
            SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
            RETURN;
        END
        ELSE IF @Action = N'Op.MosaicBuzz'
        BEGIN
            DECLARE @MB_EventUser BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            DECLARE @MB_TeamID INT = COALESCE(CAST(JSON_VALUE(@Json, '$.Payload.TeamID') AS INT), (SELECT TOP 1 TeamID FROM [OP].[tblTeamMember] WHERE EventUserID = @MB_EventUser AND ActiveFlg = 1));
            DECLARE @MB_TeamName NVARCHAR(100) = COALESCE(JSON_VALUE(@Json, '$.Payload.TeamName'), (SELECT k.Name FROM [OP].[tblTeam] t JOIN [OP].[tblKabala] k ON t.KabalaID = k.id WHERE t.id = @MB_TeamID));
            DECLARE @MB_Nickname NVARCHAR(100) = COALESCE(JSON_VALUE(@Json, '$.Payload.Nickname'), (SELECT Nickname FROM [EJ].[tblUser] WHERE id = @UserID));
            DECLARE @MB_LeftMs INT = COALESCE(
                TRY_CAST(JSON_VALUE(@Json, '$.Payload.LeftMs') AS INT),
                TRY_CAST(JSON_VALUE(@Json, '$.Payload.ClockLeftMs') AS INT)
            );

            DECLARE @MB_EQID INT = NULL;
            SELECT TOP 1 @MB_EQID = eq.id
            FROM [OP].[tblEventQuestion] eq
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id
            JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
            WHERE r.EventID = @EventID
              AND eq.StatusCode = 'active'
              AND eq.ActiveFlg = 1
              AND r.ActiveFlg = 1
              AND rt.Code = 'manual_display'
            ORDER BY eq.StartedAtUtc DESC, eq.id DESC;

            DECLARE @MB_Accepted BIT = 0;

            IF @MB_EQID IS NOT NULL
               AND @MB_TeamID IS NOT NULL
               AND NOT EXISTS (
                   SELECT 1 FROM [OP].[tblPenalty] p
                   JOIN [OP].[tblPenaltyType] pt ON p.PenaltyTypeID = pt.id
                   WHERE p.EventID = @EventID AND p.TeamID = @MB_TeamID AND pt.Code = 'mozaik_wrong' AND p.ActiveFlg = 1
               )
            BEGIN
                UPDATE eq WITH (UPDLOCK, ROWLOCK)
                SET eq.MosaicTipEventUserID = @MB_EventUser,
                    eq.MosaicTipTeamID = @MB_TeamID,
                    eq.ClockPaused = 1,
                    eq.ClockLeftMs = COALESCE(@MB_LeftMs, eq.ClockLeftMs)
                FROM [OP].[tblEventQuestion] eq
                WHERE eq.id = @MB_EQID
                  AND eq.StatusCode = 'active'
                  AND eq.MosaicTipTeamID IS NULL
                  AND eq.MosaicTipEventUserID IS NULL;

                IF @@ROWCOUNT = 1
                BEGIN
                    SET @MB_Accepted = 1;
                END
            END

            IF @MB_Accepted = 0
            BEGIN
                COMMIT TRANSACTION;
                SELECT 1 AS ReturnValue, N'Tipp figyelmen kívül hagyva.' AS ReturnDescription;
                SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
                RETURN;
            END

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID AND ISJSON(PayloadJson) = 1)
            BEGIN
                UPDATE [OP].[DisplayCast]
                SET PayloadJson = JSON_MODIFY(
                        JSON_MODIFY(
                            JSON_MODIFY(
                                JSON_MODIFY(PayloadJson, '$.TipName', ISNULL(@MB_Nickname, N'')),
                                '$.TipTeam', ISNULL(@MB_TeamName, N'')
                            ),
                            '$.ClockPhase', N'paused'
                        ),
                        '$.ClockHold', CAST(1 AS BIT)
                    ),
                    StateVersion = @NextStateVersion,
                    UpdatedAtUtc = @Now
                WHERE EventID = @EventID AND ISJSON(PayloadJson) = 1;
            END

            DECLARE @MB_InnerPayload NVARCHAR(MAX) = (
                SELECT
                    @MB_TeamID AS TeamID,
                    @MB_TeamName AS TeamName,
                    @MB_TeamName AS TipTeam,
                    @MB_Nickname AS Nickname,
                    @MB_Nickname AS TipName,
                    @MB_EventUser AS EventUserID,
                    CAST(1 AS BIT) AS Hold,
                    CAST(1 AS BIT) AS ClockHold,
                    N'paused' AS ClockPhase,
                    @MB_LeftMs AS LeftMs,
                    @MB_LeftMs AS ClockLeftMs,
                    @NextStateVersion AS StateVersion
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @MB_TeamID AS TeamID,
                    @MB_TeamName AS TeamName,
                    @MB_TeamName AS TipTeam,
                    @MB_Nickname AS Nickname,
                    @MB_Nickname AS TipName,
                    @MB_EventUser AS EventUserID,
                    CAST(1 AS BIT) AS Hold,
                    CAST(1 AS BIT) AS ClockHold,
                    N'paused' AS ClockPhase,
                    @MB_LeftMs AS LeftMs,
                    @MB_LeftMs AS ClockLeftMs,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@MB_InnerPayload) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action = N'Op.MosaicJudge'
        BEGIN
            DECLARE @MJ_TeamID INT = JSON_VALUE(@Json, '$.Payload.TeamID');
            DECLARE @MJ_CorrectFlg BIT = JSON_VALUE(@Json, '$.Payload.CorrectFlg');

            UPDATE [OP].[tblEventQuestion]
            SET MosaicTipEventUserID = NULL,
                MosaicTipTeamID = NULL,
                ClockPaused = 0
            WHERE EventID = @EventID AND StatusCode = 'active' AND ActiveFlg = 1;

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @MJ_TeamID AS TeamID,
                    @MJ_CorrectFlg AS CorrectFlg,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @MJ_TeamID AS TeamID, @MJ_CorrectFlg AS CorrectFlg, @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE IF @Action IN (N'Op.KaraokeSet', N'Op.StartExtra', N'Op.StopExtra', N'Op.ResetExtra')
        BEGIN
            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY((SELECT @NextStateVersion AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );
        END
        ELSE
        BEGIN
            DECLARE @Err NVARCHAR(200) = N'Ismeretlen Olimpub Action: ' + ISNULL(@Action, ''); THROW 50040, @Err, 1;
        END

        -- §5.2: Ha kérdéslapot indító parancs volt (@CardEQID IS NOT NULL), összerakjuk a teljes kérdéslapot helyes válasz nélkül
        IF @CardEQID IS NOT NULL
        BEGIN
            DECLARE @C_RoundID INT, @C_SortIndex INT, @C_TopicName NVARCHAR(200), @C_Prompt NVARCHAR(MAX), @C_TypeCode NVARCHAR(32), @C_TimeSec INT;
            DECLARE @C_ImageKey NVARCHAR(500), @C_ImageUrl NVARCHAR(500), @C_AudioKey NVARCHAR(500), @C_AudioUrl NVARCHAR(500), @C_MediaUrl NVARCHAR(500);
            DECLARE @C_QuestionID INT, @C_StartedAt DATETIMEOFFSET, @C_AnswerStartedAt DATETIMEOFFSET, @C_ClockPaused BIT, @C_ClockLeftMs INT;

            SELECT
                @C_QuestionID = eq.QuestionID,
                @C_RoundID = eq.RoundID,
                @C_SortIndex = eq.SortIndex,
                @C_TopicName = COALESCE(topR.Name, topQ.Name, rt.Name, N''),
                @C_Prompt = q.Prompt,
                @C_TypeCode = qt.Code,
                @C_TimeSec = eq.TimeSec,
                @C_StartedAt = TODATETIMEOFFSET(eq.StartedAtUtc, 0),
                @C_AnswerStartedAt = TODATETIMEOFFSET(eq.AnswerStartedAtUtc, 0),
                @C_ClockPaused = ISNULL(eq.ClockPaused, 1),
                @C_ClockLeftMs = ISNULL(eq.ClockLeftMs, eq.TimeSec * 1000),
                @C_ImageKey = q.ImageKey,
                @C_ImageUrl = CASE WHEN q.ImageKey IS NOT NULL AND q.ImageKey != ''
                                   THEN CASE WHEN q.ImageKey LIKE 'http%' THEN q.ImageKey ELSE @BlobBaseUrl + q.ImageKey END
                                   ELSE q.MediaUrl
                              END,
                @C_AudioKey = q.AudioKey,
                @C_AudioUrl = CASE WHEN q.AudioKey IS NOT NULL AND q.AudioKey != ''
                                   THEN CASE WHEN q.AudioKey LIKE 'http%' THEN q.AudioKey ELSE @BlobBaseUrl + q.AudioKey END
                                   ELSE NULL
                              END,
                @C_MediaUrl = q.MediaUrl
            FROM [OP].[tblEventQuestion] eq
            JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
            JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id
            JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id
            LEFT JOIN [OP].[tblTopic] topR ON r.TopicID = topR.id
            LEFT JOIN [OP].[tblTopic] topQ ON q.TopicID = topQ.id
            WHERE eq.id = @CardEQID;

            DECLARE @C_AnswersJson NVARCHAR(MAX) = CASE
                WHEN @C_TypeCode IN ('freetext', 'no_options') THEN '[]'
                ELSE ISNULL((SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(ISNULL(qo.Value, N''), 'json') + '"', ',') WITHIN GROUP (ORDER BY qo.SortIndex ASC, qo.id ASC) + ']' FROM [OP].[tblQuestionOption] qo WHERE qo.QuestionID = @C_QuestionID AND qo.ListType IN ('options', 'left')), '[]')
            END;

            DECLARE @C_MatchesJson NVARCHAR(MAX) = ISNULL((
                SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(ISNULL(qo.Value, N''), 'json') + '"', ',') WITHIN GROUP (ORDER BY qo.SortIndex ASC, qo.id ASC) + ']'
                FROM [OP].[tblQuestionOption] qo
                WHERE qo.QuestionID = @C_QuestionID AND qo.ListType = 'right'
            ), '[]');

            DECLARE @C_CategoriesJson NVARCHAR(MAX) = CASE
                WHEN @C_TypeCode = 'category' THEN ISNULL((
                    SELECT '[' + STRING_AGG('"' + STRING_ESCAPE(ISNULL(cat.Value, N''), 'json') + '"', ',') WITHIN GROUP (ORDER BY cat.MinSort ASC) + ']'
                    FROM (
                        SELECT qo.Value, MIN(qo.SortIndex) AS MinSort
                        FROM [OP].[tblQuestionOption] qo
                        WHERE qo.QuestionID = @C_QuestionID AND qo.ListType = 'right' AND qo.Value IS NOT NULL AND LTRIM(RTRIM(qo.Value)) != ''
                        GROUP BY qo.Value
                    ) cat
                ), '[]')
                ELSE '[]'
            END;

            DECLARE @C_OptionsJson NVARCHAR(MAX) = ISNULL((
                SELECT id, ListType, Value, SortIndex
                FROM [OP].[tblQuestionOption]
                WHERE QuestionID = @C_QuestionID
                ORDER BY SortIndex ASC, id ASC
                FOR JSON PATH
            ), '[]');

            DECLARE @CardInnerJson NVARCHAR(MAX) = (
                SELECT
                    'question' AS Screen,
                    'question' AS Face,
                    @CardEQID AS EventQuestionID,
                    @CardEQID AS ActiveEventQuestionID,
                    @C_RoundID AS RoundID,
                    @C_RoundID AS ActiveRoundID,
                    @C_SortIndex AS SortIndex,
                    @C_TopicName AS TopicName,
                    @C_Prompt AS Prompt,
                    @C_TypeCode AS TypeCode,
                    @C_TimeSec AS TimeSec,
                    JSON_QUERY(@C_AnswersJson) AS Answers,
                    JSON_QUERY(@C_MatchesJson) AS Matches,
                    JSON_QUERY(@C_CategoriesJson) AS Categories,
                    JSON_QUERY(@C_OptionsJson) AS Options,
                    @C_ImageKey AS ImageKey,
                    @C_ImageUrl AS ImageUrl,
                    @C_AudioKey AS AudioKey,
                    @C_AudioUrl AS AudioUrl,
                    @C_MediaUrl AS MediaUrl,
                    'active' AS QuestionStatus,
                    @C_StartedAt AS StartedAtUtc,
                    @C_AnswerStartedAt AS AnswerStartedAtUtc,
                    @C_ClockPaused AS ClockPaused,
                    @C_ClockPaused AS Hold,
                    @C_ClockLeftMs AS ClockLeftMs,
                    0 AS AnswerCount,
                    @NextStateVersion AS StateVersion
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
            );

            UPDATE [OP].[tblEventSettings]
            SET Screen = 'question', ScreenJson = @CardInnerJson, UpdatedAtUtc = @Now
            WHERE EventID = @EventID;

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
                UPDATE [OP].[DisplayCast] SET Face = 'question', PayloadJson = @CardInnerJson, StateVersion = @NextStateVersion, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            ELSE
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, 'question', @CardInnerJson, @NextStateVersion, @Now);

            SET @OutPing = (
                SELECT
                    @Action AS Action,
                    @EventID AS EventID,
                    'question' AS Screen,
                    'question' AS Face,
                    @CardEQID AS EventQuestionID,
                    @CardEQID AS ActiveEventQuestionID,
                    @C_RoundID AS RoundID,
                    @C_RoundID AS ActiveRoundID,
                    @C_SortIndex AS SortIndex,
                    @C_TopicName AS TopicName,
                    @C_Prompt AS Prompt,
                    @C_TypeCode AS TypeCode,
                    @C_TimeSec AS TimeSec,
                    JSON_QUERY(@C_AnswersJson) AS Answers,
                    JSON_QUERY(@C_MatchesJson) AS Matches,
                    JSON_QUERY(@C_CategoriesJson) AS Categories,
                    JSON_QUERY(@C_OptionsJson) AS Options,
                    @C_ImageKey AS ImageKey,
                    @C_ImageUrl AS ImageUrl,
                    @C_AudioKey AS AudioKey,
                    @C_AudioUrl AS AudioUrl,
                    @C_MediaUrl AS MediaUrl,
                    'active' AS QuestionStatus,
                    @C_StartedAt AS StartedAtUtc,
                    @C_AnswerStartedAt AS AnswerStartedAtUtc,
                    @C_ClockPaused AS ClockPaused,
                    @C_ClockPaused AS Hold,
                    @C_ClockLeftMs AS ClockLeftMs,
                    0 AS AnswerCount,
                    @NextStateVersion AS StateVersion,
                    JSON_QUERY(@CardInnerJson) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
            );
        END

        -- §5.1: Minden Op.* ping mind a 4 csoportba megy (gamer, gamemaster, organizer, display)
        IF @OutPing IS NOT NULL
        BEGIN
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @OutPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @OutPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @OutPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @OutPing);
        END

        UPDATE [OP].[tblEventSettings] SET StateVersion = StateVersion + 1 WHERE EventID = @EventID;

        COMMIT TRANSACTION;

        SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;
        SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
