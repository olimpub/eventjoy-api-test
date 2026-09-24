SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER FUNCTION [OP].[fnCalculateAnswerRatio](@AnswerID INT)
RETURNS DECIMAL(5,4)
AS
BEGIN
    DECLARE @Ratio DECIMAL(5,4) = 0.0;
    
    DECLARE @QuestionID INT;
    DECLARE @TypeCode NVARCHAR(16);

    SELECT 
        @QuestionID = q.id,
        @TypeCode = qt.Code
    FROM [OP].[tblAnswer] a
    JOIN [OP].[tblEventQuestion] eq ON a.EventQuestionID = eq.id
    JOIN [OP].[tblQuestion] q ON eq.QuestionID = q.id
    JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
    WHERE a.id = @AnswerID;

    IF @QuestionID IS NULL RETURN 0.0;

    IF @TypeCode IN ('single', 'multi')
    BEGIN
        DECLARE @TotalCorrect INT = (SELECT COUNT(*) FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @QuestionID);
        IF @TotalCorrect = 0 RETURN 0.0;

        DECLARE @SelectedCorrect INT = (
            SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
            JOIN [OP].[tblQuestionCorrectAnswer] ca ON ai.OptionID = ca.OptionID AND ca.QuestionID = @QuestionID
            WHERE ai.AnswerID = @AnswerID
        );

        DECLARE @SelectedWrong INT = (
            SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
            LEFT JOIN [OP].[tblQuestionCorrectAnswer] ca ON ai.OptionID = ca.OptionID AND ca.QuestionID = @QuestionID
            WHERE ai.AnswerID = @AnswerID AND ca.id IS NULL
        );

        DECLARE @Calc DECIMAL(10,4) = CAST(@SelectedCorrect - @SelectedWrong AS DECIMAL(10,4)) / CAST(@TotalCorrect AS DECIMAL(10,4));
        IF @Calc < 0 SET @Calc = 0;
        IF @Calc > 1 SET @Calc = 1;
        SET @Ratio = @Calc;
    END
    ELSE IF @TypeCode = 'order'
    BEGIN
        DECLARE @TotalOrder INT = (SELECT COUNT(*) FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @QuestionID);
        IF @TotalOrder = 0 RETURN 0.0;

        DECLARE @CorrectOrder INT = (
            SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
            JOIN [OP].[tblQuestionCorrectAnswer] ca ON ai.OptionID = ca.OptionID AND ai.SortIndex = ca.SortIndex AND ca.QuestionID = @QuestionID
            WHERE ai.AnswerID = @AnswerID
        );

        SET @Ratio = CAST(@CorrectOrder AS DECIMAL(10,4)) / CAST(@TotalOrder AS DECIMAL(10,4));
    END
    ELSE IF @TypeCode = 'match'
    BEGIN
        DECLARE @TotalMatch INT = (SELECT COUNT(*) FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @QuestionID);
        IF @TotalMatch = 0 RETURN 0.0;

        DECLARE @CorrectMatch INT = (
            SELECT COUNT(*) FROM [OP].[tblAnswerItem] ai
            JOIN [OP].[tblQuestionCorrectAnswer] ca ON ai.OptionID = ca.OptionID AND ai.MatchOptionID = ca.MatchOptionID AND ca.QuestionID = @QuestionID
            WHERE ai.AnswerID = @AnswerID
        );

        SET @Ratio = CAST(@CorrectMatch AS DECIMAL(10,4)) / CAST(@TotalMatch AS DECIMAL(10,4));
    END
    ELSE IF @TypeCode = 'freetext'
    BEGIN
        DECLARE @Synonyms NVARCHAR(MAX) = (SELECT TOP 1 TextValue FROM [OP].[tblQuestionCorrectAnswer] WHERE QuestionID = @QuestionID);
        DECLARE @UserText NVARCHAR(500) = (SELECT TOP 1 TextValue FROM [OP].[tblAnswerItem] WHERE AnswerID = @AnswerID);
        
        IF @Synonyms IS NOT NULL AND @UserText IS NOT NULL
        BEGIN
            -- Ellenőrizzük, hogy a user text benne van-e a vesszővel/vonallal elválasztott szinonimákban
            -- Egyszerű LIKE keresés, a valóságban a C# vagy egy okosabb split kéne, de SQL-ben így oldjuk meg:
            IF CONCAT(',', REPLACE(@Synonyms, ' ', ''), ',') LIKE CONCAT('%,', REPLACE(@UserText, ' ', ''), ',%')
                OR CONCAT('|', REPLACE(@Synonyms, ' ', ''), '|') LIKE CONCAT('%|', REPLACE(@UserText, ' ', ''), '|%')
            BEGIN
                SET @Ratio = 1.0;
            END
        END
    END
    ELSE
    BEGIN
        -- Default (pl. category vagy ismeretlen)
        SET @Ratio = 0.0;
    END

    RETURN @Ratio;
END
GO
