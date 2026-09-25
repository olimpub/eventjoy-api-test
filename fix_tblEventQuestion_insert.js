const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

const updatedEventQuestionInsert = `        -- ==========================================
        -- 8. KÉRDÉSEK BEKÖTÉSE A FORDULÓKBA (tblEventQuestion, MAX 8 per forduló)
        -- ==========================================
        ;WITH RankedQuestions AS (
            SELECT 
                r.RoundID, 
                i.NewQuestionID, 
                i.TimeSec,
                ROW_NUMBER() OVER(PARTITION BY i.TopicID ORDER BY ISNULL(i.RowIndex, i.TempId)) AS RN
            FROM #IncomingQuestions i
            JOIN @CreatedRounds r ON i.TopicID = r.TopicID
            WHERE i.NewQuestionID IS NOT NULL
        )
        INSERT INTO [OP].[tblEventQuestion] (EventID, RoundID, QuestionID, SortIndex, StatusCode, TimeSec, ActiveFlg)
        SELECT @EventID, RoundID, NewQuestionID, RN, 'pending', ISNULL(TimeSec, 30), 1
        FROM RankedQuestions
        WHERE RN <= 8;`;

content = content.replace(/-- 8\. KÉRDÉSEK BEKÖTÉSE[\s\S]*?WHERE RN <= 8;/g, updatedEventQuestionInsert);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
