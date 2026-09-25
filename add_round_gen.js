const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

const eventLogic = `
        -- ==========================================
        -- 6. ESEMÉNY BEÁLLÍTÁSOK (Topics hozzáadása)
        -- ==========================================
        INSERT INTO [OP].[tblEventSettingTopic] (EventID, TopicID)
        SELECT DISTINCT @EventID, TopicID
        FROM #IncomingQuestions
        WHERE TopicID IS NOT NULL
          AND TopicID NOT IN (SELECT TopicID FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID);

        -- ==========================================
        -- 7. FORDULÓK (tblRound) LÉTREHOZÁSA TÉMAKÖRÖNKÉNT
        -- ==========================================
        DECLARE @PendingStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'pending');
        DECLARE @MaxSortIndex INT = ISNULL((SELECT MAX(SortIndex) FROM [OP].[tblRound] WHERE EventID = @EventID), 0);
        
        DECLARE @CreatedRounds TABLE (TopicID INT, RoundID INT);

        INSERT INTO [OP].[tblRound] (EventID, TopicID, Mode, RoundStatusID, SortIndex, ActiveFlg)
        OUTPUT inserted.TopicID, inserted.id INTO @CreatedRounds
        SELECT 
            @EventID, 
            TopicID, 
            'fixed', 
            @PendingStatusID, 
            @MaxSortIndex + ROW_NUMBER() OVER (ORDER BY MIN(TempId)), 
            1
        FROM #IncomingQuestions
        WHERE TopicID IS NOT NULL
        GROUP BY TopicID;

        -- ==========================================
        -- 8. KÉRDÉSEK BEKÖTÉSE A FORDULÓKBA (tblEventQuestion)
        -- ==========================================
        INSERT INTO [OP].[tblEventQuestion] (RoundID, QuestionID, SortIndex, ActiveFlg)
        SELECT 
            r.RoundID, 
            i.NewQuestionID, 
            ROW_NUMBER() OVER(PARTITION BY i.TopicID ORDER BY ISNULL(i.RowIndex, i.TempId)), 
            1
        FROM #IncomingQuestions i
        JOIN @CreatedRounds r ON i.TopicID = r.TopicID
        WHERE i.NewQuestionID IS NOT NULL;


        COMMIT TRANSACTION;`;

content = content.replace(/COMMIT TRANSACTION;/, eventLogic);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
