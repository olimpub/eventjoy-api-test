SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spGetRepositoryQuestions]
    @EventID BIGINT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- Csak szervező kérheti le
    IF NOT EXISTS (SELECT 1 FROM [EJ].[tblEventUser] eu JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id JOIN [EJ].[tblRole] r ON er.RoleID = r.id WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1)
    BEGIN
        THROW 50060, N'Csak szervezők kérhetik le a kérdés-tárat!', 1;
    END

    -- 1. Az esemény témaköreihez tartozó ÖSSZES kérdés a repositoryból (TopicId szűrő)
    -- 2. PLUSZ az ezen az eseményen lévő EventQuestionök QuestionID-jai (esetleg olyan, aminek a Topicja már nincs bekötve)
    
    SELECT 
        q.id,
        q.TopicID,
        t.Name AS TopicName,
        qt.Code AS TypeCode,
        q.Prompt,
        q.TimeSec,
        q.MediaUrl,
        CASE WHEN EXISTS (
            SELECT 1 FROM [OP].[tblEventQuestion] eq 
            JOIN [OP].[tblRound] r ON eq.RoundID = r.id 
            WHERE eq.QuestionID = q.id AND r.EventID = @EventID AND eq.ActiveFlg = 1
        ) THEN 1 ELSE 0 END AS InEventFlg
    FROM [OP].[tblQuestion] q
    JOIN [OP].[tblTopic] t ON q.TopicID = t.id
    JOIN [OP].[tblQuestionType] qt ON q.QuestionTypeID = qt.id
    WHERE q.ActiveFlg = 1 AND t.ActiveFlg = 1
      AND (
          q.TopicID IN (SELECT TopicID FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID)
          OR q.id IN (SELECT eq.QuestionID FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblRound] r ON eq.RoundID = r.id WHERE r.EventID = @EventID AND eq.ActiveFlg = 1)
      );

END
GO
