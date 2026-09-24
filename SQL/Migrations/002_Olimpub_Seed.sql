SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
-- =============================================
-- Olimpub (OP) Seed Data
-- =============================================

BEGIN TRAN;

-- 1. Témakörök (Topics)
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Zene') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Zene', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Történelem') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Történelem', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Filmek') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Filmek', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Földrajz') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Földrajz', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Irodalom') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Irodalom', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Sport') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Sport', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Természettudomány') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Természettudomány', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = 'Vegyes') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('Vegyes', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblTopic] WHERE Name = '90-es évek') INSERT INTO [OP].[tblTopic] (Name, ActiveFlg) VALUES ('90-es évek', 1);

-- 2. Kabalák (Kabalas)
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Kék Oroszlán') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Kék Oroszlán', '/assets/kabalas/lion.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Zöld Béka') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Zöld Béka', '/assets/kabalas/frog.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Sárga Kacsa') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Sárga Kacsa', '/assets/kabalas/duck.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Piros Rókák') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Piros Rókák', '/assets/kabalas/fox.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Lila Bagoly') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Lila Bagoly', '/assets/kabalas/owl.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Barna Medve') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Barna Medve', '/assets/kabalas/bear.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Fekete Macska') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Fekete Macska', '/assets/kabalas/cat.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblKabala] WHERE Name = 'Fehér Farkas') INSERT INTO [OP].[tblKabala] (Name, ImageUrl, ActiveFlg) VALUES ('Fehér Farkas', '/assets/kabalas/wolf.png', 1);

-- 3. Kérdéstípusok (QuestionType)
IF NOT EXISTS (SELECT 1 FROM [OP].[tblQuestionType] WHERE Code = 'single') INSERT INTO [OP].[tblQuestionType] (Code, Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('single', 'Egyválasztós', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblQuestionType] WHERE Code = 'multi') INSERT INTO [OP].[tblQuestionType] (Code, Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('multi', 'Többválasztós', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblQuestionType] WHERE Code = 'order') INSERT INTO [OP].[tblQuestionType] (Code, Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('order', 'Sorrendező', 90, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblQuestionType] WHERE Code = 'match') INSERT INTO [OP].[tblQuestionType] (Code, Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('match', 'Párosító', 90, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblQuestionType] WHERE Code = 'category') INSERT INTO [OP].[tblQuestionType] (Code, Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('category', 'Kategorizáló', 90, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblQuestionType] WHERE Code = 'freetext') INSERT INTO [OP].[tblQuestionType] (Code, Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('freetext', 'Szabadszöveges', 60, 1);

-- 4. Forduló státuszok (RoundStatus)
IF NOT EXISTS (SELECT 1 FROM [OP].[tblRoundStatus] WHERE Code = 'pending') INSERT INTO [OP].[tblRoundStatus] (Code, Name, ActiveFlg) VALUES ('pending', 'Várakozik', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblRoundStatus] WHERE Code = 'active') INSERT INTO [OP].[tblRoundStatus] (Code, Name, ActiveFlg) VALUES ('active', 'Aktív', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblRoundStatus] WHERE Code = 'closed') INSERT INTO [OP].[tblRoundStatus] (Code, Name, ActiveFlg) VALUES ('closed', 'Lezárva', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[tblRoundStatus] WHERE Code = 'published') INSERT INTO [OP].[tblRoundStatus] (Code, Name, ActiveFlg) VALUES ('published', 'Eredmény publikálva', 1);

COMMIT;
GO
