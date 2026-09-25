SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. TESZT KÖRNYEZET ELŐKÉSZÍTÉSE
DECLARE @EventID BIGINT;
DECLARE @OrgUserID BIGINT = 1; -- Tegyük fel, hogy az 1-es User a szervező
DECLARE @Player1UserID BIGINT = 2;
DECLARE @Player2UserID BIGINT = 3;

-- Töröljük a korábbi teszt eseményt ha volt
DELETE FROM [EJ].[tblEvent] WHERE Title = 'Teszt Olimpub Esemény';

-- Létrehozunk egy alap eseményt
INSERT INTO [EJ].[tblEvent] (Title, Description, EventStatusID, EventTypeID, StartAtUtc, EndAtUtc, CreatedByUserID)
VALUES ('Teszt Olimpub Esemény', 'Olimpub teszt', 1, 43, SYSDATETIME(), SYSDATETIME(), 1);
SET @EventID = SCOPE_IDENTITY();

-- Szerepkörök és Userek beállítása (Szervező)
INSERT INTO [EJ].[tblEventUser] (EventID, UserID, ActiveFlg) VALUES (@EventID, @OrgUserID, 1);
DECLARE @OrgEventUserID BIGINT = SCOPE_IDENTITY();
-- Feltételezzük, hogy az EventRoleID = 1 a Szervező
INSERT INTO [EJ].[tblEventRole] (EventID, RoleID) VALUES (@EventID, 1);
DECLARE @OrgEventRoleID INT = SCOPE_IDENTITY();
UPDATE [EJ].[tblEventUser] SET EventRoleID = @OrgEventRoleID WHERE id = @OrgEventUserID;

-- 2. OP BEÁLLÍTÁSOK (spSaveEvent helyett kézzel)
INSERT INTO [OP].[tblEventSettings] (EventID, MaxTeamSize, PlannedDurationMin, ShadowAwardFlg)
VALUES (@EventID, 6, 90, 1);

-- 3. KÉRDÉSEK IMPORTÁLÁSA
DECLARE @JsonImport NVARCHAR(MAX) = N'{
  "Questions": [
    {
      "RowIndex": 1, "TopicName": "Zene", "TypeCode": "single", "Prompt": "Ki énekli a Thrillert?", "TimeSec": 60,
      "Answer1": "Michael Jackson", "IsCorrect1": true,
      "Answer2": "Prince", "IsCorrect2": false
    },
    {
      "RowIndex": 2, "TopicName": "Földrajz", "TypeCode": "single", "Prompt": "Főváros?", "TimeSec": 60,
      "Answer1": "Budapest", "IsCorrect1": true,
      "Answer2": "Bécs", "IsCorrect2": false
    },
    {
      "RowIndex": 3, "TopicName": "Zene", "TypeCode": "single", "Prompt": "Ki énekli a Bad-et?", "TimeSec": 60,
      "Answer1": "Michael Jackson", "IsCorrect1": true,
      "Answer2": "Prince", "IsCorrect2": false
    },
    {
      "RowIndex": 4, "TopicName": "Történelem", "TypeCode": "single", "Prompt": "Mikor volt a honfoglalás?", "TimeSec": 60,
      "Answer1": "895", "IsCorrect1": true,
      "Answer2": "1000", "IsCorrect2": false
    }
  ]
}';

EXEC [OP].[spImportQuestions] @Json = @JsonImport, @UserID = @OrgUserID;

-- Témakörök bekötése az Eseményhez
INSERT INTO [OP].[tblEventSettingTopic] (EventID, TopicID)
SELECT @EventID, id FROM [OP].[tblTopic];

-- 4. CSAPAT LÉTREHOZÁS ÉS CSATLAKOZÁS
INSERT INTO [OP].[tblKabala] (Name, ActiveFlg) VALUES ('Teszt Kabala 1', 1), ('Teszt Kabala 2', 1);
DECLARE @Kabala1 INT = (SELECT TOP 1 id FROM [OP].[tblKabala] WHERE Name = 'Teszt Kabala 1');
DECLARE @Kabala2 INT = (SELECT TOP 1 id FROM [OP].[tblKabala] WHERE Name = 'Teszt Kabala 2');

INSERT INTO [OP].[tblTeam] (EventID, KabalaID, ActiveFlg) VALUES (@EventID, @Kabala1, 1), (@EventID, @Kabala2, 1);
DECLARE @Team1 INT = (SELECT id FROM [OP].[tblTeam] WHERE KabalaID = @Kabala1 AND EventID = @EventID);
DECLARE @Team2 INT = (SELECT id FROM [OP].[tblTeam] WHERE KabalaID = @Kabala2 AND EventID = @EventID);

-- Játékosok (P1 és P2 csatlakozik)
INSERT INTO [EJ].[tblEventUser] (EventID, UserID, ActiveFlg) VALUES (@EventID, @Player1UserID, 1);
DECLARE @P1_EUID BIGINT = SCOPE_IDENTITY();
INSERT INTO [OP].[tblTeamMember] (EventUserID, TeamID, ActiveFlg) VALUES (@P1_EUID, @Team1, 1);

