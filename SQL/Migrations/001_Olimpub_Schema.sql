-- =============================================
-- Olimpub (OP) Schema Initialization
-- Eseménytípus kódja: 43
-- JSON mezők kiszedve, 1:N relációkra cserélve a jobb adatbázis optimalizáció miatt.
-- =============================================

BEGIN TRAN;

-- 1. OP séma létrehozása (elszeparálja a pubkvíz specifikus táblákat a dbo/EJ tábláktól)
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = 'OP')
BEGIN
    EXEC('CREATE SCHEMA OP');
END
GO

-- 2. OPFlg hozzáadása az EventType-hoz (hogy tudjuk, Olimpub-e a típus)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[EJ].[tblEventType]') AND name = 'OPFlg')
BEGIN
    ALTER TABLE [EJ].[tblEventType] ADD OPFlg bit NULL;
END
GO
UPDATE [EJ].[tblEventType] SET OPFlg = 1 WHERE id = 43;
GO

-- 3. 'device' bejelentkezési típus (mert OTP nélkül lépnek be a kvízre a játékosok)
IF NOT EXISTS (SELECT 1 FROM [EJ].[tblLoginIdentifierType] WHERE Code = 'device')
BEGIN
    DECLARE @NewID INT;
    SELECT @NewID = MAX(id) + 1 FROM [EJ].[tblLoginIdentifierType];
    IF @NewID IS NULL SET @NewID = 1;
    INSERT INTO [EJ].[tblLoginIdentifierType] (id, Code, Name, ActiveFlg) VALUES (@NewID, 'device', 'Device', 1);
END
GO

-- =============================================
-- Alap beállítások és Témakörök
-- =============================================

-- Kabala: A csapatok választható avatárjai / logói
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Kabala]'))
BEGIN
    CREATE TABLE OP.Kabala (
      id int IDENTITY PRIMARY KEY,
      Name nvarchar(80) NOT NULL, -- Kabala neve (ebből lesz a csapat alap neve)
      ImageUrl nvarchar(500) NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

-- Topic: Témakörök a kérdésekhez (pl. Földrajz, Zene)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Topic]'))
BEGIN
    CREATE TABLE OP.Topic (
      id int IDENTITY PRIMARY KEY,
      Name nvarchar(120) NOT NULL,
      DefaultRunningTimeSec int NOT NULL DEFAULT 60, -- Alapértelmezett másodperc, ha a kérdéshez nincs megadva
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_Topic_Name ON OP.Topic (Name) WHERE ActiveFlg = 1;
END

-- =============================================
-- Kvízkérdések Repozitórium (1:N struktúra)
-- =============================================

-- Question: A kérdés maga (Json nélkül)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Question]'))
BEGIN
    CREATE TABLE OP.Question (
      id int IDENTITY PRIMARY KEY,
      TopicID int NOT NULL REFERENCES OP.Topic(id),
      TypeCode nvarchar(16) NOT NULL, -- single|multi|order|match|category|freetext
      Prompt nvarchar(max) NOT NULL, -- A kérdés szövege
      TimeSec int NULL, -- Ha NULL, akkor Topic.DefaultRunningTimeSec
      MediaKey nvarchar(200) NULL, -- Kép / Hang azonosító
      ActiveFlg bit NOT NULL DEFAULT 1,
      CreatedAtUtc datetimeoffset NOT NULL DEFAULT SYSDATETIMEOFFSET()
    );
END

-- QuestionOption: A kérdés válaszlehetőségei (sorrendben)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[QuestionOption]'))
BEGIN
    CREATE TABLE OP.QuestionOption (
      id int IDENTITY PRIMARY KEY,
      QuestionID int NOT NULL REFERENCES OP.Question(id),
      ListType nvarchar(50) NOT NULL, -- Polimorf lista: 'Options' (sima), 'Left'/'Right' (párosítós), 'Items'/'Cats' (kategóriás)
      Value nvarchar(max) NOT NULL, -- A válaszlehetőség szövege
      SortIndex int NOT NULL -- Megjelenési sorrend
    );
END

-- QuestionCorrectAnswer: A helyes megoldás logikája (típustól függően mely mezők vannak kitöltve)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[QuestionCorrectAnswer]'))
BEGIN
    CREATE TABLE OP.QuestionCorrectAnswer (
      id int IDENTITY PRIMARY KEY,
      QuestionID int NOT NULL REFERENCES OP.Question(id),
      OptionID int NULL REFERENCES OP.QuestionOption(id), -- A helyes opció (single/multi), vagy a 'Left' / 'Item' opció
      MatchOptionID int NULL REFERENCES OP.QuestionOption(id), -- Párosításnál a 'Right' / 'Cat' opció
      SortIndex int NULL, -- Sorrendbe rakásnál a helyes sorrend sorszáma
      TextValue nvarchar(500) NULL -- Szabad szöveges válasznál (freetext) az elfogadható szinonima
    );
END

-- =============================================
-- Esemény konfiguráció (1:N relációk a tömbök helyett)
-- =============================================

