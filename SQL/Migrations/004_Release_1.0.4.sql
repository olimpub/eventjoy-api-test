-- =========================================================================
-- EventJoy Release 1.0.4 Migration Script
-- Version: 1.0.4
-- Date: 2026-10-22
-- =========================================================================

SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
GO

DECLARE @VersionNumber NVARCHAR(50) = N'1.0.4';
DECLARE @ReleaseDate DATETIME = GETUTCDATE();
DECLARE @Summary NVARCHAR(MAX) = N'Olimpub V2 fordulómodell (a játékok is fordulók), Mozaik játék és buzzer, kétfázisú órakezelés és szerveroldali kiértékelés, váróterem és szünet képernyők stabilizálása, kivetítő állás és modul-specifikus PIN belépés, valamint kapcsolat-, hibanaplózási és MailerSend webhook fejlesztések.';
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
-- 1. Olimpub: fordulók és játékok
(@VersionID, N'OP-ROUND-1', NULL, N'Olimpub fordulómodell: A játékok mostantól fordulók (RoundTypeCode): a main_quiz a Fordulók alatt, minden más (Párbaj, Gyorsasági, Mozaik, Karaoke) a Játékok alatt jelenik meg a Quiz menüben és a Kvízmester katalógusban is, külön szekcióban, típus- és kérdésszám-jelöléssel.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-ROUND-2', NULL, N'Olimpub adatforrás: A külön Extra játék Pinia táblák és kérdéskészlet-kiválasztók megszűntek; a backendtől érkező fordulók és kérdések jelentik az egyetlen adatforrást.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-ROUND-3', NULL, N'Párbaj és órakezelés: Párbaj (Csak zene) és nem main_quiz fordulóknál nincs 3 mp-es felolvasás, a kérdés azonnal opciókkal jelenik meg és fut a válaszóra; a Generációk és a Fő kvíz megtartja a felolvasási/bevezető fázist (ClockPaused = 1, majd Op.StartClock).', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-NO-OPT-1', NULL, N'Szóbeli / opció nélküli kérdéstípus (no_options): Új kérdéstípus (pl. Karaoke és szóbeli feladatokhoz), ahol a játékos telefonján nincs opció és nem fut óra, a kvízmester látja az opcionális megoldást, a pontozás pedig kézzel (Op.AdjustTeam: manual_plus / manual_minus) történik.', 1, GETUTCDATE(), GETUTCDATE()),

-- 2. Mozaik
(@VersionID, N'OP-MOZAIK-1', NULL, N'Mozaik tippelés (Buzzer): A játékosnál Tippelj gomb jelenik meg; atomi első-nyomó rögzítéssel (Op.MosaicBuzz) az első tippelő nyer, az óra befagyasztásra kerül, és mindenki (beleértve a kivetítőt is) a nyertes tippelő nevét és csapatát látja.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-MOZAIK-2', NULL, N'Mozaik bírálat és kizárás: A kvízmester csapatszinten értékeli a tippet (jó vagy rossz); rossz tipp (mozaik_wrong) esetén a kiesett csapat az adott kérdésben nem tippelhet újra (MosaicOutTeamIds), az óra pedig továbbindul.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-MOZAIK-3', NULL, N'Mozaik vezérlés és szinkron: Két mozaikkérdés között a „Folytatás" nem indítja el automatikusan a következő kérdést és az órát, a tipp után pedig a telefon ellenőrzi a szerver állapotát.', 1, GETUTCDATE(), GETUTCDATE()),

-- 3. Játékos telefon
(@VersionID, N'OP-PLAYER-1', NULL, N'Játékos képernyőváltások: A váróterem, a szünet és a kérdés képernyő között megszűnt a villanás (a csapatválasztó nem ugrik fel indításkor, az Indítás nem dob vissza váróterembe).', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-PLAYER-2', NULL, N'Szünet képernyő és azonnali kérdésépítés: A szünet képernyőn „X/Y" kérdésszámláló látszik a típus és a téma mellett; a telefon az indító SignalR pingből azonnal felépíti a kérdéslapot külön lekérdezés nélkül.', 1, GETUTCDATE(), GETUTCDATE()),

-- 4. Kvízmester
(@VersionID, N'OP-QM-1', NULL, N'Kvízmester fordulókezelés: Ha a kvízmester indítás nélkül lép ki egy fordulóból, az nem vált „Folyamatban" állapotra és nem lép a második kérdésre; forduló elhagyásakor a játékosok a váróba kerülnek, a kivetítő pedig az alap képernyőre vált.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'OP-QM-2', NULL, N'Kvízmester csapatlista és hanglejátszó: A forduló képernyőn a csapatlista azonnal csak a játékossal rendelkező csapatokat mutatja; a hanglejátszó sávjában a tekerés helyi blobról akkor is működik, ha a szerver nem támogatja a Range kéréseket.', 1, GETUTCDATE(), GETUTCDATE()),

-- 5. Kivetítő
(@VersionID, N'DISP-OP-1', NULL, N'Olimpub kivetítő eredmények és váróterem: Animált forduló állás (nyers pontokból) és forduló vége (OpResultsBoard fali nézet); a váróterem létszámába csak az online játékosok (LastSeenUtc / Presence) számítanak bele.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'DISP-OP-2', NULL, N'Kivetítő óra és PIN belépés: A kérdés kivetítésén az olvasási visszaszámlálás nem torzul tartás (hold) állapotban; a PIN-es kivetítő belépés és token-validálás az Olimpub modulra (Module = ''op'') és Kvízmester szerepkörre is működik.', 1, GETUTCDATE(), GETUTCDATE()),

-- 6. Kapcsolat, PTA és hibanaplózás
(@VersionID, N'SYS-CONN-1', NULL, N'SignalR stabilitás és görgetés: Elutasított csatlakozás (401/403) után a watchdog 2 percig nem próbálkozik újra, sikeres csatlakozáskor pedig újratölti az élő állapotot (useOpLiveResync); oldalváltáskor a görgetés a tetejére ugrik, fül- és szűrőváltáskor viszont megmarad.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'PTA-UI-1', NULL, N'PTA és felület javítások: Az ülésrend fal nem omlasztja össze a Chrome-ot monitorváltáskor, a kék lakat a lezártnak számító asztalokon is látszik, az Organizer oldalon a csempék és KPI-k szűk kijelzőn sem lógnak ki, a kliensoldali hibanapló pedig tartalmazza az útvonalat és a súlyosságot.', 1, GETUTCDATE(), GETUTCDATE()),

-- 7. Backend (BE) motor, pontozás és e-mail követés
(@VersionID, N'BE-CARD-1', NULL, N'Backend kérdéslap és kiértékelés: A helyes válaszokat (CorrectJson) csak a személyzet kapja meg; az Op.SubmitAnswer szerveroldalon értékeli ki az összes kérdéstípust (single, multi, order, match, category, freetext), és SignalR-en csak a válaszadók számát (AnswerCount, RosterCount) publikálja.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'BE-SCORE-1', NULL, N'Backend pontozás és tabella: Aktív színpadi/manuális forduló alatt az Op.AdjustTeam (+Pont / -Pont) közvetlenül a kérdés és a forduló pontszámát frissíti duplikáció nélkül; az Op.CloseRound dinamikus F-pont számításában csak a ténylegesen válaszoló csapatok és játékosok vesznek részt.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'BE-PRESENCE-1', NULL, N'Backend jelenlét és kivetítő hitelesítés: Valós idejű játékos jelenlét (LastSeenUtc) és automatikus Op.Presence SignalR értesítés offline-ból online állapotba lépéskor; Bearer DisplayToken támogatás és TV csoport-kizárás a SignalR és Olimpub végpontokon.', 1, GETUTCDATE(), GETUTCDATE()),
(@VersionID, N'BE-MAIL-1', NULL, N'MailerSend webhook és státusz követés: Háttérfolyamatba (Task.Run) szervezett webhook feldolgozás és GET/HEAD támogatás a 2 mp-es timeout tartásához, valamint intelligens címzett-alapú visszakeresés (EJ.spUpdateEmailOutboxProviderStatus) tömeges e-mail kiküldésnél.', 1, GETUTCDATE(), GETUTCDATE());
GO
