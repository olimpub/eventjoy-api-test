const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spChangeGame.sql', 'utf8');

const closeRoundLogic = `
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
`;

content = content.replace(
    /ELSE IF @Action = N'Op.ShowLeaderboard'/,
    closeRoundLogic.trim() + '\n        ELSE IF @Action = N\'Op.ShowLeaderboard\''
);

fs.writeFileSync('SQL\\Procedures\\OP.spChangeGame.sql', content, 'utf8');
