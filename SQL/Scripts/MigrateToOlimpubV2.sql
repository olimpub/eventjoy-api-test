BEGIN TRAN;
GO

-- 1. Új Szótár Táblák Létrehozása
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblRoundType]'))
BEGIN
    CREATE TABLE OP.tblRoundType (
        id INT IDENTITY PRIMARY KEY,
        Code VARCHAR(50) NOT NULL UNIQUE,
        Name NVARCHAR(100) NOT NULL,
        RawsMode VARCHAR(20) NOT NULL,    
        FGivenMode VARCHAR(20) NOT NULL,  
        FPointMode VARCHAR(20) NOT NULL   
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblRoundTypeFixedPoints]'))
BEGIN
    CREATE TABLE OP.tblRoundTypeFixedPoints (
        RoundTypeID INT NOT NULL REFERENCES OP.tblRoundType(id),
        RankPlace INT NOT NULL,
        Points INT NOT NULL,
        PRIMARY KEY (RoundTypeID, RankPlace)
    );
END

IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblPenaltyType]'))
BEGIN
    CREATE TABLE OP.tblPenaltyType (
        id INT IDENTITY PRIMARY KEY,
        Code VARCHAR(50) NOT NULL UNIQUE,
        Name NVARCHAR(100) NOT NULL,
        DefaultPoints INT NOT NULL
    );
END
GO

-- 2. Alapadatok Feltöltése
IF NOT EXISTS (SELECT 1 FROM OP.tblRoundType)
BEGIN
    INSERT INTO OP.tblRoundType (Code, Name, RawsMode, FGivenMode, FPointMode)
    VALUES 
    ('main_quiz', 'Fő Kvíz', 'team', 'after_round', 'dynamic'),
    ('duel_speed', 'Párbaj', 'fastest', 'after_question', 'fixed'),
    ('fast_5', 'Gyorsasági', 'fastest', 'after_round', 'fixed'),
    ('manual_display', 'Kézi Vezérlés (Mozaik/Karaoke)', 'none', 'none', 'none');

    DECLARE @DuelId INT = (SELECT id FROM OP.tblRoundType WHERE Code = 'duel_speed');
    INSERT INTO OP.tblRoundTypeFixedPoints (RoundTypeID, RankPlace, Points)
    VALUES (@DuelId, 1, 20), (@DuelId, 2, 10), (@DuelId, 3, 5);

    DECLARE @Fast5Id INT = (SELECT id FROM OP.tblRoundType WHERE Code = 'fast_5');
    INSERT INTO OP.tblRoundTypeFixedPoints (RoundTypeID, RankPlace, Points)
    VALUES (@Fast5Id, 1, 50), (@Fast5Id, 2, 40), (@Fast5Id, 3, 30), (@Fast5Id, 4, 20), (@Fast5Id, 5, 10);

    INSERT INTO OP.tblPenaltyType (Code, Name, DefaultPoints)
    VALUES 
    ('mozaik_correct', 'Mozaik Helyes Válasz', 10),
    ('karaoke_pro', 'Karaoke Bónusz', 20),
    ('cheat', 'Puskázás', -10),
    ('manual_plus', 'Kézi Bónusz', 10),
    ('manual_minus', 'Kézi Levonás', -10);
END
GO

-- 3. Meglévő Táblák Bővítése (ALTER)
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblRound]') AND name = 'RoundTypeID')
BEGIN
    ALTER TABLE OP.tblRound ADD RoundTypeID INT NULL REFERENCES OP.tblRoundType(id);
END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblRound]') AND name = 'OldExtraRunID')
BEGIN
    ALTER TABLE OP.tblRound ADD OldExtraRunID INT NULL;
END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblPenalty]') AND name = 'PenaltyTypeID')
BEGIN
    ALTER TABLE OP.tblPenalty ADD PenaltyTypeID INT NULL REFERENCES OP.tblPenaltyType(id);
END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblEventQuestion]') AND name = 'OldExtraQuestionID')
BEGIN
    ALTER TABLE OP.tblEventQuestion ADD OldExtraQuestionID INT NULL;
END
IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblAnswer]') AND name = 'OldExtraAnswerID')
BEGIN
    ALTER TABLE OP.tblAnswer ADD OldExtraAnswerID INT NULL;
END
GO

-- Data Update for existing Rounds and Penalties
DECLARE @MainQuizId INT = (SELECT id FROM OP.tblRoundType WHERE Code = 'main_quiz');
DECLARE @ManualPlusId INT = (SELECT id FROM OP.tblPenaltyType WHERE Code = 'manual_plus');
DECLARE @ManualMinusId INT = (SELECT id FROM OP.tblPenaltyType WHERE Code = 'manual_minus');

