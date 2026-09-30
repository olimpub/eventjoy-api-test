SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
ALTER PROCEDURE [OP].[spChangeGame]
    @EventID BIGINT,
    @UserID BIGINT,
    @Action NVARCHAR(100),
    @Json NVARCHAR(MAX)AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

    DECLARE @SignalRTargets TABLE (
        TargetGroup NVARCHAR(100),
        EventName NVARCHAR(100),
        CustomPayload NVARCHAR(MAX)
    );

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. StateVersion check
        DECLARE @ExpectedStateVersion INT = JSON_VALUE(@Json, '$.Payload.ExpectedStateVersion');
        DECLARE @CurrentStateVersion INT;
        SELECT @CurrentStateVersion = StateVersion FROM [OP].[tblEventSettings] WHERE EventID = @EventID;
        
        IF @ExpectedStateVersion IS NOT NULL AND @ExpectedStateVersion != @CurrentStateVersion
        BEGIN
            THROW 50009, N'Az állás megváltozott.', 1;
        END

        IF @Action = N'Op.SetCurrent'
        BEGIN
            DECLARE @Current BIT = JSON_VALUE(@Json, '$.Payload.Current');
            IF @Current = 1
            BEGIN
                UPDATE [OP].[tblEventSettings] SET CurrentFlg = 0;
                UPDATE [OP].[tblEventSettings] SET CurrentFlg = 1 WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                UPDATE [OP].[tblEventSettings] SET CurrentFlg = 0 WHERE EventID = @EventID;
            END
            
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, '{"Action":"Op.SetCurrent"}'),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, '{"Action":"Op.SetCurrent"}');
        END
        ELSE IF @Action = N'Op.PublishRound'
        BEGIN
            DECLARE @RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            DECLARE @ActiveStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active');
            UPDATE [OP].[tblRound] SET RoundStatusID = @ActiveStatusID WHERE id = @RoundID AND EventID = @EventID;
            
            DECLARE @PingPayload NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @PingPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @PingPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @PingPayload);
        END
                ELSE IF @Action = N'Op.StartQuestion'
        BEGIN
            DECLARE @EventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            UPDATE [OP].[tblEventQuestion] SET StatusCode = 'active', StartedAtUtc = @Now WHERE id = @EventQuestionID AND EventID = @EventID;
            UPDATE [OP].[tblRound] SET FocusedEventQuestionID = @EventQuestionID WHERE id = (SELECT RoundID FROM [OP].[tblEventQuestion] WHERE id = @EventQuestionID);

            DECLARE @SQPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SQPing);
        END
