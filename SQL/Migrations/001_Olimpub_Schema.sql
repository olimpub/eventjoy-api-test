SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- =============================================
-- Olimpub (OP) Schema Initialization
-- Eseménytípus kódja: 43
-- =============================================

BEGIN TRAN;

IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'OP')
BEGIN
    EXEC('CREATE SCHEMA OP');
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[EJ].[tblEventType]') AND name = 'OPFlg')
BEGIN
    ALTER TABLE [EJ].[tblEventType] ADD OPFlg bit NULL;
END
GO
UPDATE [EJ].[tblEventType] SET OPFlg = 1 WHERE id = 43;
GO

IF NOT EXISTS (SELECT 1 FROM [EJ].[tblLoginIdentifierType] WHERE Code = 'device')
BEGIN
    DECLARE @NewID INT;
    SELECT @NewID = ISNULL(MAX(id), 0) + 1 FROM [EJ].[tblLoginIdentifierType];
    INSERT INTO [EJ].[tblLoginIdentifierType] (id, Name, Code, createdAt, ActiveFlg)
    VALUES (@NewID, 'Device', 'device', SYSDATETIMEOFFSET(), 1);
END
GO

-- =============================================
-- Törzsadatok
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblKabala]'))
BEGIN
    CREATE TABLE OP.tblKabala (
      id int IDENTITY PRIMARY KEY,
      Name nvarchar(80) NOT NULL,
      ImageUrl nvarchar(500) NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblTopic]'))
BEGIN
    CREATE TABLE OP.tblTopic (
      id int IDENTITY PRIMARY KEY,
      Name nvarchar(120) NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblQuestionType]'))
BEGIN
    CREATE TABLE OP.tblQuestionType (
      id int IDENTITY PRIMARY KEY,
      Code nvarchar(16) NOT NULL, -- single, multi, order, match, category, freetext
      Name nvarchar(100) NOT NULL,
      DefaultRunningTimeSec int NOT NULL DEFAULT 60, -- Itt tároljuk a típushoz tartozó alap futási időt
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblRoundStatus]'))
BEGIN
    CREATE TABLE OP.tblRoundStatus (
      id int IDENTITY PRIMARY KEY,
      Code nvarchar(16) NOT NULL, -- pending, active, closed, published
      Name nvarchar(100) NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

-- =============================================
-- Kérdés Repository
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblQuestion]'))
BEGIN
    CREATE TABLE OP.tblQuestion (
      id int IDENTITY PRIMARY KEY,
      TopicID int NOT NULL, -- NINCS FK (tblTopic)
      QuestionTypeID int NOT NULL, -- NINCS FK (tblQuestionType)
      Prompt nvarchar(max) NOT NULL,
      TimeSec int NOT NULL,
      MediaUrl nvarchar(1000) NULL, -- Közvetlen URL a feltöltött anyaghoz
      ActiveFlg bit NOT NULL DEFAULT 1,
      CreatedAtUtc datetimeoffset NOT NULL DEFAULT SYSDATETIMEOFFSET()
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblQuestionOption]'))
BEGIN
    CREATE TABLE OP.tblQuestionOption (
      id int IDENTITY PRIMARY KEY,
      QuestionID int NOT NULL, -- NINCS FK (tblQuestion)
      ListType nvarchar(50) NOT NULL,
      Value nvarchar(max) NOT NULL,
      SortIndex int NOT NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblQuestionCorrectAnswer]'))
BEGIN
    CREATE TABLE OP.tblQuestionCorrectAnswer (
      id int IDENTITY PRIMARY KEY,
      QuestionID int NOT NULL, -- NINCS FK
      OptionID int NULL, -- NINCS FK
      MatchOptionID int NULL, -- NINCS FK
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

-- =============================================
-- Esemény Beállítások és Csapatok
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblEventSettings]'))
BEGIN
    CREATE TABLE OP.tblEventSettings (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL UNIQUE, 
      DeskCountHint int NULL,
      MaxTeamSize int NOT NULL,
      PlannedDurationMin int NOT NULL,
      ShadowAwardFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblEventSettingTopic]'))
BEGIN
    CREATE TABLE OP.tblEventSettingTopic (
      EventID bigint NOT NULL,
      TopicID int NOT NULL, -- NINCS FK
      PRIMARY KEY (EventID, TopicID)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblEventSettingExtraGame]'))
BEGIN
    CREATE TABLE OP.tblEventSettingExtraGame (
      EventID bigint NOT NULL,
      ExtraGameId nvarchar(8) NOT NULL,
      PRIMARY KEY (EventID, ExtraGameId)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblEventSettingKabala]'))
BEGIN
    CREATE TABLE OP.tblEventSettingKabala (
      EventID bigint NOT NULL,
      KabalaID int NOT NULL, -- NINCS FK
      PRIMARY KEY (EventID, KabalaID)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblTeam]'))
BEGIN
    CREATE TABLE OP.tblTeam (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      KabalaID int NOT NULL, -- NINCS FK
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblTeamMember]'))
BEGIN
    CREATE TABLE OP.tblTeamMember (
      id int IDENTITY PRIMARY KEY,
      TeamID int NOT NULL, -- NINCS FK
      EventUserID bigint NOT NULL, -- NINCS FK
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

-- =============================================
-- Játékmenet
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblRound]'))
BEGIN
    CREATE TABLE OP.tblRound (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      TopicID int NULL, -- NINCS FK
      Mode nvarchar(16) NOT NULL,
      RoundStatusID int NOT NULL, -- NINCS FK (tblRoundStatus)
      SortIndex int NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblEventQuestion]'))