INSERT INTO [EJ].[tblEventUser] (EventID, UserID, ActiveFlg) VALUES (@EventID, @Player2UserID, 1);
DECLARE @P2_EUID BIGINT = SCOPE_IDENTITY();
INSERT INTO [OP].[tblTeamMember] (EventUserID, TeamID, ActiveFlg) VALUES (@P2_EUID, @Team2, 1);

-- 5. KÖR GENERÁLÁS
EXEC [OP].[spGenerateOlimpubQuestions] @EventID = @EventID, @UserID = @OrgUserID, @Mode = 'mixed', @Count = 4;

-- Lekérjük a RoundID-t és a Kérdéseket
DECLARE @RoundID INT = (SELECT TOP 1 id FROM [OP].[tblRound] WHERE EventID = @EventID);
DECLARE @Q1 INT = (SELECT TOP 1 id FROM [OP].[tblEventQuestion] WHERE RoundID = @RoundID ORDER BY SortIndex ASC);

-- 6. JÁTÉK MOTOR (spChangeGame)
-- 6.1 Publish Round
DECLARE @PayloadPublish NVARCHAR(MAX) = N'{"Payload": {"RoundID": ' + CAST(@RoundID AS NVARCHAR) + '}}';
EXEC [OP].[spChangeGame] @EventID, @OrgUserID, N'Op.PublishRound', @PayloadPublish;

-- 6.2 Start Question 1
DECLARE @PayloadStart NVARCHAR(MAX) = N'{"Payload": {"EventQuestionID": ' + CAST(@Q1 AS NVARCHAR) + '}}';
EXEC [OP].[spChangeGame] @EventID, @OrgUserID, N'Op.StartQuestion', @PayloadStart;

-- 6.3 Player 1 válaszol (Helyes) - Kikeressük az OptionID-t
DECLARE @CorrectOption1 INT = (SELECT TOP 1 ca.OptionID FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblQuestionCorrectAnswer] ca ON eq.QuestionID = ca.QuestionID WHERE eq.id = @Q1);
DECLARE @PayloadAns1 NVARCHAR(MAX) = N'{"Payload": {"EventQuestionID": ' + CAST(@Q1 AS NVARCHAR) + ', "Items": [{"OptionID": ' + CAST(@CorrectOption1 AS NVARCHAR) + '}]}}';
EXEC [OP].[spChangeGame] @EventID, @Player1UserID, N'Op.SubmitAnswer', @PayloadAns1;

-- 6.4 Player 2 válaszol (Helytelen) - Kikeressük a ROSSZ OptionID-t
DECLARE @WrongOption1 INT = (SELECT TOP 1 o.id FROM [OP].[tblEventQuestion] eq JOIN [OP].[tblQuestionOption] o ON eq.QuestionID = o.QuestionID WHERE eq.id = @Q1 AND o.id != @CorrectOption1);
DECLARE @PayloadAns2 NVARCHAR(MAX) = N'{"Payload": {"EventQuestionID": ' + CAST(@Q1 AS NVARCHAR) + ', "Items": [{"OptionID": ' + CAST(@WrongOption1 AS NVARCHAR) + '}]}}';
EXEC [OP].[spChangeGame] @EventID, @Player2UserID, N'Op.SubmitAnswer', @PayloadAns2;

-- Várjunk 1 másodpercet hogy az idő látszódjon a szorzóban
WAITFOR DELAY '00:00:01';

-- 6.5 Stop Question 1 -> Ekkor fut le a PONTOZÁS!
DECLARE @PayloadStop NVARCHAR(MAX) = N'{"Payload": {"EventQuestionID": ' + CAST(@Q1 AS NVARCHAR) + '}}';
EXEC [OP].[spChangeGame] @EventID, @OrgUserID, N'Op.StopQuestion', @PayloadStop;

-- 7. EREDMÉNYEK LEKÉRÉSE
SELECT '==== PONTOZAS EREDMENYE ====' AS L;
SELECT t.id AS TeamID, qs.RawS, qs.C, qs.W, qs.SpeedT 
FROM [OP].[tblQuestionScore] qs 
JOIN [OP].[tblTeam] t ON qs.TeamID = t.id 
WHERE qs.EventQuestionID = @Q1;

SELECT '==== LEADERBOARD RAW ====' AS L;
EXEC [OP].[spGetLeaderboard] @EventID, 'raw', @OrgUserID;

-- 8. KÖR ZÁRÁSA ÉS LEADERBOARD MAIN
DECLARE @PayloadClose NVARCHAR(MAX) = N'{"Payload": {"RoundID": ' + CAST(@RoundID AS NVARCHAR) + '}}';
-- Trükk: a többi kérdést is stopped-ra kell tenni, különben hibát dob
UPDATE [OP].[tblEventQuestion] SET StatusCode = 'stopped' WHERE RoundID = @RoundID AND id != @Q1;
EXEC [OP].[spChangeGame] @EventID, @OrgUserID, N'Op.CloseRound', @PayloadClose;

SELECT '==== LEADERBOARD MAIN ====' AS L;
EXEC [OP].[spGetLeaderboard] @EventID, 'main', @OrgUserID;

GO