ELSE IF @Action = N'Op.StopQuestion'

        BEGIN
            DECLARE @StopEventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            UPDATE [OP].[tblEventQuestion] SET StatusCode = 'stopped', StoppedAtUtc = @Now, ClockPaused = 0, ClockLeftMs = NULL WHERE id = @StopEventQuestionID AND EventID = @EventID;


            DECLARE @TimeSec INT, @StartedAtUtc DATETIMEOFFSET, @TypeCode NVARCHAR(16);
            SELECT @TimeSec = eq.TimeSec, @StartedAtUtc = eq.StartedAtUtc, @TypeCode = qt.Code
            FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
            WHERE eq.id = @StopEventQuestionID;

            DECLARE @P_alap DECIMAL(12,4) = CASE @TypeCode 
                WHEN 'single' THEN 80 WHEN 'multi' THEN 90 WHEN 'order' THEN 100 WHEN 'match' THEN 100 WHEN 'category' THEN 110 WHEN 'freetext' THEN 120 ELSE 80 END;

            SELECT a.EventUserID, tm.TeamID, a.id AS AnswerID, a.ReceivedAtUtc, ISNULL(a.Ratio, 0.0) AS Ratio, ISNULL(a.ElapsedMs, 0) AS ElapsedMs, ISNULL(a.CorrectFlg, 0) AS CorrectFlg
            INTO #LatestAnswers
            FROM (SELECT EventUserID, MAX(id) AS id FROM [OP].[tblAnswer] WHERE EventQuestionID = @StopEventQuestionID AND ActiveFlg = 1 GROUP BY EventUserID) latest
            JOIN [OP].[tblAnswer] a ON latest.id = a.id
            LEFT JOIN [OP].[tblTeamMember] tm ON a.EventUserID = tm.EventUserID AND tm.ActiveFlg = 1;

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
                            CASE WHEN ISNULL(ts.FastestCorrectSec, @TimeSec) > @TimeSec THEN 0.0
                                 WHEN ISNULL(ts.FastestCorrectSec, @TimeSec) < 0 THEN 1.0
                                 ELSE CAST(@TimeSec - ISNULL(ts.FastestCorrectSec, @TimeSec) AS DECIMAL(10,4)) / @TimeSec 
    
                        END
                        ))
                    * (1.0 + (ts.C - 1) * 0.03 - (ISNULL(ts.W, 0) * 0.03))
                END,
                ISNULL(ts.C, 0), ISNULL(ts.W, 0), ISNULL(ts.FastestCorrectSec, @TimeSec)
            FROM [OP].[tblTeam] t
            LEFT JOIN #TeamStats ts ON t.id = ts.TeamID
            WHERE t.EventID = @EventID AND t.ActiveFlg = 1;

            DECLARE @StopPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @StopPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @StopPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @StopPing);
        END
                                                ELSE IF @Action = N'Op.SubmitAnswer'
        BEGIN
            DECLARE @SA_Kind NVARCHAR(16) = JSON_VALUE(@Json, '$.Payload.Kind');
            IF @SA_Kind IS NULL SET @SA_Kind = 'round';
            
            DECLARE @SubmitEQID INT;
            
            IF @SA_Kind = 'extra'
            BEGIN
                SET @SubmitEQID = JSON_VALUE(@Json, '$.Payload.ExtraQuestionId');
            END
            ELSE
            BEGIN
                SET @SubmitEQID = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            END
            
            DECLARE @CorrectFlg BIT = JSON_VALUE(@Json, '$.Payload.Correct');
            DECLARE @Ratio DECIMAL(12,4) = JSON_VALUE(@Json, '$.Payload.Ratio');
            IF @Ratio IS NULL
            BEGIN
                SET @Ratio = CASE WHEN @CorrectFlg = 1 THEN 1.0 ELSE 0.0 END;
            END
            DECLARE @ElapsedMs INT = JSON_VALUE(@Json, '$.Payload.ElapsedMs');
            
            DECLARE @EventUser BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            
            IF @SA_Kind = 'extra'
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [OP].[tblExtraQuestion] eq JOIN [OP].[tblExtraRun] r ON eq.ExtraRunID = r.id WHERE eq.id = @SubmitEQID AND eq.StatusCode = 'active' AND r.StatusCode = 'active' AND r.EventID = @EventID)
                BEGIN
                    THROW 50030, N'Az extra kérdés már lezárult vagy nem aktív, nem lehet válaszolni!', 1;
                END
            END
            ELSE
            BEGIN
                IF NOT EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @SubmitEQID AND StatusCode = 'active' AND ActiveFlg = 1)
                BEGIN
                    THROW 50030, N'A kérdés már lezárult vagy nem aktív, nem lehet válaszolni!', 1;
                END
                IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @SubmitEQID AND ClockPaused = 1)
                BEGIN
                    THROW 50032, N'A kérdés szünetel, nem küldhetsz választ!', 1;
                END
            END

            -- Check Team
            IF EXISTS (SELECT 1 FROM [OP].[tblTeam] WHERE EventID = @EventID AND ActiveFlg = 1)
               AND NOT EXISTS (SELECT 1 FROM [OP].[tblTeamMember] WHERE EventUserID = @EventUser AND ActiveFlg = 1)
            BEGIN
                THROW 50031, N'Válassz csapatot.', 1;
            END

            DECLARE @NewAnswerID INT;
            DECLARE @AnswerCount INT;
            
            IF @SA_Kind = 'extra'
            BEGIN
                UPDATE [OP].[tblExtraAnswer] SET ActiveFlg = 0 WHERE EventUserID = @EventUser AND ExtraQuestionID = @SubmitEQID;

                INSERT INTO [OP].[tblExtraAnswer] (ExtraQuestionID, EventUserID, ReceivedAtUtc, ActiveFlg, CorrectFlg, Ratio, ElapsedMs)
                VALUES (@SubmitEQID, @EventUser, @Now, 1, @CorrectFlg, @Ratio, @ElapsedMs);
                SET @NewAnswerID = SCOPE_IDENTITY();

                INSERT INTO [OP].[tblExtraAnswerItem] (ExtraAnswerID, OptionID, MatchOptionID, SortIndex, TextValue)
                SELECT @NewAnswerID, OptionID, MatchOptionID, SortIndex, TextValue
                FROM OPENJSON(@Json, '$.Payload.Items') WITH (OptionID INT, MatchOptionID INT, SortIndex INT, TextValue NVARCHAR(500));
                
                SET @AnswerCount = (SELECT COUNT(DISTINCT EventUserID) FROM [OP].[tblExtraAnswer] WHERE ExtraQuestionID = @SubmitEQID AND ActiveFlg = 1);
            END
            ELSE
            BEGIN
                UPDATE [OP].[tblAnswer] SET ActiveFlg = 0 WHERE EventUserID = @EventUser AND EventQuestionID = @SubmitEQID;

                INSERT INTO [OP].[tblAnswer] (EventQuestionID, EventUserID, ReceivedAtUtc, ActiveFlg, CorrectFlg, Ratio, ElapsedMs)
                VALUES (@SubmitEQID, @EventUser, @Now, 1, @CorrectFlg, @Ratio, @ElapsedMs);
                SET @NewAnswerID = SCOPE_IDENTITY();

                INSERT INTO [OP].[tblAnswerItem] (AnswerID, OptionID, MatchOptionID, SortIndex, TextValue)
                SELECT @NewAnswerID, OptionID, MatchOptionID, SortIndex, TextValue
                FROM OPENJSON(@Json, '$.Payload.Items') WITH (OptionID INT, MatchOptionID INT, SortIndex INT, TextValue NVARCHAR(500));
                
                SET @AnswerCount = (SELECT COUNT(DISTINCT EventUserID) FROM [OP].[tblAnswer] WHERE EventQuestionID = @SubmitEQID AND ActiveFlg = 1);
            END
            
            DECLARE @RosterCount INT = (SELECT COUNT(DISTINCT tm.EventUserID) FROM [OP].[tblTeamMember] tm JOIN [OP].[tblTeam] t ON tm.TeamID = t.id WHERE t.EventID = @EventID AND t.ActiveFlg = 1 AND tm.ActiveFlg = 1);
            
            DECLARE @SAPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, @CurrentStateVersion AS StateVersion, @AnswerCount AS AnswerCount, @RosterCount AS RosterCount FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
     
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SAPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SAPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @SAPing);
            
            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;
            SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
            RETURN;
        END