UPDATE OP.tblRound SET RoundTypeID = @MainQuizId WHERE RoundTypeID IS NULL;
UPDATE OP.tblPenalty SET PenaltyTypeID = CASE WHEN Points > 0 THEN @ManualPlusId ELSE @ManualMinusId END WHERE PenaltyTypeID IS NULL;

-- ALTER TABLE OP.tblRound ALTER COLUMN RoundTypeID INT NOT NULL; -- Let's skip NOT NULL for now to avoid errors if there are empty tables
GO

-- 4. Adatok Migrálása
IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraRun]'))
BEGIN
    INSERT INTO OP.tblRound (EventID, TopicID, Mode, StatusCode, Picker, SortIndex, ActiveFlg, RoundTypeID, OldExtraRunID)
    SELECT 
        er.EventID, NULL, 'pick', er.StatusCode, NULL, 100 + er.id, 1,
        CASE 
            WHEN er.ExtraGameId = 'EG1' THEN (SELECT id FROM OP.tblRoundType WHERE Code = 'duel_speed')
            WHEN er.ExtraGameId IN ('EG2', 'EG3') THEN (SELECT id FROM OP.tblRoundType WHERE Code = 'manual_display')
            ELSE (SELECT id FROM OP.tblRoundType WHERE Code = 'fast_5')
        END, er.id
    FROM OP.tblExtraRun er;
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraQuestion]'))
BEGIN
    INSERT INTO OP.tblEventQuestion (EventID, RoundID, QuestionID, SortIndex, StatusCode, StartedAtUtc, StoppedAtUtc, TimeSec, ActiveFlg, OldExtraQuestionID)
    SELECT 
        r.EventID, r.id, 
        ISNULL((SELECT TOP 1 id FROM OP.tblQuestion q WHERE q.Prompt = eq.Prompt), (SELECT TOP 1 id FROM OP.tblQuestion)), 
        eq.SortIndex, eq.StatusCode, eq.StartedAtUtc, eq.StoppedAtUtc, eq.TimeSec, 1, eq.id
    FROM OP.tblExtraQuestion eq
    JOIN OP.tblRound r ON eq.ExtraRunID = r.OldExtraRunID;
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraAnswer]'))
BEGIN
    INSERT INTO OP.tblAnswer (EventQuestionID, EventUserID, ReceivedAtUtc, ActiveFlg, OldExtraAnswerID)
    SELECT neq.id, ea.EventUserID, ea.ReceivedAtUtc, ea.ActiveFlg, ea.id
    FROM OP.tblExtraAnswer ea
    JOIN OP.tblEventQuestion neq ON ea.ExtraQuestionID = neq.OldExtraQuestionID;
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraAnswerItem]'))
BEGIN
    INSERT INTO OP.tblAnswerItem (AnswerID, OptionID, MatchOptionID, SortIndex, TextValue)
    SELECT na.id, NULL, NULL, eai.SortIndex, eai.TextValue
    FROM OP.tblExtraAnswerItem eai
    JOIN OP.tblAnswer na ON eai.ExtraAnswerID = na.OldExtraAnswerID;
END
GO

IF EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblExtraScore]'))
BEGIN
    INSERT INTO OP.tblRoundScore (RoundID, TeamID, RawSSum, Place, F)
    SELECT r.id, es.TeamID, 0, 1, es.Points
    FROM OP.tblExtraScore es
    JOIN OP.tblRound r ON es.ExtraRunID = r.OldExtraRunID;
END
GO

-- Takarítás
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblRound]') AND name = 'OldExtraRunID')
BEGIN
    ALTER TABLE OP.tblRound DROP COLUMN OldExtraRunID;
END
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblEventQuestion]') AND name = 'OldExtraQuestionID')
BEGIN
    ALTER TABLE OP.tblEventQuestion DROP COLUMN OldExtraQuestionID;
END
IF EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblAnswer]') AND name = 'OldExtraAnswerID')
BEGIN
    ALTER TABLE OP.tblAnswer DROP COLUMN OldExtraAnswerID;
END
GO

-- 5. Drop Extra Tables
DROP TABLE IF EXISTS OP.tblExtraAnswerItem;
DROP TABLE IF EXISTS OP.tblExtraAnswer;
DROP TABLE IF EXISTS OP.tblExtraQuestionCorrectAnswer;
DROP TABLE IF EXISTS OP.tblExtraQuestionOption;
DROP TABLE IF EXISTS OP.tblExtraScore;
DROP TABLE IF EXISTS OP.tblExtraQuestion;
DROP TABLE IF EXISTS OP.tblExtraRun;
GO

COMMIT;
GO
