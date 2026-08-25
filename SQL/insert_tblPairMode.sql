USE [YourDatabaseName]; -- Kérlek írd át a megfelelő adatbázis névre!
GO

INSERT INTO [PTA].[tblPairMode] 
    ([PName], [PDesc], [PairGameFlg], [FixedGroupFlg], [SameGroupFlg])
VALUES
    -- 1. Egyéni játék
    -- Nem páros játék, nincsenek fix vagy azonos csapatra vonatkozó szabályok
    (N'Egyéni játék', N'Egyéni játék', 0, 0, 0),

    -- 2. Random páros
    -- Páros játék, de a párok véletlenszerűek (nem fix), és nem feltétel az azonos csapat
    (N'Random páros', N'Véletlenszerű sorsolás alapján', 1, 0, 0),

    -- 3. Fix Páros
    -- Páros játék, ahol a párok előre rögzítettek (fix), de nem feltétel az azonos csapat
    (N'Fix Páros', N'Előre megadott fix párosok', 1, 1, 0),

    -- 4. Páros azonos csapatból
    -- Páros játék, ahol a párosítás csak azonos csapaton/csoporton belül történhet
    (N'Páros azonos csapatból', N'Párosítás azonos csapatból', 1, 0, 1);
GO
