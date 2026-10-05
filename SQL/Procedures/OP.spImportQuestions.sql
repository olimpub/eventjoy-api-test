-- =============================================
-- Author:		EventJoy
-- Create date: 
-- Description:	V2 Refactored Question Import
-- =============================================
CREATE OR ALTER PROCEDURE [OP].[spImportQuestions]
    @Json NVARCHAR(MAX),
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;

    BEGIN TRY
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        DECLARE @EventID BIGINT = JSON_VALUE(@Json, '$.EventID');

        IF @EventID IS NULL
        BEGIN
            THROW 50010, N'EventID hiányzik a JSON-ből.', 1;
        END

        IF NOT EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1)
        BEGIN
            THROW 50030, N'Nincs megfelelő jogosultságod (Szervező) a kérdések importálásához!', 1;
        END

        IF OBJECT_ID('tempdb..#IncomingQuestions') IS NOT NULL DROP TABLE #IncomingQuestions;

        SELECT 
            RowIndex,
            TopicName,
            TypeCode,
            Prompt,
            TimeSec,
            MediaUrl,
            RoundTypeCode,
            Answer1, IsCorrect1, Match1,
            Answer2, IsCorrect2, Match2,
            Answer3, IsCorrect3, Match3,
            Answer4, IsCorrect4, Match4,
            Answer5, IsCorrect5, Match5,
            Answer6, IsCorrect6, Match6,
            Answer7, IsCorrect7, Match7,
            Answer8, IsCorrect8, Match8,
            CAST(NULL AS INT) AS TopicID,
            CAST(NULL AS INT) AS QuestionTypeID,
            CAST(NULL AS INT) AS RoundTypeID,
            CAST(NULL AS INT) AS NewQuestionID,
            IDENTITY(INT, 1, 1) AS TempId
        INTO #IncomingQuestions
        FROM OPENJSON(@Json, '$.Questions')
        WITH (
            RowIndex INT '$.RowIndex',
            TopicName NVARCHAR(120) '$.TopicName',
            TypeCode NVARCHAR(16) '$.TypeCode',
            Prompt NVARCHAR(MAX) '$.Prompt',
            TimeSec INT '$.TimeSec',
            MediaUrl NVARCHAR(500) '$.MediaUrl',
            RoundTypeCode VARCHAR(50) '$.RoundTypeCode',
            Answer1 NVARCHAR(500) '$.Answer1', IsCorrect1 BIT '$.IsCorrect1', Match1 NVARCHAR(500) '$.Match1',
            Answer2 NVARCHAR(500) '$.Answer2', IsCorrect2 BIT '$.IsCorrect2', Match2 NVARCHAR(500) '$.Match2',
            Answer3 NVARCHAR(500) '$.Answer3', IsCorrect3 BIT '$.IsCorrect3', Match3 NVARCHAR(500) '$.Match3',
            Answer4 NVARCHAR(500) '$.Answer4', IsCorrect4 BIT '$.IsCorrect4', Match4 NVARCHAR(500) '$.Match4',
            Answer5 NVARCHAR(500) '$.Answer5', IsCorrect5 BIT '$.IsCorrect5', Match5 NVARCHAR(500) '$.Match5',
            Answer6 NVARCHAR(500) '$.Answer6', IsCorrect6 BIT '$.IsCorrect6', Match6 NVARCHAR(500) '$.Match6',
            Answer7 NVARCHAR(500) '$.Answer7', IsCorrect7 BIT '$.IsCorrect7', Match7 NVARCHAR(500) '$.Match7',
            Answer8 NVARCHAR(500) '$.Answer8', IsCorrect8 BIT '$.IsCorrect8', Match8 NVARCHAR(500) '$.Match8'
        );

        BEGIN TRANSACTION;

        -- Alapértelmezett RoundType = main_quiz ha nincs megadva
        UPDATE #IncomingQuestions SET RoundTypeCode = 'main_quiz' WHERE RoundTypeCode IS NULL;
        
        -- RoundTypeID beállítása
        UPDATE i SET i.RoundTypeID = rt.id
        FROM #IncomingQuestions i JOIN [OP].[tblRoundType] rt ON i.RoundTypeCode = rt.Code;

        IF EXISTS (SELECT 1 FROM #IncomingQuestions WHERE RoundTypeID IS NULL)
        BEGIN
            DECLARE @MissingRTypes NVARCHAR(MAX);
            SELECT @MissingRTypes = STRING_AGG(RoundTypeCode, ', ') FROM (SELECT DISTINCT RoundTypeCode FROM #IncomingQuestions WHERE RoundTypeID IS NULL) t;
            DECLARE @ErrMsgR NVARCHAR(2048) = N'Ismeretlen forduló típus kód(ok): ' + ISNULL(@MissingRTypes, 'ismeretlen'); THROW 50020, @ErrMsgR, 1;
        END

        -- Idő alapbeállítás gyorsasági játékoknál
        UPDATE #IncomingQuestions SET TimeSec = 12 WHERE RoundTypeCode = 'fast_5' AND TimeSec IS NULL;

        -- Topics
        INSERT INTO [OP].[tblTopic] (Name, ActiveFlg)
        SELECT DISTINCT i.TopicName, 1
        FROM #IncomingQuestions i
        WHERE i.TopicName IS NOT NULL 
          AND NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] t WHERE t.Name = i.TopicName);

        UPDATE i SET i.TopicID = t.id
        FROM #IncomingQuestions i JOIN [OP].[tblTopic] t ON i.TopicName = t.Name;

        -- QuestionTypes
        UPDATE i SET i.QuestionTypeID = qt.id
        FROM #IncomingQuestions i JOIN [OP].[tblQuestionType] qt ON i.TypeCode = qt.Code;

        IF EXISTS (SELECT 1 FROM #IncomingQuestions WHERE QuestionTypeID IS NULL)
        BEGIN
            DECLARE @MissingTypes NVARCHAR(MAX);
            SELECT @MissingTypes = STRING_AGG(TypeCode, ', ') FROM (SELECT DISTINCT TypeCode FROM #IncomingQuestions WHERE QuestionTypeID IS NULL) t;
            DECLARE @ErrMsg NVARCHAR(2048) = N'Ismeretlen kérdéstípus kód(ok): ' + ISNULL(@MissingTypes, 'ismeretlen'); THROW 50020, @ErrMsg, 1;
        END

        -- Insert Questions to Global Repository
        DECLARE @InsertedQuestions TABLE (TempId INT, InsertedID INT);
        MERGE INTO [OP].[tblQuestion] AS target
        USING #IncomingQuestions AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (TopicID, QuestionTypeID, Prompt, TimeSec, MediaUrl, ActiveFlg, CreatedAtUtc, LastCreatedUserID)
            VALUES (source.TopicID, source.QuestionTypeID, source.Prompt, ISNULL(source.TimeSec, 0), source.MediaUrl, 1, @Now, @UserID)
        OUTPUT source.TempId, inserted.id INTO @InsertedQuestions;

        UPDATE i SET i.NewQuestionID = q.InsertedID
        FROM #IncomingQuestions i JOIN @InsertedQuestions q ON i.TempId = q.TempId;

        -- Options
        CREATE TABLE #TempOptions (
            QuestionID INT, TypeCode NVARCHAR(16), SlotIndex INT,
            AnswerText NVARCHAR(500), MatchText NVARCHAR(500), IsCorrect BIT,
            InsertedOptionID INT, InsertedMatchOptionID INT
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

        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, TextValue)
        SELECT QuestionID, AnswerText FROM #TempOptions WHERE TypeCode = 'freetext' AND SlotIndex = 1;
        DELETE FROM #TempOptions WHERE TypeCode = 'freetext';

        DECLARE @InsertedOpts TABLE (SlotIndex INT, QuestionID INT, InsertedID INT);
        MERGE INTO [OP].[tblQuestionOption] AS target
        USING #TempOptions AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (QuestionID, ListType, Value, SortIndex)
            VALUES (source.QuestionID, CASE WHEN source.TypeCode IN ('match', 'category') THEN 'left' ELSE 'options' END, source.AnswerText, source.SlotIndex)
        OUTPUT source.SlotIndex, source.QuestionID, inserted.id INTO @InsertedOpts;

        UPDATE t SET t.InsertedOptionID = i.InsertedID
        FROM #TempOptions t JOIN @InsertedOpts i ON t.QuestionID = i.QuestionID AND t.SlotIndex = i.SlotIndex;

        DECLARE @InsertedMatchOpts TABLE (SlotIndex INT, QuestionID INT, InsertedID INT);
        MERGE INTO [OP].[tblQuestionOption] AS target
        USING (SELECT * FROM #TempOptions WHERE TypeCode IN ('match', 'category') AND MatchText IS NOT NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (QuestionID, ListType, Value, SortIndex)
            VALUES (source.QuestionID, 'right', source.MatchText, source.SlotIndex)
        OUTPUT source.SlotIndex, source.QuestionID, inserted.id INTO @InsertedMatchOpts;

        UPDATE t SET t.InsertedMatchOptionID = i.InsertedID
        FROM #TempOptions t JOIN @InsertedMatchOpts i ON t.QuestionID = i.QuestionID AND t.SlotIndex = i.SlotIndex;

        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID)
        SELECT QuestionID, InsertedOptionID FROM #TempOptions WHERE TypeCode IN ('single', 'multi') AND IsCorrect = 1;

        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID, SortIndex)
        SELECT QuestionID, InsertedOptionID, SlotIndex FROM #TempOptions WHERE TypeCode = 'order';

        INSERT INTO [OP].[tblQuestionCorrectAnswer] (QuestionID, OptionID, MatchOptionID)
        SELECT QuestionID, InsertedOptionID, InsertedMatchOptionID FROM #TempOptions WHERE TypeCode IN ('match', 'category');

        -- EVENT SETTINGS (Topics)
        INSERT INTO [OP].[tblEventSettingTopic] (EventID, TopicID)
        SELECT DISTINCT @EventID, TopicID FROM #IncomingQuestions
        WHERE TopicID IS NOT NULL AND TopicID NOT IN (SELECT TopicID FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID);

        -- ROUNDS LÉTREHOZÁSA (MINDEN TÍPUSNAK EGYFORMÁN!)
        DECLARE @PendingStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'pending');
        DECLARE @MaxSortIndex INT = ISNULL((SELECT MAX(SortIndex) FROM [OP].[tblRound] WHERE EventID = @EventID), 0);
        DECLARE @CreatedRounds TABLE (TopicID INT, RoundTypeID INT, RoundID INT);

        INSERT INTO [OP].[tblRound] (EventID, TopicID, Mode, RoundStatusID, SortIndex, ActiveFlg, LastCreatedUserID, RoundTypeID)
        OUTPUT inserted.TopicID, inserted.RoundTypeID, inserted.id INTO @CreatedRounds
        SELECT @EventID, TopicID, 'fixed', @PendingStatusID, @MaxSortIndex + ROW_NUMBER() OVER (ORDER BY MIN(TempId)), 1, @UserID, RoundTypeID
        FROM #IncomingQuestions
        WHERE TopicID IS NOT NULL
        GROUP BY TopicID, RoundTypeID;

        -- EVENT QUESTIONS LÉTREHOZÁSA (MINDEN TÍPUSNAK EGYFORMÁN!)
        ;WITH RankedQuestions AS (
            SELECT r.RoundID, i.NewQuestionID, i.TimeSec, ROW_NUMBER() OVER(PARTITION BY i.TopicID, i.RoundTypeID ORDER BY ISNULL(i.RowIndex, i.TempId)) AS RN
            FROM #IncomingQuestions i JOIN @CreatedRounds r ON i.TopicID = r.TopicID AND i.RoundTypeID = r.RoundTypeID
            WHERE i.NewQuestionID IS NOT NULL
        )
        INSERT INTO [OP].[tblEventQuestion] (EventID, RoundID, QuestionID, SortIndex, StatusCode, TimeSec, ActiveFlg, LastCreatedUserID)
        SELECT @EventID, RoundID, NewQuestionID, RN, 'pending', ISNULL(TimeSec, 30), 1, @UserID
        FROM RankedQuestions;

        COMMIT TRANSACTION;
        
        DECLARE @FirstRoundID INT = (SELECT TOP 1 RoundID FROM @CreatedRounds);
        SELECT 1 AS ReturnValue, N'Sikeres importálás (' + CAST((SELECT COUNT(*) FROM #IncomingQuestions) AS NVARCHAR(20)) + ' db kérdés).' AS ReturnDescription, ISNULL(@FirstRoundID, '') AS RoundID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