-- EventSettings: Alap beállítások egy konkrét eseményhez
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[EventSettings]'))
BEGIN
    CREATE TABLE OP.EventSettings (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL UNIQUE, 
      DeskCountHint int NULL,
      MaxTeamSize int NOT NULL,
      PlannedDurationMin int NOT NULL,
      ShadowAwardFlg bit NOT NULL DEFAULT 1
    );
END

-- EventSettingTopic: Engedélyezett témakörök ezen az eseményen
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[EventSettingTopic]'))
BEGIN
    CREATE TABLE OP.EventSettingTopic (
      EventID bigint NOT NULL,
      TopicID int NOT NULL REFERENCES OP.Topic(id),
      PRIMARY KEY (EventID, TopicID)
    );
END

-- EventSettingExtraGame: Bekapcsolt extra minijátékok
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[EventSettingExtraGame]'))
BEGIN
    CREATE TABLE OP.EventSettingExtraGame (
      EventID bigint NOT NULL,
      ExtraGameId nvarchar(8) NOT NULL,
      PRIMARY KEY (EventID, ExtraGameId)
    );
END

-- EventSettingKabala: Választható kabalák ezen az eseményen
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[EventSettingKabala]'))
BEGIN
    CREATE TABLE OP.EventSettingKabala (
      EventID bigint NOT NULL,
      KabalaID int NOT NULL REFERENCES OP.Kabala(id),
      PRIMARY KEY (EventID, KabalaID)
    );
END