BEGIN
    CREATE TABLE OP.tblEventQuestion (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      RoundID int NOT NULL, -- NINCS FK
      QuestionID int NOT NULL, -- NINCS FK
      SortIndex tinyint NOT NULL,
      StatusCode nvarchar(16) NOT NULL,
      StartedAtUtc datetimeoffset NULL,
      StoppedAtUtc datetimeoffset NULL,
      TimeSec int NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

-- =============================================
-- Beküldött Válaszok
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblAnswer]'))
BEGIN
    CREATE TABLE OP.tblAnswer (
      id int IDENTITY PRIMARY KEY,
      EventQuestionID int NOT NULL, -- NINCS FK
      EventUserID bigint NOT NULL, -- NINCS FK
      ReceivedAtUtc datetimeoffset NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblAnswerItem]'))
BEGIN
    CREATE TABLE OP.tblAnswerItem (
      id int IDENTITY PRIMARY KEY,
      AnswerID int NOT NULL, -- NINCS FK
      OptionID int NULL, -- NINCS FK
      MatchOptionID int NULL, -- NINCS FK
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

-- =============================================
-- Pontozás
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblQuestionScore]'))
BEGIN
    CREATE TABLE OP.tblQuestionScore (
      EventQuestionID int NOT NULL,
      TeamID int NOT NULL,
      RawS decimal(12,4) NOT NULL,
      C int NOT NULL,
      W int NOT NULL,
      SpeedT decimal(8,3) NULL,
      PRIMARY KEY (EventQuestionID, TeamID)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblShadowScore]'))
BEGIN
    CREATE TABLE OP.tblShadowScore (
      EventQuestionID int NOT NULL,
      EventUserID bigint NOT NULL,
      S decimal(12,4) NOT NULL,
      PRIMARY KEY (EventQuestionID, EventUserID)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblRoundScore]'))
BEGIN
    CREATE TABLE OP.tblRoundScore (
      RoundID int NOT NULL,
      TeamID int NOT NULL,
      RawSSum decimal(12,4) NOT NULL,
      Place int NOT NULL,
      F int NOT NULL,
      PRIMARY KEY (RoundID, TeamID)
    );
END

-- =============================================
-- Extra Játékok
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraRun]'))
BEGIN
    CREATE TABLE OP.tblExtraRun (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      ExtraGameId nvarchar(8) NOT NULL,
      StatusCode nvarchar(16) NOT NULL,
      StartedAtUtc datetimeoffset NOT NULL,
      ClosedAtUtc datetimeoffset NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraQuestion]'))
BEGIN
    CREATE TABLE OP.tblExtraQuestion (
      id int IDENTITY PRIMARY KEY,
      ExtraRunID int NOT NULL, -- NINCS FK
      SortIndex tinyint NOT NULL,
      QuestionTypeID int NOT NULL, -- NINCS FK
      Prompt nvarchar(max) NOT NULL,
      TimeSec int NOT NULL,
      MediaUrl nvarchar(1000) NULL,
      StatusCode nvarchar(16) NOT NULL,
      StartedAtUtc datetimeoffset NULL,
      StoppedAtUtc datetimeoffset NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraQuestionOption]'))
BEGIN
    CREATE TABLE OP.tblExtraQuestionOption (
      id int IDENTITY PRIMARY KEY,
      ExtraQuestionID int NOT NULL, -- NINCS FK
      ListType nvarchar(50) NOT NULL,
      Value nvarchar(max) NOT NULL,
      SortIndex int NOT NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraQuestionCorrectAnswer]'))
BEGIN
    CREATE TABLE OP.tblExtraQuestionCorrectAnswer (
      id int IDENTITY PRIMARY KEY,
      ExtraQuestionID int NOT NULL, -- NINCS FK
      OptionID int NULL, -- NINCS FK
      MatchOptionID int NULL, -- NINCS FK
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraAnswer]'))
BEGIN
    CREATE TABLE OP.tblExtraAnswer (
      id int IDENTITY PRIMARY KEY,
      ExtraQuestionID int NOT NULL, -- NINCS FK
      EventUserID bigint NOT NULL, -- NINCS FK
      ReceivedAtUtc datetimeoffset NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraAnswerItem]'))
BEGIN
    CREATE TABLE OP.tblExtraAnswerItem (
      id int IDENTITY PRIMARY KEY,
      ExtraAnswerID int NOT NULL, -- NINCS FK
      OptionID int NULL, -- NINCS FK
      MatchOptionID int NULL, -- NINCS FK
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraScore]'))
BEGIN
    CREATE TABLE OP.tblExtraScore (
      ExtraRunID int NOT NULL,
      TeamID int NOT NULL,
      Points int NOT NULL,
      PRIMARY KEY (ExtraRunID, TeamID)
    );
END

-- =============================================
-- Büntetések és Kivetítő
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblPenalty]'))
BEGIN
    CREATE TABLE OP.tblPenalty (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      TeamID int NOT NULL, -- NINCS FK
      Points int NOT NULL,
      UndoOfID int NULL,
      CreatedAtUtc datetimeoffset NOT NULL DEFAULT SYSDATETIMEOFFSET(),
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblDisplayToken]'))
BEGIN
    CREATE TABLE OP.tblDisplayToken (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      Pin char(4) NOT NULL,
      Token nvarchar(80) NOT NULL,
      ExpiresAtUtc datetimeoffset NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

COMMIT;
GO