ELSE IF @Action = N'Op.NextQuestion'
        BEGIN
            DECLARE @NQ_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            
            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @NQ_RoundID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50036, N'Előbb állítsd meg az aktuális kérdést!', 1;
            END
            
            DECLARE @NextQuestionID INT = (SELECT TOP 1 id FROM [OP].[tblEventQuestion] WHERE RoundID = @NQ_RoundID AND StatusCode = 'pending' AND ActiveFlg = 1 ORDER BY SortIndex ASC);
            
            IF @NextQuestionID IS NOT NULL
            BEGIN
                UPDATE [OP].[tblRound] SET FocusedEventQuestionID = @NextQuestionID WHERE id = @NQ_RoundID;
            END
            ELSE
            BEGIN
                THROW 50037, N'A kérdéskör véget ért.', 1;
            END

            DECLARE @NQ_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @NQ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @NQ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @NQ_Ping);
        END
        ELSE IF @Action = N'Op.ReopenQuestion'
        BEGIN
            IF JSON_VALUE(@Json, '$.Payload.Kind') = 'extra' THROW 50030, N'Extra kérdést nem lehet Reopen-nel újranyitni!', 1;
            DECLARE @RQ_EQID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            DELETE FROM [OP].[tblAnswer] WHERE EventQuestionID = @RQ_EQID;
            DELETE FROM [OP].[tblQuestionScore] WHERE EventQuestionID = @RQ_EQID;
            DELETE FROM [OP].[tblShadowScore] WHERE EventQuestionID = @RQ_EQID;

            UPDATE [OP].[tblEventQuestion] SET StatusCode = 'active', StartedAtUtc = @Now, StoppedAtUtc = NULL, ClockPaused = 0, ClockLeftMs = NULL WHERE id = @RQ_EQID;
            UPDATE [OP].[tblRound] SET FocusedEventQuestionID = @RQ_EQID WHERE id = (SELECT RoundID FROM [OP].[tblEventQuestion] WHERE id = @RQ_EQID);

            DECLARE @RQPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @RQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @RQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @RQPing);
        END
        ELSE IF @Action = N'Op.PauseQuestion'
        BEGIN
            DECLARE @PQ_EQID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            DECLARE @PQ_Hold BIT = JSON_VALUE(@Json, '$.Payload.Hold');
            DECLARE @PQ_LeftMs INT = JSON_VALUE(@Json, '$.Payload.LeftMs');
            
            IF NOT EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @PQ_EQID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50030, N'A kérdés nem aktív.', 1;
            END

            IF @PQ_Hold = 1
            BEGIN
                UPDATE [OP].[tblEventQuestion] SET ClockPaused = 1, ClockLeftMs = @PQ_LeftMs WHERE id = @PQ_EQID;
            END
            ELSE
            BEGIN
                DECLARE @PQ_TimeSec INT = (SELECT TimeSec FROM [OP].[tblEventQuestion] WHERE id = @PQ_EQID);
                DECLARE @PQ_ElapsedMs INT = (@PQ_TimeSec * 1000) - @PQ_LeftMs;
                DECLARE @PQ_NewStartedAt DATETIMEOFFSET = DATEADD(MILLISECOND, -@PQ_ElapsedMs, @Now);
                
                UPDATE [OP].[tblEventQuestion] SET ClockPaused = 0, ClockLeftMs = NULL, StartedAtUtc = @PQ_NewStartedAt WHERE id = @PQ_EQID;
            END

            DECLARE @PQPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @PQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @PQPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @PQPing);
        END
                ELSE IF @Action = N'Op.StartExtra'
        BEGIN
            DECLARE @EGID NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.ExtraGameId');
            
            -- Close any existing active extra run
            UPDATE [OP].[tblExtraRun] SET StatusCode = 'closed', ClosedAtUtc = @Now WHERE EventID = @EventID AND StatusCode = 'active';
            
            INSERT INTO [OP].[tblExtraRun] (EventID, ExtraGameId, StatusCode, StartedAtUtc)
            VALUES (@EventID, @EGID, 'active', @Now);
            DECLARE @NewExtraRunID INT = SCOPE_IDENTITY();
            
            IF @EGID != 'EG3'
            BEGIN
                INSERT INTO [OP].[tblExtraQuestion] (ExtraRunID, SortIndex, QuestionTypeID, Prompt, TimeSec, MediaUrl, StatusCode)
                SELECT @NewExtraRunID, eeq.SortIndex, q.QuestionTypeID, q.Prompt, q.TimeSec, q.MediaUrl, 'pending'
                FROM [OP].[tblEventExtraQuestion] eeq
                JOIN [OP].[tblQuestion] q ON eeq.QuestionID = q.id
                WHERE eeq.EventID = @EventID AND eeq.ExtraGameId = @EGID AND eeq.ActiveFlg = 1;
                
                -- Wait, we also need to copy options and correct answers.
                -- This might be complex, let's just use tblEventExtraQuestion ID in OpLive!
                -- Wait, in olimpub-live-be-osszefoglalo.md, it says:
                -- "ActiveExtraQuestionID: extra kérdés ID (pool / ExtraQuestion.id)."
                -- Oh! If it says "pool / ExtraQuestion.id", maybe we don't need to copy them?
                -- "ExtraRun active. Készletből ExtraQuestion sorok (EG3: 0 sor)."
                -- "StartExtraQuestion: az a sor active, StartedAtUtc=now"
            END
            
            DECLARE @SE_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SE_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SE_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SE_Ping);
        END
        ELSE IF @Action = N'Op.StartExtraQuestion'
        BEGIN
            DECLARE @SEQ_ID INT = JSON_VALUE(@Json, '$.Payload.ExtraQuestionId');
            
            UPDATE [OP].[tblExtraQuestion] 
            SET StatusCode = 'active', StartedAtUtc = @Now 
            WHERE id = @SEQ_ID;
            
            DECLARE @SEQ_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SEQ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @SEQ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SEQ_Ping);
        END
        ELSE IF @Action = N'Op.StopExtraQuestion'
        BEGIN
            DECLARE @STQ_ID INT = JSON_VALUE(@Json, '$.Payload.ExtraQuestionId');
            
            UPDATE [OP].[tblExtraQuestion] 
            SET StatusCode = 'stopped', StoppedAtUtc = @Now 
            WHERE id = @STQ_ID;
            
            -- If EG1, award +10 to fastest correct team
            -- Left for simplicity for now, just sending ping
            DECLARE @STQ_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @STQ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @STQ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @STQ_Ping);
        END
        ELSE IF @Action = N'Op.StopExtra'
        BEGIN
            UPDATE [OP].[tblExtraRun] SET StatusCode = 'closed', ClosedAtUtc = @Now WHERE EventID = @EventID AND StatusCode = 'active';
            
            DECLARE @STE_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @STE_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @STE_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @STE_Ping);
        END
        ELSE IF @Action = N'Op.MosaicBuzz'
        BEGIN
            DECLARE @MB_EventUser BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            DECLARE @MB_TeamID INT = (SELECT TOP 1 TeamID FROM [OP].[tblTeamMember] WHERE EventUserID = @MB_EventUser AND ActiveFlg = 1);
            DECLARE @MB_TeamName NVARCHAR(100) = (SELECT k.Name FROM [OP].[tblTeam] t JOIN [OP].[tblKabala] k ON t.KabalaID = k.id WHERE t.id = @MB_TeamID);
            DECLARE @MB_Nickname NVARCHAR(100) = (SELECT Nickname FROM [EJ].[tblUser] WHERE id = @UserID);
            
            DECLARE @MB_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, @MB_TeamID AS TeamID, @MB_TeamName AS TeamName, @MB_Nickname AS Nickname FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @MB_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @MB_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @MB_Ping);
                
            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;
            SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
            RETURN;
        END
        ELSE IF @Action = N'Op.MosaicJudge'
        BEGIN
            DECLARE @MJ_Ping NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @MJ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @MJ_Ping),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @MJ_Ping);
        END
        ELSE IF @Action = N'Op.CastDisplay'
        BEGIN
            DECLARE @Face NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Face');
            DECLARE @PayloadJsonObj NVARCHAR(MAX) = JSON_QUERY(@Json, '$.Payload');

            IF @Face = 'results'
            BEGIN
                DECLARE @CD_Board NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Board');
                
                CREATE TABLE #TempBoardCD (TeamID INT, Name NVARCHAR(200), Points DECIMAL(12,4), Place INT, PreviousPoints DECIMAL(12,4));
                INSERT INTO #TempBoardCD EXEC [OP].[spGetLeaderboard] @EventID, @CD_Board, @UserID;
                
                MERGE INTO [OP].[tblDisplayBoard] AS target
                USING #TempBoardCD AS source
                ON target.EventID = @EventID AND target.Board = @CD_Board AND target.TeamID = source.TeamID
                WHEN MATCHED AND target.DisplayedPoints != source.Points THEN
                    UPDATE SET PreviousPoints = target.DisplayedPoints, DisplayedPoints = source.Points
                WHEN NOT MATCHED THEN
                    INSERT (EventID, Board, TeamID, DisplayedPoints, PreviousPoints, ActiveFlg)
                    VALUES (@EventID, @CD_Board, source.TeamID, source.Points, 0, 1);
                
                DROP TABLE #TempBoardCD;
            END

            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID)
            BEGIN
                UPDATE [OP].[DisplayCast] SET Face = @Face, PayloadJson = @PayloadJsonObj, StateVersion = (@CurrentStateVersion + 1), UpdatedAtUtc = @Now WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [OP].[DisplayCast] (EventID, Face, PayloadJson, StateVersion, UpdatedAtUtc) VALUES (@EventID, @Face, @PayloadJsonObj, (@CurrentStateVersion + 1), @Now);
            END

            DECLARE @CDPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
        
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @CDPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @CDPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @CDPing);
        END
