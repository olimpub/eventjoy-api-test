-- =========================================================================
-- EventJoy Release 1.0.3 Migration Script
-- Version: 1.0.3
-- Date: 2026-10-14
-- =========================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @VersionNumber NVARCHAR(50) = N'1.0.3';
DECLARE @ReleaseDate DATETIME = GETUTCDATE();
DECLARE @Summary NVARCHAR(MAX) = N'PTA sorsolás és pontozás optimalizálása, személyes QR belépő kódok és eszközkötés (játékos és játékmester), Olimpub egyszerűsített fordulók, valamint kivetítés és fejléc fejlesztések.';
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
-- PTA sorsolás
(@VersionID, N'PTA-DRAW-1', NULL, N'PTA sorsolás: Ha az asztalszám nem stimmel a belépett játékosokkal, a véglegesítés le van tiltva, és kiírja, hány asztal kellene.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PTA-DRAW-2', NULL, N'PTA sorsolás: Későbbi mentés nem törli a játékosok szervezetnevét.', 1, GETUTCDATE(), GETUTCDATE()),

-- Olimpub
(@VersionID, N'OLIM-ROUND-1', NULL, N'Olimpub: A forduló típusa egyszerűsödött: Fő kvíz, Párbaj, Gyorsasági, Színpad.', 1, GETUTCDATE(), GETUTCDATE()),

-- Kivetítés és teljes képernyő
(@VersionID, N'DISP-ROUND-1', NULL, N'Kivetítés: Lezárt forduló is kivetíthető, nem csak a publikált. A játékos telefonja továbbra is csak a publikált eredményt látja.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'DISP-SELECT-1', NULL, N'Kivetítés: A vetítésválasztó üresen indul. Játékosok, Csoportok és Dobogó csak választott, lezárt vagy publikált fordulóra megy. Ha nincs ilyen forduló, a három gomb nem él.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'DISP-WARN-1', NULL, N'Kivetítés: Ha nem az utolsó lezárt fordulót választják, figyelmeztetés jön. Dobogónál akkor is, ha nincs minden forduló lezárva.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'DISP-STAND-1', NULL, N'Kivetítés: Ülésrend és Forduló állás továbbra is a nyitott fordulót veszi.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'DISP-HDMI-1', NULL, N'Kivetítés: A személyzet HDMI-fala a lezárt forduló pontjait is mutatja.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'UI-FULLSCREEN-1', NULL, N'Kivetítés és felület: Új teljes képernyő gomb a fejlécben.', 1, GETUTCDATE(), GETUTCDATE()),

-- Belépő kód
(@VersionID, N'PASS-QR-1', NULL, N'Belépő kód: A résztvevő adatlapján, játékos és játékmester sornál, személyes QR van. A saját telefon bejelentkezik, e-mail és kód nélkül, és ehhez az eszközhöz kötődik.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PASS-CHECKIN-1', NULL, N'Belépő kód: Ha az esemény már bejelentkezésen vagy azon túl van, megnyílik az adatlap. Játékosnál ez Belépett státuszt is jelent. Játékmesternél a státusz nem változik. Előtte várakozó képernyő.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PASS-BIND-1', NULL, N'Belépő kód: Másik telefon ugyanazzal a kóddal nem lép be. Elveszett telefonhoz az Új kód ad másikat.', 1, GETUTCDATE(), GETUTCDATE()),

-- Pontozás
(@VersionID, N'SCORE-GM-1', NULL, N'Pontozás: Üres asztalt a mentés a pontozó játékmesterhez köti. Más játékmester asztalát is lehet pontozni, és a mentés után az asztal az övé lesz.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'SCORE-ROUND-1', NULL, N'Pontozás: A fordulót csak a szervező lépteti Folyamatban állapotba. A játékmester mentése ezt nem teszi meg.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'SCORE-LOCK-1', NULL, N'Pontozás: Lezárt vagy lejátszott asztalt a játékmester nem ír át. A szervező igen.', 1, GETUTCDATE(), GETUTCDATE()),

-- Fejléc
(@VersionID, N'UI-HEADER-1', NULL, N'Fejléc: A hírfolyam, az értesítés és a chat ikon ideiglenesen rejtve van, hogy mobilon elférjen a logó, a súgó és a teljes képernyő.', 1, GETUTCDATE(), GETUTCDATE()),

-- Backend (BE) módosítások
(@VersionID, N'BE-PARTICIPANT-1', NULL, N'Backend: Résztvevők adatlapján szervezetnév megjelenítése (spGetEventUserDataSheet), valamint e-mail küldési engedély (EmailSendingEnabled) figyelembe vétele importálásnál és kiküldésnél.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'BE-SOCIAL-1', NULL, N'Backend: Social Bónusz és arcade minijáték végpontok, valamint PTA camelCase és PascalCase JSON kulcsok felkészítése mentéskor.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'BE-PASS-1', NULL, N'Backend: Személyes belépő kód végpontok (POST /auth/player-pass, POST /auth/player-device-join) és SQL tárolt eljárások (EJ.tblPlayerDevicePass, spCreateOrGetPlayerPass, spJoinPlayerDevicePass) JWT hitelesítéssel.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'BE-SCORE-1', NULL, N'Backend: Rugalmas játékmesteri pontozás az EJ.spChangeEvent eljárásban (bármely játékmester és szervező pontozhat, mentéskor az asztal hozzárendelődik).', 1, GETUTCDATE(), GETUTCDATE()),

-- Még nem commitolt tételek
(@VersionID, N'DEV-UNCOMMITTED-1', NULL, N'[Még nincs commitolva] Backend: Belépő kód tábla és eljárások (tblPlayerDevicePass, spCreateOrGetPlayerPass, spJoinPlayerDevicePass, PlayerPassEndpoints), valamint a módosított játékmesteri pontozás (EJ.spChangeEvent).', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'DEV-UNCOMMITTED-2', NULL, N'[Még nincs commitolva] Frontend: Személyes QR belépő kód felületek (PlayerPassSheet, PlayerPassPage, playerDevicePass), kivetítés és teljes képernyő finomhangolások, játékmesteri asztalvédelem és mobilos fejléc.', 1, GETUTCDATE(), GETUTCDATE());
GO
