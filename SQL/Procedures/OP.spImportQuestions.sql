SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spImportQuestions]
    @Json NVARCHAR(MAX),
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;
                DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');

        IF @EventID IS NULL
        BEGIN
            THROW 50010, 'A JSON-ben nincs megadva az EventID, nem lehet a fordulót létrehozni!', 1;
        END

        -- 1. JSON beolvasása egy temp táblába (Flat struktúra Excel-ből)
        CREATE TABLE #IncomingQuestions (
              TempId INT IDENTITY(1,1) PRIMARY KEY,
            RowIndex INT,
            TopicName NVARCHAR(120),
            TypeCode NVARCHAR(16),
            Prompt NVARCHAR(MAX),
            TimeSec INT,
            MediaUrl NVARCHAR(1000),
            
            Answer1 NVARCHAR(500), IsCorrect1 BIT, Match1 NVARCHAR(500),
            Answer2 NVARCHAR(500), IsCorrect2 BIT, Match2 NVARCHAR(500),
            Answer3 NVARCHAR(500), IsCorrect3 BIT, Match3 NVARCHAR(500),
            Answer4 NVARCHAR(500), IsCorrect4 BIT, Match4 NVARCHAR(500),
            Answer5 NVARCHAR(500), IsCorrect5 BIT, Match5 NVARCHAR(500),
            Answer6 NVARCHAR(500), IsCorrect6 BIT, Match6 NVARCHAR(500),
            Answer7 NVARCHAR(500), IsCorrect7 BIT, Match7 NVARCHAR(500),
            Answer8 NVARCHAR(500), IsCorrect8 BIT, Match8 NVARCHAR(500),

            TopicID INT,
            QuestionTypeID INT,
            NewQuestionID INT
        );

        INSERT INTO #IncomingQuestions (
            RowIndex, TopicName, TypeCode, Prompt, TimeSec, MediaUrl,
            Answer1, IsCorrect1, Match1, Answer2, IsCorrect2, Match2,
            Answer3, IsCorrect3, Match3, Answer4, IsCorrect4, Match4,
            Answer5, IsCorrect5, Match5, Answer6, IsCorrect6, Match6,
            Answer7, IsCorrect7, Match7, Answer8, IsCorrect8, Match8
        )
        SELECT 
            RowIndex, LTRIM(RTRIM(TopicName)), LOWER(LTRIM(RTRIM(TypeCode))), Prompt, TimeSec, MediaUrl,
            COALESCE(Answer1, Valasz1, Helyes), ISNULL(COALESCE(IsCorrect1, Helyes1), 0), COALESCE(Match1, Par1),
            COALESCE(Answer2, Valasz2), ISNULL(COALESCE(IsCorrect2, Helyes2), 0), COALESCE(Match2, Par2),
            COALESCE(Answer3, Valasz3), ISNULL(COALESCE(IsCorrect3, Helyes3), 0), COALESCE(Match3, Par3),
            COALESCE(Answer4, Valasz4), ISNULL(COALESCE(IsCorrect4, Helyes4), 0), COALESCE(Match4, Par4),
            COALESCE(Answer5, Valasz5), ISNULL(COALESCE(IsCorrect5, Helyes5), 0), COALESCE(Match5, Par5),
            COALESCE(Answer6, Valasz6), ISNULL(COALESCE(IsCorrect6, Helyes6), 0), COALESCE(Match6, Par6),
            COALESCE(Answer7, Valasz7), ISNULL(COALESCE(IsCorrect7, Helyes7), 0), COALESCE(Match7, Par7),
            COALESCE(Answer8, Valasz8), ISNULL(COALESCE(IsCorrect8, Helyes8), 0), COALESCE(Match8, Par8)
        FROM OPENJSON(@Json, '$.Questions')
        WITH (
            RowIndex INT '$.SortIndex', 
            TopicName NVARCHAR(120) '$.Topic', 
            TypeCode NVARCHAR(16) '$.TypeCode', 
            Prompt NVARCHAR(MAX) '$.Prompt', 
            TimeSec INT '$.TimeSec', 
            MediaUrl NVARCHAR(1000) '$.MediaUrl',
            
            Answer1 NVARCHAR(500) '$.Answer1', IsCorrect1 BIT '$.IsCorrect1', Match1 NVARCHAR(500) '$.Match1',
            Answer2 NVARCHAR(500) '$.Answer2', IsCorrect2 BIT '$.IsCorrect2', Match2 NVARCHAR(500) '$.Match2',
            Answer3 NVARCHAR(500) '$.Answer3', IsCorrect3 BIT '$.IsCorrect3', Match3 NVARCHAR(500) '$.Match3',
            Answer4 NVARCHAR(500) '$.Answer4', IsCorrect4 BIT '$.IsCorrect4', Match4 NVARCHAR(500) '$.Match4',
            Answer5 NVARCHAR(500) '$.Answer5', IsCorrect5 BIT '$.IsCorrect5', Match5 NVARCHAR(500) '$.Match5',
            Answer6 NVARCHAR(500) '$.Answer6', IsCorrect6 BIT '$.IsCorrect6', Match6 NVARCHAR(500) '$.Match6',
            Answer7 NVARCHAR(500) '$.Answer7', IsCorrect7 BIT '$.IsCorrect7', Match7 NVARCHAR(500) '$.Match7',
            Answer8 NVARCHAR(500) '$.Answer8', IsCorrect8 BIT '$.IsCorrect8', Match8 NVARCHAR(500) '$.Match8',
            
            Helyes NVARCHAR(500) '$.Helyes',
            Helyes1 BIT '$.Helyes1', Valasz1 NVARCHAR(500) '$."Válasz1"', Par1 NVARCHAR(500) '$."Pár1"',
            Helyes2 BIT '$.Helyes2', Valasz2 NVARCHAR(500) '$."Válasz2"', Par2 NVARCHAR(500) '$."Pár2"',
            Helyes3 BIT '$.Helyes3', Valasz3 NVARCHAR(500) '$."Válasz3"', Par3 NVARCHAR(500) '$."Pár3"',
            Helyes4 BIT '$.Helyes4', Valasz4 NVARCHAR(500) '$."Válasz4"', Par4 NVARCHAR(500) '$."Pár4"',
            Helyes5 BIT '$.Helyes5', Valasz5 NVARCHAR(500) '$."Válasz5"', Par5 NVARCHAR(500) '$."Pár5"',
            Helyes6 BIT '$.Helyes6', Valasz6 NVARCHAR(500) '$."Válasz6"', Par6 NVARCHAR(500) '$."Pár6"',
            Helyes7 BIT '$.Helyes7', Valasz7 NVARCHAR(500) '$."Válasz7"', Par7 NVARCHAR(500) '$."Pár7"',
            Helyes8 BIT '$.Helyes8', Valasz8 NVARCHAR(500) '$."Válasz8"', Par8 NVARCHAR(500) '$."Pár8"'
        );

        -- 2. Témakörök (Topics) szinkronizálása
        INSERT INTO [OP].[tblTopic] (Name, ActiveFlg)
        SELECT DISTINCT i.TopicName, 1
        FROM #IncomingQuestions i
        WHERE i.TopicName IS NOT NULL 
          AND NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] t WHERE t.Name = i.TopicName);

        UPDATE i
        SET i.TopicID = t.id
        FROM #IncomingQuestions i
        JOIN [OP].[tblTopic] t ON i.TopicName = t.Name;

        -- 3. Kérdéstípusok azonosítása
        UPDATE i
        SET i.QuestionTypeID = qt.id
        FROM #IncomingQuestions i
        JOIN [OP].[tblQuestionType] qt ON i.TypeCode = qt.Code;

        IF EXISTS (SELECT 1 FROM #IncomingQuestions WHERE QuestionTypeID IS NULL)
        BEGIN
            DECLARE @MissingTypes NVARCHAR(MAX);
            SELECT @MissingTypes = STRING_AGG(TypeCode, ', ') FROM (SELECT DISTINCT TypeCode FROM #IncomingQuestions WHERE QuestionTypeID IS NULL) t;
            DECLARE @ErrMsg NVARCHAR(2048) = N'Ismeretlen kérdéstípus kód(ok): ' + ISNULL(@MissingTypes, 'ismeretlen'); THROW 50020, @ErrMsg, 1;
        END

        -- 4. Kérdések beszúrása
        DECLARE @InsertedQuestions TABLE (TempId INT, InsertedID INT);
        
        MERGE INTO [OP].[tblQuestion] AS target
        USING #IncomingQuestions AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (TopicID, QuestionTypeID, Prompt, TimeSec, MediaUrl, ActiveFlg, CreatedAtUtc, LastCreatedUserID)
            VALUES (source.TopicID, source.QuestionTypeID, source.Prompt, ISNULL(source.TimeSec, 0), source.MediaUrl, 1, @Now, @UserID)
        OUTPUT source.TempId, inserted.id INTO @InsertedQuestions;

        UPDATE i
        SET i.NewQuestionID = q.InsertedID
        FROM #IncomingQuestions i
        JOIN @InsertedQuestions q ON i.TempId = q.TempId;

        -- 5. Opciók és helyes válaszok feldolgozása

        -- TEMP TÁBLA az opcióknak, hogy egyszerűbben tudjuk a CORRECT ANSWER táblát tölteni
        CREATE TABLE #TempOptions (
            QuestionID INT,
            TypeCode NVARCHAR(16),
            SlotIndex INT,
            AnswerText NVARCHAR(500),
            MatchText NVARCHAR(500),
            IsCorrect BIT,
            InsertedOptionID INT,       -- Az AnswerText beszúrt ID-ja
            InsertedMatchOptionID INT   -- A MatchText beszúrt ID-ja (párosításnál)
        );

        -- Unpivot: Kiterítjük a 8 slotot sorokra
        INSERT INTO #TempOptions (QuestionID, TypeCode, SlotIndex, AnswerText, MatchText, IsCorrect)
        SELECT NewQuestionID, TypeCode, 1, Answer1, Match1, IsCorrect1 FROM #IncomingQuestions WHERE Answer1 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 2, Answer2, Match2, IsCorrect2 FROM #IncomingQuestions WHERE Answer2 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 3, Answer3, Match3, IsCorrect3 FROM #IncomingQuestions WHERE Answer3 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 4, Answer4, Match4, IsCorrect4 FROM #IncomingQuestions WHERE Answer4 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 5, Answer5, Match5, IsCorrect5 FROM #IncomingQuestions WHERE Answer5 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 6, Answer6, Match6, IsCorrect6 FROM #IncomingQuestions WHERE Answer6 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 7, Answer7, Match7, IsCorrect7 FROM #IncomingQuestions WHERE Answer7 IS NOT NULL
        UNION ALL SELECT NewQuestionID, TypeCode, 8, Answer8, Match8, IsCorrect8 FROM #IncomingQuestions WHERE Answer8 IS NOT NULL;

        -- 5.1 FREETEXT kezelése
        -- Szabad szövegesnél nincsenek opciók, az Answer1-ben vannak a szinonimák
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, TextValue)
        SELECT QuestionID, AnswerText
        FROM #TempOptions
        WHERE TypeCode = 'freetext' AND SlotIndex = 1;

        -- Töröljük a freetext-et a tempből, hogy a többit rendesen opcióként kezeljük
        DELETE FROM #TempOptions WHERE TypeCode = 'freetext';

        -- 5.2 BAL OLDALI / FŐ OPCIÓK BESZÚRÁSA (tblQuestionOption)
        DECLARE @InsertedOpts TABLE (SlotIndex INT, QuestionID INT, InsertedID INT);
        
        MERGE INTO [OP].[tblQuestionOption] AS target
        USING #TempOptions AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (QuestionID, ListType, Value, SortIndex)
            VALUES (
                source.QuestionID, 
                CASE WHEN source.TypeCode IN ('match', 'category') THEN 'left' ELSE 'options' END, 
                source.AnswerText, 
                source.SlotIndex
            )
        OUTPUT source.SlotIndex, source.QuestionID, inserted.id INTO @InsertedOpts;

        UPDATE t
        SET t.InsertedOptionID = i.InsertedID
        FROM #TempOptions t
        JOIN @InsertedOpts i ON t.QuestionID = i.QuestionID AND t.SlotIndex = i.SlotIndex;

        -- 5.3 JOBB OLDALI OPCIÓK BESZÚRÁSA (csak MATCH esetén)
        DECLARE @InsertedMatchOpts TABLE (SlotIndex INT, QuestionID INT, InsertedID INT);

        MERGE INTO [OP].[tblQuestionOption] AS target
        USING (SELECT * FROM #TempOptions WHERE TypeCode IN ('match', 'category') AND MatchText IS NOT NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (QuestionID, ListType, Value, SortIndex)
            VALUES (source.QuestionID, 'right', source.MatchText, source.SlotIndex)
        OUTPUT source.SlotIndex, source.QuestionID, inserted.id INTO @InsertedMatchOpts;

        UPDATE t
        SET t.InsertedMatchOptionID = i.InsertedID
        FROM #TempOptions t
        JOIN @InsertedMatchOpts i ON t.QuestionID = i.QuestionID AND t.SlotIndex = i.SlotIndex;

        -- 5.4 HELYES VÁLASZOK BEKÖTÉSE (tblQuestionCorrectAnswer)
        
        -- A) SINGLE / MULTI
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID)
        SELECT QuestionID, InsertedOptionID
        FROM #TempOptions
        WHERE TypeCode IN ('single', 'multi') AND IsCorrect = 1;

        -- B) ORDER (Sorrendezésnél a helyes sorrend maga a SlotIndex)
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID, SortIndex)
        SELECT QuestionID, InsertedOptionID, SlotIndex
        FROM #TempOptions
        WHERE TypeCode = 'order';

        -- C) MATCH (Párosításnál az OptionID-t kötjük a MatchOptionID-hoz)
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID, MatchOptionID)
        SELECT QuestionID, InsertedOptionID, InsertedMatchOptionID
        FROM #TempOptions
        WHERE TypeCode IN ('match', 'category');


        
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

        INSERT INTO [OP].[tblRound] (EventID, TopicID, Mode, RoundStatusID, SortIndex, ActiveFlg, LastCreatedUserID)
        OUTPUT inserted.TopicID, inserted.id INTO @CreatedRounds
        SELECT 
            @EventID, 
            TopicID, 
            'fixed', 
            @PendingStatusID, 
            @MaxSortIndex + ROW_NUMBER() OVER (ORDER BY MIN(TempId)), 
              1, @UserID
          FROM #IncomingQuestions
        WHERE TopicID IS NOT NULL
        GROUP BY TopicID;

        -- ==========================================
                -- ==========================================
                -- ==========================================
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
        INSERT INTO [OP].[tblEventQuestion] (EventID, RoundID, QuestionID, SortIndex, StatusCode, TimeSec, ActiveFlg, LastCreatedUserID)
        SELECT @EventID, RoundID, NewQuestionID, RN, 'pending', ISNULL(TimeSec, 30), 1, @UserID
        FROM RankedQuestions
        WHERE RN <= 8;


                  COMMIT TRANSACTION;
          
          DECLARE @FirstRoundID INT = (SELECT TOP 1 RoundID FROM @CreatedRounds);
          
          SELECT 
              1 AS ReturnValue, 
              N'Sikeres importálás (' + CAST((SELECT COUNT(*) FROM #IncomingQuestions) AS NVARCHAR(20)) + ' db kérdés).' AS ReturnDescription,
              @FirstRoundID AS RoundID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