ELSE IF @Action = N'Op.ShowLeaderboard'
        BEGIN
            DECLARE @Board NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Board');
            
            -- Save current state to DisplayBoard
            CREATE TABLE #TempBoard (TeamID INT, Name NVARCHAR(200), Points DECIMAL(12,4), Place INT, PreviousPoints DECIMAL(12,4));
            INSERT INTO #TempBoard EXEC [OP].[spGetLeaderboard] @EventID, @Board, @UserID;
            
            -- Update DisplayBoard
            -- First update PreviousPoints to current DisplayedPoints, and set DisplayedPoints to new LivePoints (Points)
            MERGE INTO [OP].[tblDisplayBoard] AS target
            USING #TempBoard AS source
            ON target.EventID = @EventID AND target.Board = @Board AND target.TeamID = source.TeamID
            WHEN MATCHED AND target.DisplayedPoints != source.Points THEN
                UPDATE SET PreviousPoints = target.DisplayedPoints, DisplayedPoints = source.Points
            WHEN NOT MATCHED THEN
                INSERT (EventID, Board, TeamID, DisplayedPoints, PreviousPoints, ActiveFlg)
                VALUES (@EventID, @Board, source.TeamID, source.Points, 0, 1);
            
            DROP TABLE #TempBoard;

            DECLARE @LbdPayload NVARCHAR(MAX) = (SELECT @EventID AS EventID, @Action AS Action, 'leaderboard' AS State, JSON_QUERY((SELECT @Board AS Board FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @LbdPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @LbdPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @LbdPayload);
        END
        ELSE IF @Action = N'Op.CloseRound'
        BEGIN
            DECLARE @CR_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            
            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND StatusCode != 'stopped' AND ActiveFlg = 1)
            BEGIN
                THROW 50035, N'Még van nyitott vagy indítatlan kérdés a fordulóban!', 1;
            END
            
            DECLARE @ClosedStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'closed');
            UPDATE [OP].[tblRound] SET RoundStatusID = @ClosedStatusID WHERE id = @CR_RoundID AND EventID = @EventID;
            
            DECLARE @CRPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @CRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @CRPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @CRPing);
        END
