CREATE OR ALTER PROCEDURE [OP].[spChangeGame]
    @Json NVARCHAR(MAX),
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    BEGIN TRY
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        DECLARE @EventID BIGINT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @Action NVARCHAR(50) = JSON_VALUE(@Json, '$.Action');

        IF @EventID IS NULL OR @Action IS NULL
        BEGIN
            THROW 50010, N'EventID vagy Action hiányzik a JSON-ből.', 1;
        END

        DECLARE @IsQM BIT = 0;
        DECLARE @IsOrg BIT = 0;
        IF @UserID IS NOT NULL
        BEGIN
            IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1) SET @IsOrg = 1;
            IF EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.id = 7 AND eu.ActiveFlg = 1) SET @IsQM = 1;
        END

        IF @Action != 'Op.SubmitAnswer' AND @Action != 'Op.JoinTeam' AND @Action != 'Op.LeaveTeam' AND @Action != 'Op.React'
        BEGIN
            IF @IsQM = 0 AND @IsOrg = 0
            BEGIN
                THROW 50030, N'Nincs megfelelő jogosultságod!', 1;
            END
        END

        DECLARE @CurrentStateVersion BIGINT;
        SELECT @CurrentStateVersion = StateVersion FROM [OP].[tblEventSettings] WHERE EventID = @EventID;

        DECLARE @SignalRTargets TABLE (TargetGroup NVARCHAR(100), EventName NVARCHAR(50), CustomPayload NVARCHAR(MAX));

        BEGIN TRANSACTION;

        IF @Action = N'Op.CastDisplay'
        BEGIN
            DECLARE @Face NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Face');
            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
            BEGIN
                UPDATE [OP].[DisplayCast] SET Face = @Face, PayloadJson = @Json, StateVersion = @CurrentStateVersion + 1, UpdatedAtUtc = @Now WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, @Face, @Json, @CurrentStateVersion + 1, @Now);
            END
            
            DECLARE @CDPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @CDPing);
        END
        ELSE IF @Action = N'Op.StartRound'
        BEGIN
            DECLARE @SR_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            DECLARE @ActiveStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active');
            
            IF EXISTS (SELECT 1 FROM [OP].[tblRound] WHERE EventID = @EventID AND RoundStatusID = @ActiveStatusID AND ActiveFlg = 1)
            BEGIN
                THROW 50031, N'Már van aktív forduló!', 1;
            END

            UPDATE [OP].[tblRound] SET RoundStatusID = @ActiveStatusID, FocusedEventQuestionID = NULL WHERE id = @SR_RoundID AND EventID = @EventID;
            
            DECLARE @SRPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SRPing);
        END
        ELSE IF @Action = N'Op.StartQuestion'
        BEGIN
            DECLARE @EventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            
            UPDATE [OP].[tblEventQuestion] 
            SET StatusCode = 'active', StartedAtUtc = @Now, ClockPaused = 0, ClockLeftMs = (TimeSec * 1000) 
            WHERE id = @EventQuestionID AND EventID = @EventID;
            
            UPDATE [OP].[tblRound] 
            SET FocusedEventQuestionID = @EventQuestionID 
            WHERE id = (SELECT RoundID FROM [OP].[tblEventQuestion] WHERE id = @EventQuestionID) AND EventID = @EventID;
            
            DECLARE @SQPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @SQPing);
        END
        ELSE IF @Action = N'Op.StartClock'
        BEGIN
            DECLARE @SC_EventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            UPDATE [OP].[tblEventQuestion] SET ClockPaused = 0, StartedAtUtc = @Now WHERE id = @SC_EventQuestionID AND EventID = @EventID;
            
            DECLARE @SCPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SCPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SCPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SCPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @SCPing);
        END
        ELSE IF @Action = N'Op.PauseClock'
        BEGIN
            DECLARE @PC_EventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            DECLARE @PC_ClockLeftMs INT = JSON_VALUE(@Json, '$.Payload.ClockLeftMs');
            
            UPDATE [OP].[tblEventQuestion] SET ClockPaused = 1, ClockLeftMs = @PC_ClockLeftMs WHERE id = @PC_EventQuestionID AND EventID = @EventID;
            
            DECLARE @PCPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @PCPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @PCPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @PCPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @PCPing);
        END
        ELSE IF @Action = N'Op.StopQuestion'
        BEGIN
            DECLARE @StopEventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            UPDATE [OP].[tblEventQuestion] SET StatusCode = 'stopped', StoppedAtUtc = @Now, ClockPaused = 0, ClockLeftMs = NULL WHERE id = @StopEventQuestionID AND EventID = @EventID;

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

            IF @RawsMode = 'team'
            BEGIN
                DECLARE @P_alap DECIMAL(12,4) = CASE @TypeCode WHEN 'single' THEN 80 WHEN 'multi' THEN 90 WHEN 'order' THEN 100 WHEN 'match' THEN 100 WHEN 'category' THEN 110 WHEN 'freetext' THEN 120 ELSE 80 END;

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
            ELSE IF @RawsMode = 'fastest'
            BEGIN
                SELECT TeamID, MIN(ElapsedMs) AS MinElapsedMs
                INTO #FastestTeams
                FROM #LatestAnswers
                WHERE TeamID IS NOT NULL AND Ratio = 1.0
                GROUP BY TeamID;

                INSERT INTO [OP].[tblQuestionScore] (EventQuestionID, TeamID, RawS, C, W, SpeedT)
                SELECT @StopEventQuestionID, TeamID, (100000 - MinElapsedMs), 1, 0, (MinElapsedMs / 1000.0)
                FROM #FastestTeams;
            END

            IF @FGivenMode = 'after_question' AND @FPointMode = 'fixed'
            BEGIN
                SELECT TeamID, ROW_NUMBER() OVER (ORDER BY RawS DESC) AS Rnk
                INTO #QuestionWinners
                FROM [OP].[tblQuestionScore]
                WHERE EventQuestionID = @StopEventQuestionID AND RawS > 0;

                MERGE INTO [OP].[tblRoundScore] AS target
                USING (
                    SELECT qw.TeamID, f.Points
                    FROM #QuestionWinners qw
                    JOIN [OP].[tblRoundTypeFixedPoints] f ON f.RoundTypeID = @RoundTypeID AND f.RankPlace = qw.Rnk
                ) AS source
                ON target.RoundID = @SQ_RoundID AND target.TeamID = source.TeamID
                WHEN MATCHED THEN
                    UPDATE SET F = target.F + source.Points
                WHEN NOT MATCHED THEN
                    INSERT (RoundID, TeamID, RawSSum, Place, F)
                    VALUES (@SQ_RoundID, source.TeamID, 0, 1, source.Points);
            END

            DECLARE @StPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @StPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @StPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @StPing);
        END
        ELSE IF @Action = N'Op.CloseRound'
        BEGIN
            DECLARE @CR_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            
            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND StatusCode != 'stopped' AND ActiveFlg = 1)
            BEGIN
                THROW 50035, N'Még van nyitott vagy indítatlan kérdés a fordulóban!', 1;
            END

            DECLARE @CR_FGivenMode VARCHAR(20), @CR_FPointMode VARCHAR(20), @CR_RoundTypeID INT;
            SELECT @CR_FGivenMode = rt.FGivenMode, @CR_FPointMode = rt.FPointMode, @CR_RoundTypeID = rt.id
            FROM [OP].[tblRound] r JOIN [OP].[tblRoundType] rt ON r.RoundTypeID = rt.id WHERE r.id = @CR_RoundID;

            IF @CR_FGivenMode = 'after_round'
            BEGIN
                DECLARE @N INT = (SELECT COUNT(*) FROM [OP].[tblTeam] WHERE EventID = @EventID AND ActiveFlg = 1);
                IF @N = 0 SET @N = 1;
                
                SELECT t.id AS TeamID, ISNULL(SUM(qs.RawS), 0) AS RawSSum, RANK() OVER (ORDER BY ISNULL(SUM(qs.RawS), 0) DESC) AS Place
                INTO #CR_TeamScores
                FROM [OP].[tblTeam] t
                LEFT JOIN [OP].[tblQuestionScore] qs ON t.id = qs.TeamID AND qs.EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND ActiveFlg = 1)
                WHERE t.EventID = @EventID AND t.ActiveFlg = 1
                GROUP BY t.id;
                
                DELETE FROM [OP].[tblRoundScore] WHERE RoundID = @CR_RoundID;
                
                IF @CR_FPointMode = 'dynamic'
                BEGIN
                    DECLARE @P_max FLOAT = 100.0;
                    DECLARE @P_min FLOAT = CASE WHEN @N <= 5 THEN 50.0 WHEN @N <= 10 THEN 40.0 WHEN @N <= 20 THEN 30.0 ELSE 20.0 END;
                    
                    INSERT INTO [OP].[tblRoundScore] (RoundID, TeamID, RawSSum, Place, F)
                    SELECT @CR_RoundID, TeamID, RawSSum, Place,
                        CASE WHEN @N = 1 THEN @P_max ELSE ROUND(@P_min + (@P_max - @P_min) * CAST((@N - Place) AS FLOAT) / CAST((@N - 1) AS FLOAT), 0) END AS F
                    FROM #CR_TeamScores;

                    -- Shadow scores dynamic F point calculation
                    SELECT eu.id AS EventUserID, ISNULL(SUM(ss.S), 0) AS RawSSum, RANK() OVER (ORDER BY ISNULL(SUM(ss.S), 0) DESC) AS Place
                    INTO #CR_ShadowScores
                    FROM [EJ].[tblEventUser] eu
                    LEFT JOIN [OP].[tblShadowScore] ss ON eu.id = ss.EventUserID AND ss.EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND ActiveFlg = 1)
                    WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1
                    GROUP BY eu.id;

                    DECLARE @M INT = (SELECT COUNT(*) FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND ActiveFlg = 1);
                    IF @M = 0 SET @M = 1;
                    DECLARE @SP_min FLOAT = CASE WHEN @M <= 5 THEN 50.0 WHEN @M <= 10 THEN 40.0 WHEN @M <= 20 THEN 30.0 ELSE 20.0 END;

                    DELETE FROM [OP].[tblShadowRoundScore] WHERE RoundID = @CR_RoundID;
                    INSERT INTO [OP].[tblShadowRoundScore] (RoundID, EventUserID, RawSSum, Place, F)
                    SELECT @CR_RoundID, EventUserID, RawSSum, Place,
                        CASE WHEN @M = 1 THEN @P_max ELSE ROUND(@SP_min + (@P_max - @SP_min) * CAST((@M - Place) AS FLOAT) / CAST((@M - 1) AS FLOAT), 0) END AS F
                    FROM #CR_ShadowScores;
                END
                ELSE IF @CR_FPointMode = 'fixed'
                BEGIN
                    INSERT INTO [OP].[tblRoundScore] (RoundID, TeamID, RawSSum, Place, F)
                    SELECT @CR_RoundID, rs.TeamID, rs.RawSSum, rs.Place, ISNULL(fp.Points, 0)
                    FROM #CR_TeamScores rs
                    LEFT JOIN [OP].[tblRoundTypeFixedPoints] fp ON fp.RoundTypeID = @CR_RoundTypeID AND fp.RankPlace = rs.Place;
                END
            END
            
            DECLARE @ClosedStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'closed');
            UPDATE [OP].[tblRound] SET RoundStatusID = @ClosedStatusID WHERE id = @CR_RoundID AND EventID = @EventID;
            
            DECLARE @CRPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @CRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @CRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @CRPing);
        END
        ELSE IF @Action = N'Op.PublishRound'
        BEGIN
            DECLARE @PR_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            DECLARE @PubStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'published');
            UPDATE [OP].[tblRound] SET RoundStatusID = @PubStatusID WHERE id = @PR_RoundID AND EventID = @EventID;
            
            DECLARE @PRPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @PRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @PRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @PRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @PRPing);
        END
        ELSE IF @Action = N'Op.SubmitAnswer'
        BEGIN
            DECLARE @SUB_EventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            DECLARE @SUB_ElapsedMs INT = JSON_VALUE(@Json, '$.Payload.ElapsedMs');
            
            IF NOT EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @SUB_EventQuestionID AND EventID = @EventID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50032, N'A kérdés már le van zárva vagy nem is aktív!', 1;
            END

            DECLARE @MyEventUserID2 BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            IF @MyEventUserID2 IS NULL THROW 50033, N'Nem vagy bejelentkezve az eseményre!', 1;

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
            IF @Ratio IS NULL
            BEGIN
                SET @Ratio = CASE WHEN @CorrectFlg = 1 THEN 1.0 ELSE 0.0 END;
            END
            UPDATE [OP].[tblAnswer] SET CorrectFlg = @CorrectFlg, Ratio = @Ratio WHERE id = @AnsId;

            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres válaszadás' AS ReturnDescription;
            RETURN;
        END
        ELSE IF @Action = N'Op.AdjustTeam'
        BEGIN
            DECLARE @ADJ_TeamID INT = JSON_VALUE(@Json, '$.Payload.TeamID');
            DECLARE @PenaltyTypeCode VARCHAR(50) = JSON_VALUE(@Json, '$.Payload.PenaltyTypeCode');
            
            DECLARE @ADJ_Points INT = JSON_VALUE(@Json, '$.Payload.Points');
            IF @ADJ_Points IS NULL
            BEGIN
                SET @ADJ_Points = (SELECT DefaultPoints FROM [OP].[tblPenaltyType] WHERE Code = @PenaltyTypeCode);
                IF @ADJ_Points IS NULL SET @ADJ_Points = 0;
            END
            
            DECLARE @PenaltyTypeID INT = (SELECT id FROM [OP].[tblPenaltyType] WHERE Code = @PenaltyTypeCode);

            DECLARE @ADJ_EventUser BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            INSERT INTO [OP].[tblPenalty] (EventID, TeamID, Points, PenaltyTypeID, EventUserID, LastCreatedUserID)
            VALUES (@EventID, @ADJ_TeamID, @ADJ_Points, @PenaltyTypeID, @ADJ_EventUser, @UserID);

            DECLARE @ADJPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_qm', @Action, @ADJPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @ADJPing);
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
                INSERT INTO [OP].[tblTeamMember] (TeamID, EventUserID, ActiveFlg) VALUES (@JT_TeamID, @JT_EventUserID, 1);
            END
            ELSE
            BEGIN
                UPDATE [OP].[tblTeamMember] SET ActiveFlg = 1 WHERE TeamID = @JT_TeamID AND EventUserID = @JT_EventUserID;
            END

            DECLARE @JTPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @JTPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @JTPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @JTPing);
        END
        ELSE IF @Action = N'Op.ResetRound'
        BEGIN
            DECLARE @ResetRoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            
            DELETE FROM [OP].[tblAnswerItem] WHERE AnswerID IN (SELECT id FROM [OP].[tblAnswer] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID));
            DELETE FROM [OP].[tblAnswer] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID);
            DELETE FROM [OP].[tblQuestionScore] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID);
            DELETE FROM [OP].[tblShadowScore] WHERE EventQuestionID IN (SELECT id FROM [OP].[tblEventQuestion] WHERE RoundID = @ResetRoundID);
            DELETE FROM [OP].[tblRoundScore] WHERE RoundID = @ResetRoundID;
            DELETE FROM [OP].[tblShadowRoundScore] WHERE RoundID = @ResetRoundID;
            
            UPDATE [OP].[tblEventQuestion] SET StatusCode = 'pending', StartedAtUtc = NULL, StoppedAtUtc = NULL, ClockPaused = 0, ClockLeftMs = NULL WHERE RoundID = @ResetRoundID;
            
            DECLARE @PendingStID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'pending');
            UPDATE [OP].[tblRound] SET RoundStatusID = @PendingStID, FocusedEventQuestionID = NULL WHERE id = @ResetRoundID AND EventID = @EventID;
            
            DECLARE @RRPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @RRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @RRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @RRPing);
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

            DECLARE @LTPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @LTPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @LTPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @LTPing);
        END
        ELSE IF @Action = N'Op.React'
        BEGIN
            DECLARE @Glyph NVARCHAR(16) = JSON_VALUE(@Json, '$.Payload.Glyph');
            DECLARE @ReactPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, @Glyph AS Glyph FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @ReactPing);
            
            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;
            SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
            RETURN;
        END
        ELSE
        BEGIN
            DECLARE @Err NVARCHAR(200) = N'Ismeretlen Olimpub Action: ' + ISNULL(@Action, ''); THROW 50040, @Err, 1;
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




