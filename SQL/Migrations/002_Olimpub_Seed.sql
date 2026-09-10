-- =============================================
-- Olimpub (OP) Seed Data
-- Alapadatok (Témakörök, Kabalák) betöltése
-- =============================================

BEGIN TRAN;

-- 1. Témakörök (Topics)
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Zene')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Zene', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Történelem')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Történelem', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Filmek')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Filmek', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Földrajz')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Földrajz', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Irodalom')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Irodalom', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Sport')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Sport', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Természettudomány')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Természettudomány', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = 'Vegyes')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('Vegyes', 60, 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Topic] WHERE Name = '90-es évek')
    INSERT INTO [OP].[Topic] (Name, DefaultRunningTimeSec, ActiveFlg) VALUES ('90-es évek', 60, 1);

-- 2. Kabalák (Kabalas)
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Kék Oroszlán')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Kék Oroszlán', '/assets/kabalas/lion.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Zöld Béka')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Zöld Béka', '/assets/kabalas/frog.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Sárga Kacsa')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Sárga Kacsa', '/assets/kabalas/duck.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Piros Rókák')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Piros Rókák', '/assets/kabalas/fox.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Lila Bölly')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Lila Bölly', '/assets/kabalas/owl.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Barna Medve')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Barna Medve', '/assets/kabalas/bear.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Fekete Macska')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Fekete Macska', '/assets/kabalas/cat.png', 1);
IF NOT EXISTS (SELECT 1 FROM [OP].[Kabala] WHERE Name = 'Fehér Farkas')
    INSERT INTO [OP].[Kabala] (Name, ImageUrl, ActiveFlg) VALUES ('Fehér Farkas', '/assets/kabalas/wolf.png', 1);

COMMIT;
GO
