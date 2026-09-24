CREATE OR ALTER PROCEDURE [OP].[spSaveQuestion]
    @Json NVARCHAR(MAX),
    @UserID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);

    BEGIN TRY
        BEGIN TRANSACTION;
        
        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @EventQuestionID INT = JSON_VALUE(@Json, '$.EventQuestionID');
        DECLARE @QuestionID INT = JSON_VALUE(@Json, '$.QuestionID');
        
        -- 1. Validate Status
        DECLARE @StatusCode NVARCHAR(50);
        SELECT @StatusCode = StatusCode 
        FROM [OP].[tblEventQuestion] 
        WHERE id = @EventQuestionID AND EventID = @EventID AND QuestionID = @QuestionID;
        
        IF @StatusCode IS NULL
        BEGIN
            THROW 50010, 'A kérdés nem található ebben az eseményben.', 1;
        END
        
        IF @StatusCode != 'pending'
        BEGIN
            THROW 50010, 'A kérdés már lement vagy fut, nem szerkeszthető.', 1;
        END
        
        -- Parse flat fields into a temp table for easy reuse of the import logic
        CREATE TABLE #IncomingQuestions (
            NewQuestionID INT,
            TypeCode NVARCHAR(50),
            Prompt NVARCHAR(MAX),
            TimeSec INT,
            SortIndex INT,
            Answer1 NVARCHAR(MAX), Match1 NVARCHAR(MAX), IsCorrect1 BIT,
            Answer2 NVARCHAR(MAX), Match2 NVARCHAR(MAX), IsCorrect2 BIT,
            Answer3 NVARCHAR(MAX), Match3 NVARCHAR(MAX), IsCorrect3 BIT,
            Answer4 NVARCHAR(MAX), Match4 NVARCHAR(MAX), IsCorrect4 BIT,
            Answer5 NVARCHAR(MAX), Match5 NVARCHAR(MAX), IsCorrect5 BIT,
            Answer6 NVARCHAR(MAX), Match6 NVARCHAR(MAX), IsCorrect6 BIT,
            Answer7 NVARCHAR(MAX), Match7 NVARCHAR(MAX), IsCorrect7 BIT,
            Answer8 NVARCHAR(MAX), Match8 NVARCHAR(MAX), IsCorrect8 BIT
        );
        
        INSERT INTO #IncomingQuestions (
            NewQuestionID, TypeCode, Prompt, TimeSec, SortIndex,
            Answer1, Match1, IsCorrect1, Answer2, Match2, IsCorrect2,
            Answer3, Match3, IsCorrect3, Answer4, Match4, IsCorrect4,
            Answer5, Match5, IsCorrect5, Answer6, Match6, IsCorrect6,
            Answer7, Match7, IsCorrect7, Answer8, Match8, IsCorrect8
        )
        SELECT 
            @QuestionID, COALESCE(TypeCode, [Type]), Prompt, ISNULL(TimeSec, 0), SortIndex,
            Answer1, Match1, CAST(IsCorrect1 AS BIT), Answer2, Match2, CAST(IsCorrect2 AS BIT),
            Answer3, Match3, CAST(IsCorrect3 AS BIT), Answer4, Match4, CAST(IsCorrect4 AS BIT),
            Answer5, Match5, CAST(IsCorrect5 AS BIT), Answer6, Match6, CAST(IsCorrect6 AS BIT),
            Answer7, Match7, CAST(IsCorrect7 AS BIT), Answer8, Match8, CAST(IsCorrect8 AS BIT)
        FROM OPENJSON(@Json)
        WITH (
            TypeCode NVARCHAR(50) '$.TypeCode',
            [Type] NVARCHAR(50) '$.Type',
            Prompt NVARCHAR(MAX) '$.Prompt',
            TimeSec INT '$.TimeSec',
            SortIndex INT '$.SortIndex',
            Answer1 NVARCHAR(MAX) '$.Answer1', Match1 NVARCHAR(MAX) '$.Match1', IsCorrect1 BIT '$.IsCorrect1',
            Answer2 NVARCHAR(MAX) '$.Answer2', Match2 NVARCHAR(MAX) '$.Match2', IsCorrect2 BIT '$.IsCorrect2',
            Answer3 NVARCHAR(MAX) '$.Answer3', Match3 NVARCHAR(MAX) '$.Match3', IsCorrect3 BIT '$.IsCorrect3',
            Answer4 NVARCHAR(MAX) '$.Answer4', Match4 NVARCHAR(MAX) '$.Match4', IsCorrect4 BIT '$.IsCorrect4',
            Answer5 NVARCHAR(MAX) '$.Answer5', Match5 NVARCHAR(MAX) '$.Match5', IsCorrect5 BIT '$.IsCorrect5',
            Answer6 NVARCHAR(MAX) '$.Answer6', Match6 NVARCHAR(MAX) '$.Match6', IsCorrect6 BIT '$.IsCorrect6',
            Answer7 NVARCHAR(MAX) '$.Answer7', Match7 NVARCHAR(MAX) '$.Match7', IsCorrect7 BIT '$.IsCorrect7',
            Answer8 NVARCHAR(MAX) '$.Answer8', Match8 NVARCHAR(MAX) '$.Match8', IsCorrect8 BIT '$.IsCorrect8'
        );
        
        DECLARE @NewPrompt NVARCHAR(MAX) = (SELECT Prompt FROM #IncomingQuestions);
        DECLARE @NewTimeSec INT = (SELECT TimeSec FROM #IncomingQuestions);
        DECLARE @NewSortIndex INT = (SELECT SortIndex FROM #IncomingQuestions);
        
        -- 2. Update tblQuestion
        UPDATE [OP].[tblQuestion]
        SET Prompt = @NewPrompt,
            TimeSec = @NewTimeSec,
            LastCreatedUserID = @UserID
        WHERE id = @QuestionID;
        
        -- 3. Update tblEventQuestion
        UPDATE [OP].[tblEventQuestion]
        SET TimeSec = @NewTimeSec,
            SortIndex = ISNULL(@NewSortIndex, SortIndex),
            LastCreatedUserID = @UserID
        WHERE id = @EventQuestionID;
        
        -- 4. Delete Old Options & Correct Answers
        DELETE FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @QuestionID;
        DELETE FROM [OP].[tblQuestionOption] WHERE QuestionID = @QuestionID;
        
        -- 5. Reconstruct Options
        CREATE TABLE #TempOptions (
            QuestionID INT,
            TypeCode NVARCHAR(16),
            SlotIndex INT,
            AnswerText NVARCHAR(MAX),
            MatchText NVARCHAR(MAX),
            IsCorrect BIT,
            InsertedOptionID INT,       
            InsertedMatchOptionID INT   
        );

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
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, TextValue)
        SELECT QuestionID, AnswerText
        FROM #TempOptions
        WHERE TypeCode = 'freetext' AND SlotIndex = 1;

        DELETE FROM #TempOptions WHERE TypeCode = 'freetext';

        -- 5.2 BAL OLDALI / FŐ OPCIÓK BESZÚRÁSA
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

        -- 5.3 JOBB OLDALI OPCIÓK BESZÚRÁSA
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

        -- 5.4 HELYES VÁLASZOK BEKÖTÉSE
        
        -- A) SINGLE / MULTI / CATEGORY
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID)
        SELECT QuestionID, InsertedOptionID
        FROM #TempOptions
        WHERE TypeCode IN ('single', 'multi') AND IsCorrect = 1;

        -- B) ORDER
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID, SortIndex)
        SELECT QuestionID, InsertedOptionID, SlotIndex
        FROM #TempOptions
        WHERE TypeCode = 'order';

        -- C) MATCH
        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID, MatchOptionID)
        SELECT QuestionID, InsertedOptionID, InsertedMatchOptionID
        FROM #TempOptions
        WHERE TypeCode IN ('match', 'category');


        COMMIT TRANSACTION;
        SELECT 1 AS ReturnValue, N'Kérdés sikeresen mentve.' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