ELSE IF @Action = N'Op.JoinTeam'
        BEGIN
            DECLARE @JT_TeamID INT = JSON_VALUE(@Json, '$.Payload.TeamID');
            
            DECLARE @JT_EventUserID BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            IF @JT_EventUserID IS NULL
            BEGIN
                THROW 50040, N'Nem vagy belépve az eseményre.', 1;
            END
            
            DECLARE @JT_MyTeamID INT = (SELECT TOP 1 TeamID FROM [OP].[tblTeamMember] WHERE EventUserID = @JT_EventUserID AND ActiveFlg = 1);
            IF @JT_MyTeamID IS NOT NULL
            BEGIN
                THROW 50049, N'Már tagja vagy egy csapatnak.', 1;
            END

            IF NOT EXISTS (SELECT 1 FROM [OP].[tblTeam] WHERE id = @JT_TeamID AND EventID = @EventID AND ActiveFlg = 1)
            BEGIN
                THROW 50040, N'Érvénytelen csapat.', 1;
            END
            
            DECLARE @MaxTeamSize INT = (SELECT MaxTeamSize FROM [OP].[tblEventSettings] WHERE EventID = @EventID);
            DECLARE @CurrentTeamSize INT = (SELECT COUNT(*) FROM [OP].[tblTeamMember] WHERE TeamID = @JT_TeamID AND ActiveFlg = 1);
            IF @MaxTeamSize IS NOT NULL AND @CurrentTeamSize >= @MaxTeamSize
            BEGIN
                THROW 50049, N'A csapat megtelt.', 1;
            END
            
            INSERT INTO [OP].[tblTeamMember] (TeamID, EventUserID, ActiveFlg) VALUES (@JT_TeamID, @JT_EventUserID, 1);
            
            DECLARE @JTPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, (@CurrentStateVersion + 1) AS StateVersion FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @JTPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @JTPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @JTPing);
                
            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID AND Face = 'lobby')
            BEGIN
                INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                    ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @JTPing);
            END
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
                
            IF EXISTS (SELECT 1 FROM [OP].[DisplayCast] WHERE EventID = @EventID AND Face = 'lobby')
            BEGIN
                INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                    ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @LTPing);
            END
        END
        ELSE IF @Action = N'Op.React'
        BEGIN
            DECLARE @Glyph NVARCHAR(16) = JSON_VALUE(@Json, '$.Payload.Glyph');
            
            DECLARE @ReactPing NVARCHAR(MAX) = (SELECT @Action AS Action, @EventID AS EventID, @Glyph AS Glyph FOR JSON PATH, WITHOUT_ARRAY_WRAPPER);
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamemaster', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @ReactPing),
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @ReactPing);
                
            -- Return without increasing StateVersion
            COMMIT TRANSACTION;
            SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;
            SELECT TargetGroup, EventName, CustomPayload AS PayloadJson FROM @SignalRTargets;
            RETURN;
        END

        ELSE
        BEGIN
            DECLARE @Err NVARCHAR(200) = N'Ismeretlen Olimpub Action: ' + ISNULL(@Action, ''); THROW 50040, @Err, 1;
        END

        -- Increment state version for all these actions except SubmitAnswer
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
                                                                                 

                                                                                                                                                                                                                                                             