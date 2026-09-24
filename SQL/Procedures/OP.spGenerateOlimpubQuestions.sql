SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spGenerateOlimpubQuestions]
    @EventID BIGINT,
    @TopicID INT,
    @Mode NVARCHAR(16),
    @RoundSortIndex INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @RoundID INT;
    DECLARE @PendingStatusID INT = (SELECT id FROM [OP].[tblRoundStatus] WHERE Code = 'pending');

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Ellenőrizzük, hogy van-e már ilyen sorszámú kör (ha igen, dobjunk hibát vagy töröljük, ha még pending?)
        -- Jellemzően újat generálunk.
        IF EXISTS (SELECT 1 FROM [OP].[tblRound] WHERE EventID = @EventID AND SortIndex = @RoundSortIndex AND RoundStatusID != @PendingStatusID AND ActiveFlg = 1)
        BEGIN
            THROW 50010, N'Erre a sorszámra már létezik egy aktív vagy lezárt forduló!', 1;
        END

        -- Ha volt már pending forduló ezen az indexen, azt inaktiváljuk (felülírjuk az újonnan generálttal)
        UPDATE [OP].[tblRound] SET ActiveFlg = 0 
        WHERE EventID = @EventID AND SortIndex = @RoundSortIndex AND RoundStatusID = @PendingStatusID AND ActiveFlg = 1;

        -- 2. Hozzuk létre az új Round-ot
        INSERT INTO [OP].[tblRound] (EventID, TopicID, Mode, RoundStatusID, SortIndex, ActiveFlg)
        VALUES (@EventID, @TopicID, @Mode, @PendingStatusID, @RoundSortIndex, 1);

        SET @RoundID = SCOPE_IDENTITY();

        -- 3. Kérdések kiválogatása (1,3,5,7 -> single, 2,4,6,8 -> egyéb)
        -- Olyan kérdéseket keresünk, amik MÁG NEM voltak ezen az eseményen
        DECLARE @SingleTypeID INT = (SELECT id FROM [OP].[tblQuestionType] WHERE Code = 'single');

        CREATE TABLE #SelectedQuestions (
            QuestionID INT,
            SortIndex INT,
            TimeSec INT
        );

        -- 3.1. Négy 'single' kérdés kiválasztása véletlenszerűen
        INSERT INTO #SelectedQuestions (QuestionID, SortIndex, TimeSec)
        SELECT q.id, 
               CASE row_number() OVER (ORDER BY NEWID()) 
                    WHEN 1 THEN 1 
                    WHEN 2 THEN 3 
                    WHEN 3 THEN 5 
                    WHEN 4 THEN 7 
               END,
               ISNULL(NULLIF(q.TimeSec, 0), qt.DefaultRunningTimeSec)
        FROM [OP].[tblQuestion] q
        JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
        WHERE q.TopicID = @TopicID 
          AND q.QuestionTypeID = @SingleTypeID 
          AND q.ActiveFlg = 1
          AND NOT EXISTS (
              SELECT 1 FROM [OP].[tblEventQuestion] eq 
              JOIN [OP].[tblRound] r ON eq.RoundID = r.id
              WHERE r.EventID = @EventID AND eq.QuestionID = q.id AND eq.ActiveFlg = 1
          )
        ORDER BY NEWID()
        OFFSET 0 ROWS FETCH NEXT 4 ROWS ONLY;

        IF @@ROWCOUNT < 4
        BEGIN
            THROW 50011, N'Nincs elegendő "egyválasztós" kérdés ebben a témakörben!', 1;
        END

        -- 3.2. Négy NEM 'single' kérdés kiválasztása
        INSERT INTO #SelectedQuestions (QuestionID, SortIndex, TimeSec)
        SELECT q.id, 
               CASE row_number() OVER (ORDER BY NEWID()) 
                    WHEN 1 THEN 2 
                    WHEN 2 THEN 4 
                    WHEN 3 THEN 6 
                    WHEN 4 THEN 8 
               END,
               ISNULL(NULLIF(q.TimeSec, 0), qt.DefaultRunningTimeSec)
        FROM [OP].[tblQuestion] q
        JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
        WHERE q.TopicID = @TopicID 
          AND q.QuestionTypeID != @SingleTypeID 
          AND q.ActiveFlg = 1
          AND NOT EXISTS (
              SELECT 1 FROM [OP].[tblEventQuestion] eq 
              JOIN [OP].[tblRound] r ON eq.RoundID = r.id
              WHERE r.EventID = @EventID AND eq.QuestionID = q.id AND eq.ActiveFlg = 1
          )
        ORDER BY NEWID()
        OFFSET 0 ROWS FETCH NEXT 4 ROWS ONLY;

        IF @@ROWCOUNT < 4
        BEGIN
            THROW 50012, N'Nincs elegendő egyéb típusú kérdés ebben a témakörben!', 1;
        END

        -- 4. Kérdések beszúrása az EventQuestion táblába
        INSERT INTO [OP].[tblEventQuestion] (EventID, RoundID, QuestionID, SortIndex, StatusCode, TimeSec, ActiveFlg)
        SELECT @EventID, @RoundID, QuestionID, SortIndex, 'pending', TimeSec, 1
        FROM #SelectedQuestions;

        COMMIT TRANSACTION;

        SELECT 1 AS ReturnValue, N'Kérdéssor sikeresen legenerálva.' AS ReturnDescription, @RoundID AS RoundID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS RoundID;
    END CATCH
END
GO
