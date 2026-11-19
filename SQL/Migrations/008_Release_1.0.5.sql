-- =========================================================================
-- EventJoy Release 1.0.5 Migration Script
-- Version: 1.0.5
-- Date: 2026-11-19
-- =========================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @VersionNumber NVARCHAR(50) = N'1.0.5';
DECLARE @ReleaseDate DATETIME = GETUTCDATE();
DECLARE @Summary NVARCHAR(MAX) = N'PROFI-T-ABILITY négyes döntő játéktípus (3 fordulós + döntő), eseményszintű különdíjak és interaktív sorsolás a kivetítőn, egyéni pontszámítás kapcsoló (Pontot kap), csoportos összesített kivetítő nézet, továbbfejlesztett több szerepkörös és csoportfrissítő Excel meghívó import, valamint elkülönített éles (app.eventjoy.hu) és teszt (apptest.eventjoy.hu) környezet.';
DECLARE @LastUpdatedUserID BIGINT = 3;

-- 1. Verzió felvitele vagy frissítése
DECLARE @VersionID INT;

SELECT @VersionID = id 
FROM [EJ].[tblAppVersion] 
WHERE VersionNumber = @VersionNumber;

IF @VersionID IS NULL
BEGIN
    INSERT INTO [EJ].[tblAppVersion] (
        VersionNumber,
        ReleaseDate,
        Summary,
        ActiveFlg,
        LastUpdatedUserID,
        createdAt,
        updatedAt
    ) VALUES (
        @VersionNumber,
        @ReleaseDate,
        @Summary,
        1,
        @LastUpdatedUserID,
        GETUTCDATE(),
        GETUTCDATE()
    );

    SET @VersionID = SCOPE_IDENTITY();
END
ELSE
BEGIN
    UPDATE [EJ].[tblAppVersion]
    SET ReleaseDate = @ReleaseDate,
        Summary = @Summary,
        ActiveFlg = 1,
        LastUpdatedUserID = @LastUpdatedUserID,
        updatedAt = GETUTCDATE()
    WHERE id = @VersionID;

    -- Korábbi tételek törlése az újrafuttathatóság érdekében
    DELETE FROM [EJ].[tblAppVersionItem]
    WHERE VersionID = @VersionID;
END

-- 2. Verzió tételeinek beszúrása
INSERT INTO [EJ].[tblAppVersionItem] (
    VersionID,
    InternalReference,
    ExternalReference,
    Description,
    ActiveFlg,
    createdAt,
    updatedAt
) VALUES
-- 1. PTA Négyes döntő
(@VersionID, N'PTA-FINAL-1', NULL, N'Négyes döntő játéktípus (3 fordulós + döntő): Az első három közös forduló lezárása után a szervező egy gombnyomással asztalhoz ültetheti a legjobb 4 játékost (Pta.SeatFinal) helyezés szerinti színkiosztással (1. piros, 2. kék, 3. sárga, 4. zöld).', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PTA-FINAL-2', NULL, N'Döntő végeredmény és pontszámítás: A döntő asztal pontjai nem adódnak hozzá az egyéni vagy csoportos összesítéshez; a döntő publikálása után az 1–4. helyet a döntő asztal sorrendje adja pontszám nélkül, az 5. helytől pedig a három elődöntő forduló állása rangsorol.', 1, GETUTCDATE(), GETUTCDATE()),

-- 2. PTA Különdíjak és Kivetítő
(@VersionID, N'PTA-PRIZE-1', NULL, N'Eseményszintű különdíjak (Meglepetés és Súlyozott sorsolás): Az eseményvarázslóban egyedi névvel kapcsolható be a két különdíj (PTA.tblEventSpecialPrize), a kihirdetett nyertest pedig a rendszer megőrzi újratöltés és eseményszerkesztés után is (Pta.SetSpecialPrizeWinner).', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PTA-PRIZE-2', NULL, N'Interaktív különdíj kivetítés és lezárt fordulók: A kivetítő vezérlőjén külön különdíj szekció érhető el újrahúzható sorsolással és látványos névforgató animációval a falon; a kivetítő adatlekérdezése (PTA.spGetEventDisplayData) már a lezárt (4) fordulók pontjait is átadja a különdíj-számításhoz.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PTA-DISP-1', NULL, N'Csoportvetítés és forduló-feliratok: A csoportos kivetítés egységes összesített listában mutatja a csoport összpontszámát és alatta a tagok egyéni pontjait; a fordulók felirata mindenhol a játéktípus sablon sorszámát (OrderIndex) és nevét (RName) követi.', 1, GETUTCDATE(), GETUTCDATE()),

-- 3. PTA Pontot kap kapcsoló
(@VersionID, N'PTA-SCORE-1', NULL, N'Pontot kap kapcsoló (ScoreCountFlg): A játékos szerkesztőlapján kikapcsolható a pontszámítás (Pta.SetScoreCount) — a játékos továbbra is asztalhoz ülhet és rögzíthető az asztali eredménye, de nem szerepel az egyéni/csoportos rangsorokban, a dobogón, a döntőbe jutásban és a különdíjakban, a beállítás pedig újrasorsoláskor is megmarad.', 1, GETUTCDATE(), GETUTCDATE()),

-- 4. Meghívó import és adatmegőrzés
(@VersionID, N'INV-IMP-1', NULL, N'Több szerepkörös és frissítő Excel meghívó import (EJ.spImportInvitations): Ugyanaz az e-mail cím több szerepkörben (pl. Játékos és Játékmester) is importálható; a már bent lévő szerepkör újraimportálása hiba helyett frissíti a jegyet és a csoportosítási adatokat (pl. Régió, Csapat, Szervezet, Cég) felesleges új meghívó e-mail és belépőkód-csere nélkül.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PTA-RESET-1', NULL, N'Csoportosítási adatok védelme Reset és Sorsolás során: A sorsolás visszaállítása (Pta.Reset) és újragenerálása (Pta.ReplaceDraw) megőrzi az importált játékosok régió-, csapat-, cég- és szervezet-besorolását az adatbázisban.', 1, GETUTCDATE(), GETUTCDATE()),

-- 5. Infrastruktúra
(@VersionID, N'INFRA-ENV-1', NULL, N'Éles és teszt környezet szétválasztása: Éles indulás az app.eventjoy.hu / api.eventjoy.hu domaineken automatikus átirányítással a korábbi testapp címről, valamint dedikált, izolált teszt környezet az apptest.eventjoy.hu / apitest.eventjoy.hu alatt.', 1, GETUTCDATE(), GETUTCDATE());
GO
