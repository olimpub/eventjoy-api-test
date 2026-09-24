SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spChangeGame]
    @EventID BIGINT,
    @UserID BIGINT,
    @Action NVARCHAR(100),
    @Json NVARCHAR(MAX)
AS
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

        IF @Action = N'Op.PublishRound'
        BEGIN
            DECLARE @RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            DECLARE @ActiveStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'active');

            UPDATE [OP].[tblRound]
            SET RoundStatusID = @ActiveStatusID
            WHERE id = @RoundID AND EventID = @EventID;

            -- SignalR Gamer ping
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES (
                'event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, (SELECT @EventID AS EventID, @Action AS Action, 'idle' AS State, JSON_QUERY((SELECT @RoundID AS RoundID, 'active' AS Status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)
            ),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, (SELECT @EventID AS EventID, @Action AS Action, 'idle' AS State, JSON_QUERY((SELECT @RoundID AS RoundID, 'active' AS Status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, (SELECT @EventID AS EventID, @Action AS Action, 'idle' AS State, JSON_QUERY((SELECT @RoundID AS RoundID, 'active' AS Status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload FOR JSON PATH, WITHOUT_ARRAY_WRAPPER));
        END
        ELSE IF @Action = N'Op.StartQuestion'
        BEGIN
            DECLARE @EventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            
            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'active', StartedAtUtc = @Now
            WHERE id = @EventQuestionID AND EventID = @EventID;

            -- TODO: Ide jöhet a részletes kinyerése a kérdésnek (Prompt, Options, CorrectJson a résztvevőknek)
            -- Jelenleg csak küldünk egy State = 'question_active' pinget
            DECLARE @SQPayload NVARCHAR(MAX) = (
                SELECT @EventID AS EventID, @Action AS Action, 'question_active' AS State, 
                       JSON_QUERY((SELECT @EventQuestionID AS EventQuestionID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload 
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @SQPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SQPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @SQPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, @SQPayload);
        END
        ELSE IF @Action = N'Op.StopQuestion'
        BEGIN
            DECLARE @StopEventQuestionID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            
            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'stopped', StoppedAtUtc = @Now
            WHERE id = @StopEventQuestionID AND EventID = @EventID;

            
            -- IDE JÖN A 6. LÉPÉS: A PONTOZÁS
            DECLARE @TimeSec INT, @StartedAtUtc DATETIMEOFFSET, @TypeCode NVARCHAR(16);
            SELECT @TimeSec = eq.TimeSec, @StartedAtUtc = eq.StartedAtUtc, @TypeCode = qt.Code
            FROM [OP].[tblEventQuestion] eq
            JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
            JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
            WHERE eq.id = @StopEventQuestionID;

            DECLARE @P_alap DECIMAL(12,4) = 
                CASE @TypeCode 
                    WHEN 'single' THEN 80
                    WHEN 'multi' THEN 90
                    WHEN 'order' THEN 100
                    WHEN 'match' THEN 100
                    WHEN 'category' THEN 110
                    WHEN 'freetext' THEN 120
                    ELSE 80
                END;

            -- Kikeressük az összes aktív tag LATEST válaszát (AnswerID)
            SELECT 
                a.EventUserID,
                tm.TeamID,
                a.id AS AnswerID,
                a.ReceivedAtUtc,
                [OP].[fnCalculateAnswerRatio](a.id) AS Ratio
            INTO #LatestAnswers
            FROM (
                SELECT EventUserID, MAX(id) AS id 
                FROM [OP].[tblAnswer] 
                WHERE EventQuestionID = @StopEventQuestionID AND ActiveFlg = 1
                GROUP BY EventUserID
            ) latest
            JOIN [OP].[tblAnswer] a ON latest.id = a.id
            JOIN [OP].[tblTeamMember] tm ON a.EventUserID = tm.EventUserID AND tm.ActiveFlg = 1;

            -- ShadowScore kiszámítása minden felhasználónak
            INSERT INTO [OP].[tblShadowScore] (EventQuestionID, EventUserID, S)
            SELECT 
                @StopEventQuestionID,
                EventUserID,
                @P_alap * Ratio * (1.0 + 0.3 * (
                    CASE WHEN DATEDIFF(second, @StartedAtUtc, ReceivedAtUtc) > @TimeSec THEN 0
                         WHEN DATEDIFF(second, @StartedAtUtc, ReceivedAtUtc) < 0 THEN @TimeSec
                         ELSE CAST(@TimeSec - DATEDIFF(second, @StartedAtUtc, ReceivedAtUtc) AS DECIMAL(10,4)) / @TimeSec 
                    END))
            FROM #LatestAnswers;

            -- Team szintű aggregáció (C, W, t)
            SELECT 
                TeamID,
                SUM(CASE WHEN Ratio = 1.0 THEN 1 ELSE 0 END) AS C,
                SUM(CASE WHEN Ratio = 0.0 THEN 1 ELSE 0 END) AS W,
                MIN(CASE WHEN Ratio = 1.0 THEN DATEDIFF(second, @StartedAtUtc, ReceivedAtUtc) ELSE NULL END) AS FastestCorrectSec
            INTO #TeamStats
            FROM #LatestAnswers
            GROUP BY TeamID;

            -- Végleges QuestionScore beírása az ÖSSZES AKTÍV CSAPATNAK (akik nem válaszoltak, azoknak 0)
            INSERT INTO [OP].[tblQuestionScore] (EventQuestionID, TeamID, RawS, C, W, SpeedT)
            SELECT 
                @StopEventQuestionID,
                t.id,
                CASE 
                    WHEN ISNULL(ts.C, 0) = 0 THEN 0.0
                    ELSE 
                        @P_alap 
                        * (1.0 + 0.3 * (
                            CASE WHEN ISNULL(ts.FastestCorrectSec, @TimeSec) > @TimeSec THEN 0.0
                                 WHEN ISNULL(ts.FastestCorrectSec, @TimeSec) < 0 THEN 1.0
                                 ELSE CAST(@TimeSec - ISNULL(ts.FastestCorrectSec, @TimeSec) AS DECIMAL(10,4)) / @TimeSec 
                            END
                        ))
                        * (1.0 + (ts.C - 1) * 0.03 - (ISNULL(ts.W, 0) * 0.03))
                END,
                ISNULL(ts.C, 0),
                ISNULL(ts.W, 0),
                ISNULL(ts.FastestCorrectSec, @TimeSec)
            FROM [OP].[tblTeam] t
            LEFT JOIN #TeamStats ts ON t.id = ts.TeamID
            WHERE t.EventID = @EventID AND t.ActiveFlg = 1;

            DECLARE @StopPayload NVARCHAR(MAX) = (
                SELECT @EventID AS EventID, @Action AS Action, 'idle' AS State, 
                       JSON_QUERY((SELECT @StopEventQuestionID AS EventQuestionID, 'stopped' AS Status FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload 
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @StopPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @StopPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @StopPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, @StopPayload);
        END
        ELSE IF @Action = N'Op.SubmitAnswer'
        BEGIN
            -- Ezt a Játékos hívja meg!
            DECLARE @SubmitEQID INT = JSON_VALUE(@Json, '$.Payload.EventQuestionID');
            DECLARE @EventUserID BIGINT = (SELECT TOP 1 id FROM [EJ].[tblEventUser] WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1);
            
            -- Ellenőrizzük, hogy active-e még a kérdés
            IF NOT EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE id = @SubmitEQID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                THROW 50030, N'A kérdés már lezárult vagy nem aktív, nem lehet válaszolni!', 1;
            END

            -- Beszúrjuk az Answer rekordot
            DECLARE @NewAnswerID INT;
            INSERT INTO [OP].[tblAnswer] (EventQuestionID, EventUserID, ReceivedAtUtc, ActiveFlg)
            VALUES (@SubmitEQID, @EventUserID, @Now, 1);
            SET @NewAnswerID = SCOPE_IDENTITY();

            -- És beszúrjuk az Item-eket a JSON tömbből
            INSERT INTO [OP].[tblAnswerItem] (AnswerID, OptionID, MatchOptionID, SortIndex, TextValue)
            SELECT @NewAnswerID, OptionID, MatchOptionID, SortIndex, TextValue
            FROM OPENJSON(@Json, '$.Payload.Items')
            WITH (
                OptionID INT,
                MatchOptionID INT,
                SortIndex INT,
                TextValue NVARCHAR(500)
            );
            
            -- Erre nem küldünk SignalR-t, a kliens tudja, hogy sikeres.
        END
        ELSE IF @Action = N'Op.NextQuestion'
        BEGIN
            DECLARE @NQ_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            
            -- Ha van active kérdés, dobjunk hibát, hogy előbb állítsa le! 
            -- A specifikáció azt írja "implicit Stop, majd next", de mivel a Stop összetett és a Kvízmester úgyis egy gombot nyom,
            -- biztonságosabb, ha külön hívják a Stop-ot. Vagy implementáljuk a Stop logikát itt is?
            -- Nem, hívja meg magát vagy dobjunk hibát. Inkább csak kijelöljük a következőt.
            -- "Következő pending SortIndex StartQuestion."
            
            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @NQ_RoundID AND StatusCode = 'active' AND ActiveFlg = 1)
            BEGIN
                DECLARE @ErrNQ NVARCHAR(200) = N'Előbb állítsd meg az aktuális kérdést (StopQuestion)!'; THROW 50036, @ErrNQ, 1;
            END

            -- Keressük meg a legkisebb SortIndexű pending kérdést
            DECLARE @NextQuestionID INT = (
                SELECT TOP 1 id 
                FROM [OP].[tblEventQuestion] 
                WHERE RoundID = @NQ_RoundID AND StatusCode = 'pending' AND ActiveFlg = 1 
                ORDER BY SortIndex ASC
            );

            IF @NextQuestionID IS NULL
            BEGIN
                DECLARE @ErrNQEnd NVARCHAR(200) = N'A kérdéskör véget ért.'; THROW 50037, @ErrNQEnd, 1;
            END

            -- Startoljuk el az adott kérdést (mintha Op.StartQuestion lenne)
            UPDATE [OP].[tblEventQuestion]
            SET StatusCode = 'active', StartedAtUtc = @Now
            WHERE id = @NextQuestionID;

            DECLARE @NQPayload NVARCHAR(MAX) = (
                SELECT @EventID AS EventID, @Action AS Action, 'question_active' AS State, 
                       JSON_QUERY((SELECT @NextQuestionID AS EventQuestionID FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload 
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @NQPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @NQPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @NQPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, @NQPayload);
        END
        ELSE IF @Action = N'Op.CloseRound'
        BEGIN
            DECLARE @CR_RoundID INT = JSON_VALUE(@Json, '$.Payload.RoundID');
            
            -- Ellenőrizzük, hogy minden EventQuestion stopped-e
            IF EXISTS (SELECT 1 FROM [OP].[tblEventQuestion] WHERE RoundID = @CR_RoundID AND StatusCode != 'stopped' AND ActiveFlg = 1)
            BEGIN
                DECLARE @ErrCR NVARCHAR(200) = N'Még van nyitott vagy indítatlan kérdés a fordulóban!'; THROW 50035, @ErrCR, 1;
            END

            -- N = Active Team count
            DECLARE @N INT = (SELECT COUNT(*) FROM [OP].[tblTeam] WHERE EventID = @EventID AND ActiveFlg = 1);
            IF @N = 0 SET @N = 1; -- Biztonsági fallback osztás nullával elkerülésére

            DECLARE @P_max DECIMAL(12,4) = 100.0;
            DECLARE @P_min DECIMAL(12,4) = CASE 
                WHEN @N <= 5 THEN 50.0
                WHEN @N <= 10 THEN 40.0
                WHEN @N <= 20 THEN 30.0
                ELSE 20.0
            END;

            -- Team RawSSum
            SELECT 
                t.id AS TeamID,
                ISNULL(SUM(qs.RawS), 0.0) AS RawSSum,
                RANK() OVER (ORDER BY ISNULL(SUM(qs.RawS), 0.0) DESC) AS Place
            INTO #RoundRank
            FROM [OP].[tblTeam] t
            LEFT JOIN [OP].[tblEventQuestion] eq ON eq.RoundID = @CR_RoundID AND eq.ActiveFlg = 1
            LEFT JOIN [OP].[tblQuestionScore] qs ON qs.EventQuestionID = eq.id AND qs.TeamID = t.id
            WHERE t.EventID = @EventID AND t.ActiveFlg = 1
            GROUP BY t.id;

            -- Insert tblRoundScore
            INSERT INTO [OP].[tblRoundScore] (RoundID, TeamID, RawSSum, Place, F)
            SELECT 
                @CR_RoundID,
                TeamID,
                RawSSum,
                Place,
                CASE 
                    WHEN @N = 1 THEN @P_max
                    ELSE ROUND(@P_min + (@P_max - @P_min) * (CAST(@N - Place AS DECIMAL(12,4)) / CAST(@N - 1 AS DECIMAL(12,4))), 0)
                END
            FROM #RoundRank;

            -- Round Status -> closed
            DECLARE @ClosedStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'closed');
            UPDATE [OP].[tblRound] SET RoundStatusID = @ClosedStatusID WHERE id = @CR_RoundID AND EventID = @EventID;
            
            -- SignalR vagy return? CloseRoundnál csak státuszt frissítünk. (Leaderboardot a kliens ShowLeaderboarddal kéri le)
        END
        ELSE IF @Action = N'Op.ShowLeaderboard'
        BEGIN
            DECLARE @Board NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.Board');

            DECLARE @LbdPayload NVARCHAR(MAX) = (
                SELECT @EventID AS EventID, @Action AS Action, 'leaderboard' AS State, 
                       JSON_QUERY((SELECT @Board AS Board FOR JSON PATH, WITHOUT_ARRAY_WRAPPER)) AS Payload 
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES 
                ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @LbdPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @LbdPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @LbdPayload),
                ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, @LbdPayload);
        END
        ELSE
        BEGIN
            DECLARE @Err NVARCHAR(200) = N'Ismeretlen Olimpub Action: ' + ISNULL(@Action, ''); THROW 50040, @Err, 1;
        END

        COMMIT TRANSACTION;
        
        -- RS1: API response
        SELECT 1 AS ReturnValue, N'Sikeres művelet' AS ReturnDescription;

        -- RS2: SignalR Outbox a C# ServiceBus felé
        SELECT 
            TargetGroup,
            EventName,
            CustomPayload AS PayloadJson
        FROM @SignalRTargets;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
