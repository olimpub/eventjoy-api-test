const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spChangeGame.sql', 'utf8');

const nextQuestionLogic = `
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
                ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @NQPayload);
        END
`;

content = content.replace(
    /ELSE IF @Action = N'Op.CloseRound'/,
    nextQuestionLogic.trim() + '\n        ELSE IF @Action = N\'Op.CloseRound\''
);

fs.writeFileSync('SQL\\Procedures\\OP.spChangeGame.sql', content, 'utf8');