-- =============================================
-- Csapatok és Játékosok
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Team]'))
BEGIN
    CREATE TABLE OP.Team (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      KabalaID int NOT NULL REFERENCES OP.Kabala(id),
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_Team_EventKabala ON OP.Team (EventID, KabalaID) WHERE ActiveFlg = 1;
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[TeamMember]'))
BEGIN
    CREATE TABLE OP.TeamMember (
      id int IDENTITY PRIMARY KEY,
      TeamID int NOT NULL REFERENCES OP.Team(id),
      EventUserID bigint NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_TeamMember ON OP.TeamMember (TeamID, EventUserID) WHERE ActiveFlg = 1;
END

-- =============================================
-- Kvíz Körök és Élesített Kérdések
-- =============================================

-- Round: Egy 8 kérdéses kvízkör állapota
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Round]'))
BEGIN
    CREATE TABLE OP.Round (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      TopicID int NULL REFERENCES OP.Topic(id),
      Mode nvarchar(16) NOT NULL, -- fixed (előre megadott), pick (csapat választ), wheel (szerencsekerék)
      StatusCode nvarchar(16) NOT NULL, -- pending | active | closed | published
      Picker nvarchar(8) NULL,
      SortIndex int NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

-- EventQuestion: A körben élesített kérdés időbélyegekkel
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[EventQuestion]'))
BEGIN
    CREATE TABLE OP.EventQuestion (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      RoundID int NOT NULL REFERENCES OP.Round(id),
      QuestionID int NOT NULL REFERENCES OP.Question(id),
      SortIndex tinyint NOT NULL,
      StatusCode nvarchar(16) NOT NULL, -- pending | active | stopped
      StartedAtUtc datetimeoffset NULL,
      StoppedAtUtc datetimeoffset NULL,
      TimeSec int NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_EQ_RoundSort ON OP.EventQuestion (RoundID, SortIndex) WHERE ActiveFlg = 1;
END

-- =============================================
-- Beküldött Válaszok (1:N struktúra)
-- =============================================

-- Answer: A válasz fejléce (ki mikor küldte)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Answer]'))
BEGIN
    CREATE TABLE OP.Answer (
      id int IDENTITY PRIMARY KEY,
      EventQuestionID int NOT NULL REFERENCES OP.EventQuestion(id),
      EventUserID bigint NOT NULL,
      ReceivedAtUtc datetimeoffset NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_Answer_EQ_EU ON OP.Answer (EventQuestionID, EventUserID) WHERE ActiveFlg = 1;
END

-- AnswerItem: A válasz részletei (mit pipált be, mit gépelt be)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[AnswerItem]'))
BEGIN
    CREATE TABLE OP.AnswerItem (
      id int IDENTITY PRIMARY KEY,
      AnswerID int NOT NULL REFERENCES OP.Answer(id),
      OptionID int NULL REFERENCES OP.QuestionOption(id),
      MatchOptionID int NULL REFERENCES OP.QuestionOption(id),
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

-- =============================================
-- Pontozás (Csapat és Árnyék)
-- =============================================

-- QuestionScore: Kérdésenkénti csapatpont
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[QuestionScore]'))
BEGIN
    CREATE TABLE OP.QuestionScore (
      EventQuestionID int NOT NULL,
      TeamID int NOT NULL,
      RawS decimal(12,4) NOT NULL, -- Kiszámolt pont a gyorsaság és helyes tagok arányában
      C int NOT NULL, -- Helyeset beküldő tagok száma
      W int NOT NULL, -- Rosszat beküldő tagok száma
      SpeedT decimal(8,3) NULL, -- Első helyes beküldés ideje
      PRIMARY KEY (EventQuestionID, TeamID)
    );
END

-- ShadowScore: Egyéni pontok
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ShadowScore]'))
BEGIN
    CREATE TABLE OP.ShadowScore (
      EventQuestionID int NOT NULL,
      EventUserID bigint NOT NULL,
      S decimal(12,4) NOT NULL,
      PRIMARY KEY (EventQuestionID, EventUserID)
    );
END

-- RoundScore: Kör összesített helyezése (F pontszám ami a fő tabellára megy)
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[RoundScore]'))
BEGIN
    CREATE TABLE OP.RoundScore (
      RoundID int NOT NULL,
      TeamID int NOT NULL,
      RawSSum decimal(12,4) NOT NULL,
      Place int NOT NULL,
      F int NOT NULL,
      PRIMARY KEY (RoundID, TeamID)
    );
END

-- =============================================
-- Extra Játékok (1:N struktúra másolása a kvízről)
-- =============================================

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraRun]'))
BEGIN
    CREATE TABLE OP.ExtraRun (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      ExtraGameId nvarchar(8) NOT NULL,
      StatusCode nvarchar(16) NOT NULL,
      StartedAtUtc datetimeoffset NOT NULL,
      ClosedAtUtc datetimeoffset NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraQuestion]'))
BEGIN
    CREATE TABLE OP.ExtraQuestion (
      id int IDENTITY PRIMARY KEY,
      ExtraRunID int NOT NULL REFERENCES OP.ExtraRun(id),
      SortIndex tinyint NOT NULL,
      TypeCode nvarchar(16) NOT NULL,
      Prompt nvarchar(max) NOT NULL,
      TimeSec int NOT NULL,
      MediaKey nvarchar(200) NULL,
      StatusCode nvarchar(16) NOT NULL,
      StartedAtUtc datetimeoffset NULL,
      StoppedAtUtc datetimeoffset NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraQuestionOption]'))
BEGIN
    CREATE TABLE OP.ExtraQuestionOption (
      id int IDENTITY PRIMARY KEY,
      ExtraQuestionID int NOT NULL REFERENCES OP.ExtraQuestion(id),
      ListType nvarchar(50) NOT NULL,
      Value nvarchar(max) NOT NULL,
      SortIndex int NOT NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraQuestionCorrectAnswer]'))
BEGIN
    CREATE TABLE OP.ExtraQuestionCorrectAnswer (
      id int IDENTITY PRIMARY KEY,
      ExtraQuestionID int NOT NULL REFERENCES OP.ExtraQuestion(id),
      OptionID int NULL REFERENCES OP.ExtraQuestionOption(id),
      MatchOptionID int NULL REFERENCES OP.ExtraQuestionOption(id),
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraAnswer]'))
BEGIN
    CREATE TABLE OP.ExtraAnswer (
      id int IDENTITY PRIMARY KEY,
      ExtraQuestionID int NOT NULL REFERENCES OP.ExtraQuestion(id),
      EventUserID bigint NOT NULL,
      ReceivedAtUtc datetimeoffset NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_ExtraAnswer ON OP.ExtraAnswer (ExtraQuestionID, EventUserID) WHERE ActiveFlg = 1;
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraAnswerItem]'))
BEGIN
    CREATE TABLE OP.ExtraAnswerItem (
      id int IDENTITY PRIMARY KEY,
      ExtraAnswerID int NOT NULL REFERENCES OP.ExtraAnswer(id),
      OptionID int NULL REFERENCES OP.ExtraQuestionOption(id),
      MatchOptionID int NULL REFERENCES OP.ExtraQuestionOption(id),
      SortIndex int NULL,
      TextValue nvarchar(500) NULL
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[ExtraScore]'))
BEGIN
    CREATE TABLE OP.ExtraScore (
      ExtraRunID int NOT NULL,
      TeamID int NOT NULL,
      Points int NOT NULL,
      PRIMARY KEY (ExtraRunID, TeamID)
    );
END

-- =============================================
-- Büntetések és Média
-- =============================================

-- Penalty: Kézi + vagy - pont a szervezőtől
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Penalty]'))
BEGIN
    CREATE TABLE OP.Penalty (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      TeamID int NOT NULL,
      Points int NOT NULL,
      UndoOfID int NULL,
      CreatedAtUtc datetimeoffset NOT NULL DEFAULT SYSDATETIMEOFFSET(),
      ActiveFlg bit NOT NULL DEFAULT 1
    );
END

-- Media: Tárhely (Azure Blob) kapcsolat képeknek, hangoknak
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[Media]'))
BEGIN
    CREATE TABLE OP.Media (
      id int IDENTITY PRIMARY KEY,
      EventID bigint NOT NULL,
      MediaKey nvarchar(200) NOT NULL,
      BlobUrl nvarchar(1000) NOT NULL,
      ContentHash nvarchar(64) NOT NULL,
      Mime nvarchar(80) NOT NULL,
      ActiveFlg bit NOT NULL DEFAULT 1
    );
    CREATE UNIQUE INDEX UX_OP_Media ON OP.Media (EventID, MediaKey) WHERE ActiveFlg = 1;
END

-- DisplayToken: Kivetítő párosítási token PIN kóddal
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[DisplayToken]'))
BEGIN
    CREATE TABLE OP.DisplayToken (
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
