const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spChangeGame.sql', 'utf8');

const scoringLogic = `
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
`;

content = content.replace(
    /-- IDE JÖN A 6\. LÉPÉS: A PONTOZÁS.*?(?=DECLARE @StopPayload)/s,
    scoringLogic + '\n            '
);

fs.writeFileSync('SQL\\Procedures\\OP.spChangeGame.sql', content, 'utf8');
