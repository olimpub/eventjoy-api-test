const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

const updatedEventQuestionInsert = `        -- ==========================================
        -- 8. KÉRDÉSEK BEKÖTÉSE A FORDULÓKBA (tblEventQuestion, MAX 8 per forduló)
        -- ==========================================
        ;WITH RankedQuestions AS (
            SELECT 
                r.RoundID, 
                i.NewQuestionID, 
                ROW_NUMBER() OVER(PARTITION BY i.TopicID ORDER BY ISNULL(i.RowIndex, i.TempId)) AS RN
            FROM #IncomingQuestions i
            JOIN @CreatedRounds r ON i.TopicID = r.TopicID
            WHERE i.NewQuestionID IS NOT NULL
        )
        INSERT INTO [OP].[tblEventQuestion] (RoundID, QuestionID, SortIndex, ActiveFlg)
        SELECT RoundID, NewQuestionID, RN, 1
        FROM RankedQuestions
        WHERE RN <= 8;`;

content = content.replace(/-- 8\. KÉRDÉSEK BEKÖTÉSE[\s\S]*?WHERE i\.NewQuestionID IS NOT NULL;/, updatedEventQuestionInsert);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
