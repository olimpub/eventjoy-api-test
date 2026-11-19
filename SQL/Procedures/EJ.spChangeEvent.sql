SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spChangeEvent]
    @Json NVARCHAR(MAX),
    @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @Action NVARCHAR(64) = JSON_VALUE(@Json, '$.Action');
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        DECLARE @TargetEventUserIDs TABLE (ID INT);
        DECLARE @SignalRTargets TABLE (TargetGroup NVARCHAR(100), EventName NVARCHAR(100), CustomPayload NVARCHAR(MAX));
        DECLARE @InsertedFinalSchedules TABLE (
            GameScheduleID INT,
            EventRoundDeskID INT,
            PlayerID INT,
            PlayColorHex VARCHAR(16),
            SeatNo INT,
            ActiveFlg BIT
        );

        IF @EventID IS NULL
        BEGIN
            THROW 50000, N'EventID is required', 1;
        END

        IF @Action = N'Event.SetStatus'
        BEGIN
            DECLARE @EventToStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            DECLARE @EventPrevStatusID INT = JSON_VALUE(@Json, '$.Payload.PrevStatusID');
            
            UPDATE [EJ].[tblEvent]
            SET EventStatusID = @EventToStatusID,
                PrevEventStatusID = @EventPrevStatusID,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id = @EventID;
        END
        ELSE IF @Action = N'EventUser.SetStatus'
        BEGIN
            DECLARE @EuToStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            DECLARE @EuPrevStatusID INT = JSON_VALUE(@Json, '$.Payload.PrevStatusID');
            
            -- 1. Batch ID-k
            IF JSON_QUERY(@Json, '$.Payload.EventUserIDs') IS NOT NULL
            BEGIN
                INSERT INTO @TargetEventUserIDs (ID)
                SELECT CAST(value AS INT)
                FROM OPENJSON(@Json, '$.Payload.EventUserIDs');
            END
            -- 2. Single ID
            ELSE IF JSON_VALUE(@Json, '$.Payload.EventUserID') IS NOT NULL
            BEGIN
                INSERT INTO @TargetEventUserIDs (ID)
                VALUES (JSON_VALUE(@Json, '$.Payload.EventUserID'));
            END
            -- 3. UID
            ELSE IF JSON_VALUE(@Json, '$.Payload.EventUserUID') IS NOT NULL
            BEGIN
                DECLARE @EuUID UNIQUEIDENTIFIER = CAST(JSON_VALUE(@Json, '$.Payload.EventUserUID') AS UNIQUEIDENTIFIER);
                INSERT INTO @TargetEventUserIDs (ID)
                SELECT id FROM [EJ].[tblEventUser] WHERE EventUserUID = @EuUID AND EventID = @EventID;
            END

            -- Update EventUsers
            UPDATE [EJ].[tblEventUser]
            SET EventUserStatusID = @EuToStatusID,
                PrevEventUserStatusID = CASE WHEN @EuPrevStatusID IS NULL THEN PrevEventUserStatusID ELSE @EuPrevStatusID END,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id IN (SELECT ID FROM @TargetEventUserIDs)
              AND EventID = @EventID;
        END
        ELSE IF @Action = N'Pta.ShowDisplay'
        BEGIN
            IF NOT EXISTS (
                SELECT 1 FROM [EJ].[tblEventUser] eu
                JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
                JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND r.RoleTypeID IN (1, 2)
            )
            BEGIN
                THROW 50403, N'Nincs jogosultságod módosítani a kivetítést.', 1;
            END

            DECLARE @DispState NVARCHAR(16) = JSON_VALUE(@Json, '$.Payload.State');
            DECLARE @DispScope NVARCHAR(16) = JSON_VALUE(@Json, '$.Payload.Scope');
            DECLARE @DispRoundId INT = COALESCE(JSON_VALUE(@Json, '$.Payload.RoundId'), JSON_VALUE(@Json, '$.Payload.EventRoundID'));
            DECLARE @DispGroupKey NVARCHAR(32) = JSON_VALUE(@Json, '$.Payload.GroupKey');
            
            IF @DispGroupKey = 'player' SET @DispGroupKey = NULL;

            IF @DispState = 'leaderboard'
            BEGIN
                IF @DispRoundId IS NULL
                BEGIN
                    THROW 50400, N'Publikált forduló megadása kötelező a leaderboardhoz.', 1;
                END
                
                IF NOT EXISTS (
                    SELECT 1 FROM [PTA].[tblEventRound] r
                    WHERE r.EventRoundID = @DispRoundId AND r.EventID = @EventID AND r.EventRoundStatusID = 5
                )
                BEGIN
                    THROW 50400, N'Előbb publikáld a fordulót.', 1;
                END
            END

            MERGE INTO [PTA].[tblPtaDisplayState] AS target
            USING (SELECT @EventID AS EventID) AS source
            ON target.EventID = source.EventID
            WHEN MATCHED THEN
                UPDATE SET 
                    State = @DispState,
                    Scope = @DispScope,
                    RoundId = @DispRoundId,
                    GroupKey = @DispGroupKey,
                    UpdatedAtUtc = @Now
            WHEN NOT MATCHED THEN
                INSERT (EventID, State, Scope, RoundId, GroupKey, UpdatedAtUtc)
                VALUES (@EventID, @DispState, @DispScope, @DispRoundId, @DispGroupKey, @Now);

            DECLARE @DisplayPayload NVARCHAR(MAX) = (
                SELECT 
                    @Action AS Action,
                    @EventID AS EventID,
                    @DispState AS State,
                    @DispScope AS Scope,
                    @DispRoundId AS RoundId,
                    @DispRoundId AS EventRoundID,
                    @DispGroupKey AS GroupKey
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_display', @Action, @DisplayPayload);
        END
        ELSE IF @Action = N'EventUser.PatchContact'
        BEGIN
            -- Payload.EventUserID + LastName + FirstName + Email + Phone
            -- szervező; tblUser globális módosítás! (specifikáció megváltoztatva)

            IF NOT EXISTS (
                SELECT 1 FROM [EJ].[tblEventUser] eu
                JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
                JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID AND eu.EventID = @EventID AND r.RoleTypeID = 1 AND eu.ActiveFlg = 1
            )
            BEGIN
                THROW 50403, N'Nincs jogosultságod módosítani a résztvevő adatait.', 1;
            END

            DECLARE @PatchEventUserID BIGINT = JSON_VALUE(@Json, '$.Payload.EventUserID');
            DECLARE @PatchLastName NVARCHAR(100) = JSON_VALUE(@Json, '$.Payload.LastName');
            DECLARE @PatchFirstName NVARCHAR(100) = JSON_VALUE(@Json, '$.Payload.FirstName');
            DECLARE @PatchEmail NVARCHAR(250) = JSON_VALUE(@Json, '$.Payload.Email');
            DECLARE @PatchPhone NVARCHAR(100) = JSON_VALUE(@Json, '$.Payload.Phone');

            IF LTRIM(RTRIM(ISNULL(@PatchLastName, ''))) = '' OR LTRIM(RTRIM(ISNULL(@PatchFirstName, ''))) = ''
            BEGIN
                THROW 50400, N'A vezetéknév és a keresztnév megadása kötelező.', 1;
            END

            IF LTRIM(RTRIM(ISNULL(@PatchEmail, ''))) = ''
            BEGIN
                THROW 50400, N'Add meg az e-mail címet.', 1;
            END

            IF @PatchEmail NOT LIKE '%_@__%.__%'
            BEGIN
                THROW 50400, N'Érvénytelen e-mail cím.', 1;
            END

            -- HU Phone validation
            IF LTRIM(RTRIM(ISNULL(@PatchPhone, ''))) = '' SET @PatchPhone = NULL;

            IF @PatchPhone IS NOT NULL AND (@PatchPhone NOT LIKE '+36%' AND @PatchPhone NOT LIKE '06%' AND @PatchPhone NOT LIKE '36%')
            BEGIN
                THROW 50400, N'Érvénytelen telefonszám.', 1;
            END

            DECLARE @TargetUserIDToPatch BIGINT = (SELECT UserID FROM [EJ].[tblEventUser] WHERE id = @PatchEventUserID AND EventID = @EventID AND ActiveFlg = 1);
            IF @TargetUserIDToPatch IS NULL
            BEGIN
                THROW 50404, N'A résztvevő nem található.', 1;
            END

            -- Check duplication ON THE SAME EVENT
            IF EXISTS (
                SELECT 1 FROM [EJ].[tblEventUser] eu
                JOIN [EJ].[tblUser] u ON eu.UserID = u.id
                WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1 AND eu.id <> @PatchEventUserID
                AND (LOWER(u.EmailAddress) = LOWER(@PatchEmail) OR (u.PhoneNumber IS NOT NULL AND u.PhoneNumber = @PatchPhone))
            )
            BEGIN
                THROW 50409, N'Ez a résztvevő már szerepel a listán.', 1;
            END
            
            -- ALSO check global email duplication (because EmailAddress is unique in tblUserLoginIdentifier / tblUser)
            IF EXISTS (
                SELECT 1 FROM [EJ].[tblUser] WHERE LOWER(EmailAddress) = LOWER(@PatchEmail) AND id <> @TargetUserIDToPatch
            )
            BEGIN
                THROW 50409, N'Ez az e-mail cím már egy másik felhasználóhoz tartozik a rendszerben. Nem lehet módosítani.', 1;
            END

            UPDATE [EJ].[tblUser]
            SET LastName = @PatchLastName,
                FirstName = @PatchFirstName,
                EmailAddress = LOWER(@PatchEmail),
                PhoneNumber = @PatchPhone,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id = @TargetUserIDToPatch;

            UPDATE [EJ].[tblUserLoginIdentifier]
            SET IdentifierValueRaw = LOWER(@PatchEmail),
                IdentifierValueNormalized = LOWER(@PatchEmail),
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE UserID = @TargetUserIDToPatch AND IdentifierTypeID = 1;

            UPDATE [PTA].[tblEventPlayer]
            SET NickName = @PatchLastName + ' ' + @PatchFirstName,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE EventUserID = @PatchEventUserID AND EventID = @EventID;

            INSERT INTO @TargetEventUserIDs (ID) VALUES (@PatchEventUserID);
        END
        ELSE IF @Action = N'EventUser.Apply'
        BEGIN
            DECLARE @ApplyTicketID INT = JSON_VALUE(@Json, '$.Payload.EventTicketID');
            -- Kikeressük az adott jegyhez tartozó RoleID-t
            DECLARE @ApplyRoleID INT = (SELECT TOP 1 EventRoleID FROM [EJ].[tblEventRoleTicket] WHERE EventTicketID = @ApplyTicketID);
            
            INSERT INTO [EJ].[tblEventUser] (EventID, UserID, EventRoleID, EventTicketID, EventUserStatusID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, @UserID, @ApplyRoleID, @ApplyTicketID, 1, 1, @UserID, @Now, @Now);
        END
        ELSE IF @Action = N'EventUser.Remove'
        BEGIN
            DECLARE @RemoveEventUserID INT = JSON_VALUE(@Json, '$.Payload.EventUserID');
            UPDATE [EJ].[tblEventUser] 
            SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now 
            WHERE id = @RemoveEventUserID AND EventID = @EventID;
        END
        ELSE IF @Action = N'EventUser.SetRating'
        BEGIN
            DECLARE @RatingEventUserID INT = JSON_VALUE(@Json, '$.Payload.EventUserID');
            DECLARE @RatingComment NVARCHAR(MAX) = JSON_VALUE(@Json, '$.Payload.RatingComment');

            DECLARE @RatingValue NVARCHAR(MAX), @RatingType INT;
            SELECT @RatingValue = [value], @RatingType = [type]
            FROM OPENJSON(@Json, '$.Payload')
            WHERE [key] = 'Rating';

            IF @RatingType IS NULL
                THROW 50000, N'Érvénytelen értékelés: A Rating mező kötelező.', 1;

            DECLARE @Rating TINYINT = NULL;
            IF @RatingType = 2
            BEGIN
                SET @Rating = CAST(@RatingValue AS TINYINT);
                IF @Rating < 1 OR @Rating > 5
                    THROW 50000, N'Érvénytelen értékelés (1-5 között kell lennie).', 1;
            END
            ELSE IF @RatingType <> 0
            BEGIN
                THROW 50000, N'Érvénytelen értékelés: Szám vagy null elvárt.', 1;
            END

            IF @RatingType = 2 AND LEN(@RatingComment) > 2000
                THROW 50000, N'Az értékelés szövege túl hosszú.', 1;

            -- 2. Résztvevő ellenőrzése
            DECLARE @TargetRoleType INT, @TargetEU_UserID BIGINT, @TargetActive BIT;
            SELECT @TargetRoleType = r.RoleTypeID, @TargetEU_UserID = eu.UserID, @TargetActive = eu.ActiveFlg
            FROM [EJ].[tblEventUser] eu
            JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
            JOIN [EJ].[tblRole] r ON er.RoleID = r.id
            WHERE eu.id = @RatingEventUserID AND eu.EventID = @EventID;

            IF @TargetEU_UserID IS NULL OR @TargetActive = 0
                THROW 50000, N'Érvénytelen vagy inaktív résztvevő.', 1;

            IF @TargetEU_UserID <> @UserID
                THROW 50000, N'Csak a saját részvételedet értékelheted.', 1;

            IF @TargetRoleType = 1
                THROW 50000, N'Szervezők nem értékelhetnek.', 1;

            -- 3. Esemény státusz ellenőrzése
            DECLARE @EvStatusName NVARCHAR(200);
            SELECT @EvStatusName = es.StatusName
            FROM [EJ].[tblEvent] e
            LEFT JOIN [EJ].[tblEventStatus] es ON e.EventStatusID = es.id
            WHERE e.id = @EventID;

            IF LOWER(@EvStatusName) NOT LIKE N'%lezárt%' AND LOWER(@EvStatusName) NOT LIKE N'%vége%' AND LOWER(@EvStatusName) NOT LIKE N'%befejezve%'
                THROW 50000, N'Az esemény még nincs lezárva.', 1;

            -- 4. Értékelés mentése vagy törlése
            IF @RatingType = 0
            BEGIN
                UPDATE [EJ].[tblEventUser]
                SET Rating = NULL,
                    RatingComment = NULL,
                    LastUpdatedUserID = @UserID,
                    updatedAt = @Now
                WHERE id = @RatingEventUserID AND EventID = @EventID;
                
                SET @ReturnDescription = N'Értékelés törölve.';
            END
            ELSE
            BEGIN
                UPDATE [EJ].[tblEventUser]
                SET Rating = @Rating,
                    RatingComment = NULLIF(LTRIM(RTRIM(@RatingComment)), ''),
                    LastUpdatedUserID = @UserID,
                    updatedAt = @Now
                WHERE id = @RatingEventUserID AND EventID = @EventID;
                
                SET @ReturnDescription = N'Értékelés mentve.';
            END

            COMMIT TRANSACTION;

            -- Nincs SignalR / Outbox, itt befejezzük:
            SELECT 1 AS ReturnValue, @ReturnDescription AS ReturnDescription, @EventID AS EventID, @Action AS Action;
            RETURN;
        END
        ELSE IF @Action = N'Pta.ReplaceDraw'
        BEGIN
            IF OBJECT_ID(N'[PTA].[tblEventSpecialPrize]', N'U') IS NOT NULL
            BEGIN
                UPDATE [PTA].[tblEventSpecialPrize]
                SET WinnerEventPlayerID = NULL, LastUpdatedUserID = @UserID, updatedAt = @Now
                WHERE EventID = @EventID AND WinnerEventPlayerID IS NOT NULL;
            END
            -- Mentjük a törlés előtti játékos metaadatokat (csoportok + ScoreCountFlg) EventUserID szerint,
            -- hogy Reset / ReplaceDraw vagy még be nem lépett meghívottak esetén se vesszenek el az importált régiók/csapatok!
            DECLARE @PrevPlayers TABLE (
                EventUserID BIGINT PRIMARY KEY,
                NickName NVARCHAR(100),
                TeamName NVARCHAR(100),
                CompanyName NVARCHAR(100),
                OrganizationName NVARCHAR(100),
                RegionName NVARCHAR(100),
                ScoreCountFlg BIT,
                ActiveFlg BIT
            );
            INSERT INTO @PrevPlayers (EventUserID, NickName, TeamName, CompanyName, OrganizationName, RegionName, ScoreCountFlg, ActiveFlg)
            SELECT
                EventUserID,
                MAX(NickName),
                MAX(TeamName),
                MAX(CompanyName),
                MAX(OrganizationName),
                MAX(RegionName),
                CAST(MIN(CAST(ScoreCountFlg AS INT)) AS BIT),
                CAST(MAX(CAST(ActiveFlg AS INT)) AS BIT)
            FROM [PTA].[tblEventPlayer]
            WHERE EventID = @EventID
              AND EventUserID IS NOT NULL
            GROUP BY EventUserID;

            DELETE FROM [PTA].[tblGameSchedule] WHERE PlayerID IN (SELECT EventPlayerID FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID);
            DELETE FROM [PTA].[tblEventRoundDesk] WHERE EventRoundID IN (SELECT EventRoundID FROM [PTA].[tblEventRound] WHERE EventID = @EventID);
            DELETE FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID;
            DELETE FROM [PTA].[tblEventRound] WHERE EventID = @EventID;
            DELETE FROM [PTA].[tblEventDesk] WHERE EventID = @EventID;

            -- INSERT Desks
            DECLARE @NewDesks TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventDesk] AS target
            USING (
                SELECT TempId, DeskNo, ActiveFlg
                FROM OPENJSON(@Json, '$.Payload.Desks')
                WITH (TempId NVARCHAR(64), DeskNo INT, ActiveFlg BIT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, DeskNumber, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.DeskNo, source.ActiveFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventDeskID, source.TempId INTO @NewDesks;

            -- INSERT Rounds
            DECLARE @NewRounds TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventRound] AS target
            USING (
                SELECT TempId, RoundID, EventRoundStatusID, NoOfDesks
                FROM OPENJSON(@Json, '$.Payload.Rounds')
                WITH (TempId NVARCHAR(64), RoundID INT, EventRoundStatusID INT, NoOfDesks INT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, RoundID, EventRoundStatusID, NoOfDesks, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.RoundID, source.EventRoundStatusID, source.NoOfDesks, @UserID, @Now, @Now)
            OUTPUT inserted.EventRoundID, source.TempId INTO @NewRounds;

            -- INSERT RoundDesks
            DECLARE @NewRoundDesks TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventRoundDesk] AS target
            USING (
                SELECT j.TempId, d.InsertedID AS DeskID, r.InsertedID AS RoundID, j.GameMasterUserID, j.ActiveFlg
                FROM OPENJSON(@Json, '$.Payload.RoundDesks')
                WITH (TempId NVARCHAR(64), DeskTempId NVARCHAR(64), RoundTempId NVARCHAR(64), GameMasterUserID INT, ActiveFlg BIT) j
                JOIN @NewDesks d ON j.DeskTempId = d.TempId
                JOIN @NewRounds r ON j.RoundTempId = r.TempId
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventRoundID, EventDeskID, GameMasterUserID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (source.RoundID, source.DeskID, source.GameMasterUserID, source.ActiveFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventRoundDeskID, source.TempId INTO @NewRoundDesks;

            -- INSERT Players (csoportmezők és ScoreCountFlg átörökítésével: payload -> régi sor -> default)
            DECLARE @NewPlayers TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventPlayer] AS target
            USING (
                SELECT 
                    JSON_VALUE(pJson.[value], '$.TempId') AS TempId, 
                    CAST(JSON_VALUE(pJson.[value], '$.EventUserID') AS BIGINT) AS EventUserID, 
                    COALESCE(NULLIF(LTRIM(RTRIM(COALESCE(JSON_VALUE(pJson.[value], '$.Name'), JSON_VALUE(pJson.[value], '$.name')))), ''), prev.NickName) AS Name, 
                    COALESCE(NULLIF(LTRIM(RTRIM(COALESCE(JSON_VALUE(pJson.[value], '$.TeamName'), JSON_VALUE(pJson.[value], '$.teamName')))), ''), prev.TeamName) AS TeamName, 
                    COALESCE(NULLIF(LTRIM(RTRIM(COALESCE(JSON_VALUE(pJson.[value], '$.CompanyName'), JSON_VALUE(pJson.[value], '$.companyName')))), ''), prev.CompanyName) AS CompanyName, 
                    COALESCE(NULLIF(LTRIM(RTRIM(COALESCE(JSON_VALUE(pJson.[value], '$.OrganizationName'), JSON_VALUE(pJson.[value], '$.organizationName')))), ''), prev.OrganizationName) AS OrganizationName, 
                    COALESCE(NULLIF(LTRIM(RTRIM(COALESCE(JSON_VALUE(pJson.[value], '$.RegionName'), JSON_VALUE(pJson.[value], '$.regionName')))), ''), prev.RegionName) AS RegionName, 
                    CAST(COALESCE(JSON_VALUE(pJson.[value], '$.ActiveFlg'), JSON_VALUE(pJson.[value], '$.activeFlg'), '1') AS BIT) AS ActiveFlg,
                    COALESCE(
                        TRY_CAST(COALESCE(JSON_VALUE(pJson.[value], '$.ScoreCountFlg'), JSON_VALUE(pJson.[value], '$.scoreCountFlg')) AS BIT),
                        prev.ScoreCountFlg,
                        CAST(1 AS BIT)
                    ) AS ScoreCountFlg
                FROM OPENJSON(@Json, '$.Payload.Players') pJson
                LEFT JOIN @PrevPlayers prev
                    ON prev.EventUserID = TRY_CAST(JSON_VALUE(pJson.[value], '$.EventUserID') AS BIGINT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, EventUserID, NickName, TeamName, CompanyName, OrganizationName, RegionName, ActiveFlg, ScoreCountFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.EventUserID, source.Name, source.TeamName, source.CompanyName, source.OrganizationName, source.RegionName, source.ActiveFlg, source.ScoreCountFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventPlayerID, source.TempId INTO @NewPlayers;

            -- Azok a meghívott játékosok (pl. még nem belépett résztvevők), akik nem szerepeltek a sorsolási Payload.Players-ben,
            -- szintén kapják vissza a PTA.tblEventPlayer sorukat, hogy a csoportjaik (RegionName, stb.) és ScoreCountFlg-ük megmaradjon!
            INSERT INTO [PTA].[tblEventPlayer] (EventID, EventUserID, NickName, TeamName, CompanyName, OrganizationName, RegionName, ActiveFlg, ScoreCountFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT @EventID, prev.EventUserID, prev.NickName, prev.TeamName, prev.CompanyName, prev.OrganizationName, prev.RegionName, prev.ActiveFlg, ISNULL(prev.ScoreCountFlg, 1), @UserID, @Now, @Now
            FROM @PrevPlayers prev
            WHERE NOT EXISTS (
                SELECT 1 FROM [PTA].[tblEventPlayer] cur
                WHERE cur.EventID = @EventID AND cur.EventUserID = prev.EventUserID
            );

            -- INSERT Schedules
            INSERT INTO [PTA].[tblGameSchedule] (EventRoundDeskID, PlayerID, PlayColorHex, Amount, OnTrack, Position, ResultPoint, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT rd.InsertedID, p.InsertedID, j.ColorHex, j.Amount, j.OnTrack, j.Position, j.ResultPoint, j.ActiveFlg, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.Payload.Schedules')
            WITH (RoundDeskTempId NVARCHAR(64), PlayerTempId NVARCHAR(64), ColorHex NVARCHAR(10), Amount INT, OnTrack INT, Position INT, ResultPoint INT, ActiveFlg BIT) j
            JOIN @NewRoundDesks rd ON j.RoundDeskTempId = rd.TempId
            JOIN @NewPlayers p ON j.PlayerTempId = p.TempId;

        END
        ELSE IF @Action = N'Pta.SeatFinal'
        BEGIN
            -- 1. Szervezői jogosultság ellenőrzése
            IF NOT EXISTS (
                SELECT 1
                FROM [EJ].[tblEventUser] eu
                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
                INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID
                  AND eu.EventID = @EventID
                  AND eu.ActiveFlg = 1
                  AND (r.RoleName IN (N'Organizer', N'Szervező', N'Házigazda', N'Tulajdonos') OR r.Code IN (N'organizer', N'host', N'owner') OR r.RoleTypeID = 1)
            )
            BEGIN
                THROW 50403, N'Permission Denied: Csak a szervező sorsolhatja a döntőt!', 1;
            END

            DECLARE @SF_EventRoundID INT = JSON_VALUE(@Json, '$.Payload.EventRoundID');
            DECLARE @SF_EventRoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');

            IF @SF_EventRoundID IS NULL OR @SF_EventRoundDeskID IS NULL
            BEGIN
                THROW 50400, N'Hiányzó EventRoundID vagy EventRoundDeskID.', 1;
            END

            -- 2. Az EventRoundID ehhez az EventID-hez tartozik, és a sablonja FinalRoundFlg = 1
            IF NOT EXISTS (
                SELECT 1
                FROM [PTA].[tblEventRound] er
                INNER JOIN [PTA].[tblGameTypeRounds] gtr ON er.RoundID = gtr.RoundID
                WHERE er.EventRoundID = @SF_EventRoundID
                  AND er.EventID = @EventID
                  AND gtr.FinalRoundFlg = 1
            )
            BEGIN
                THROW 50400, N'A megadott forduló nem döntő forduló ezen az eseményen.', 1;
            END

            -- 3. Az EventRoundDeskID ehhez a fordulóhoz tartozik
            IF NOT EXISTS (
                SELECT 1
                FROM [PTA].[tblEventRoundDesk] erd
                WHERE erd.EventRoundDeskID = @SF_EventRoundDeskID
                  AND erd.EventRoundID = @SF_EventRoundID
                  AND erd.ActiveFlg = 1
            )
            BEGIN
                THROW 50400, N'A megadott asztal nem tartozik a döntő fordulóhoz.', 1;
            END

            -- 4. Az asztalon még nincs ülés és nincs eredmény
            IF EXISTS (
                SELECT 1
                FROM [PTA].[tblGameSchedule] gs
                WHERE gs.EventRoundDeskID = @SF_EventRoundDeskID
                  AND (
                      gs.ActiveFlg = 1
                      OR gs.Amount IS NOT NULL
                      OR gs.OnTrack IS NOT NULL
                      OR gs.Position IS NOT NULL
                      OR gs.ResultPoint IS NOT NULL
                  )
            )
            BEGIN
                THROW 50409, N'A döntő asztalon már van ülés vagy rögzített eredmény.', 1;
            END

            -- 5. Pontosan 4 különböző EventPlayerID érkezik, mind az esemény aktív játékosa
            DECLARE @SF_Seats TABLE (
                RowOrd INT IDENTITY(1,1),
                PlayerID INT,
                ColorHex VARCHAR(16),
                ColorIndex INT,
                SeatNo INT
            );

            INSERT INTO @SF_Seats (PlayerID, ColorHex, ColorIndex, SeatNo)
            SELECT PlayerID, ColorHex, ColorIndex, SeatNo
            FROM OPENJSON(@Json, '$.Payload.Seats')
            WITH (
                PlayerID INT '$.PlayerID',
                ColorHex VARCHAR(16) '$.ColorHex',
                ColorIndex INT '$.ColorIndex',
                SeatNo INT '$.SeatNo'
            )
            ORDER BY ISNULL(SeatNo, 99);

            IF (SELECT COUNT(*) FROM @SF_Seats) <> 4
               OR (SELECT COUNT(DISTINCT PlayerID) FROM @SF_Seats WHERE PlayerID IS NOT NULL) <> 4
            BEGIN
                THROW 50400, N'Pontosan 4 különböző játékost kell megadni a döntőhöz.', 1;
            END

            IF (
                SELECT COUNT(*)
                FROM @SF_Seats fs
                INNER JOIN [PTA].[tblEventPlayer] ep ON ep.EventPlayerID = fs.PlayerID
                WHERE ep.EventID = @EventID AND ep.ActiveFlg = 1
            ) <> 4
            BEGIN
                THROW 50400, N'Minden megadott játékosnak az esemény aktív játékosának kell lennie.', 1;
            END

            -- 6. Az előző fordulók le vannak zárva
            IF NOT EXISTS (
                SELECT 1
                FROM [PTA].[tblEventRound] er
                LEFT JOIN [PTA].[tblGameTypeRounds] gtr ON er.RoundID = gtr.RoundID
                WHERE er.EventID = @EventID
                  AND ISNULL(gtr.FinalRoundFlg, 0) = 0
            )
            BEGIN
                THROW 50400, N'Nincs elődöntő forduló az eseményen.', 1;
            END

            IF EXISTS (
                SELECT 1
                FROM [PTA].[tblEventRound] er
                LEFT JOIN [PTA].[tblGameTypeRounds] gtr ON er.RoundID = gtr.RoundID
                LEFT JOIN [PTA].[tblEventRoundStatus] rs ON er.EventRoundStatusID = rs.EventRoundStatusID
                WHERE er.EventID = @EventID
                  AND ISNULL(gtr.FinalRoundFlg, 0) = 0
                  AND er.EventRoundStatusID NOT IN (4, 5)
                  AND ISNULL(rs.SName, N'') NOT IN (N'Lezárt', N'Publikált', N'Közzétett')
                  AND (
                      NOT EXISTS (
                          SELECT 1
                          FROM [PTA].[tblEventRoundDesk] erd0
                          WHERE erd0.EventRoundID = er.EventRoundID AND erd0.ActiveFlg = 1
                      )
                      OR EXISTS (
                          SELECT 1
                          FROM [PTA].[tblEventRoundDesk] erd
                          WHERE erd.EventRoundID = er.EventRoundID
                            AND erd.ActiveFlg = 1
                            AND erd.CompletedAtUtc IS NULL
                            AND NOT EXISTS (
                                SELECT 1
                                FROM [PTA].[tblGameSchedule] gs
                                WHERE gs.EventRoundDeskID = erd.EventRoundDeskID
                                  AND gs.ActiveFlg = 1
                                HAVING COUNT(*) > 0 AND COUNT(*) = COUNT(gs.ResultPoint)
                            )
                      )
                  )
            )
            BEGIN
                THROW 50400, N'A döntő csak akkor sorsolható, ha az előző fordulók le vannak zárva.', 1;
            END

            -- 7. Négy sor mentése a PTA.tblGameSchedule táblába (üres eredménymezőkkel)
            MERGE INTO [PTA].[tblGameSchedule] AS target
            USING (
                SELECT
                    RowOrd,
                    PlayerID,
                    COALESCE(
                        NULLIF(LTRIM(RTRIM(ColorHex)), ''),
                        CASE SeatNo
                            WHEN 1 THEN '#FF6060'
                            WHEN 2 THEN '#2AA9FF'
                            WHEN 3 THEN '#F2E74B'
                            WHEN 4 THEN '#28C76F'
                            ELSE '#FF6060'
                        END
                    ) AS PlayColorHex,
                    ISNULL(SeatNo, RowOrd) AS SeatNo
                FROM @SF_Seats
            ) AS source ON 1 = 0
            WHEN NOT MATCHED THEN
                INSERT (EventRoundDeskID, PlayerID, PlayColorHex, Amount, OnTrack, Position, ResultPoint, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
                VALUES (@SF_EventRoundDeskID, source.PlayerID, source.PlayColorHex, NULL, NULL, NULL, NULL, 1, @UserID, @Now, @Now)
            OUTPUT inserted.GameScheduleID, inserted.EventRoundDeskID, inserted.PlayerID, inserted.PlayColorHex, source.SeatNo, inserted.ActiveFlg
            INTO @InsertedFinalSchedules (GameScheduleID, EventRoundDeskID, PlayerID, PlayColorHex, SeatNo, ActiveFlg);
        END
        ELSE IF @Action IN (N'Pta.SetRoundStatus', N'Pta.CloseRound', N'Pta.PublishRound')
        BEGIN
            DECLARE @RoundID INT = JSON_VALUE(@Json, '$.Payload.EventRoundID');
            DECLARE @RoundStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            
            -- 1. Forduló státusz frissítése
            UPDATE [PTA].[tblEventRound] 
            SET EventRoundStatusID = @RoundStatusID, 
                LastUpdatedUserID = @UserID, 
                updatedAt = @Now 
            WHERE EventRoundID = @RoundID AND EventID = @EventID;

            DECLARE @HasFinalRound BIT = CASE WHEN EXISTS (
                SELECT 1
                FROM [PTA].[tblEventRound] r
                INNER JOIN [PTA].[tblGameTypeRounds] gtr ON r.RoundID = gtr.RoundID
                WHERE r.EventID = @EventID
                  AND gtr.FinalRoundFlg = 1
            ) THEN 1 ELSE 0 END;

            -- 2. Aggregáció
            IF @HasFinalRound = 1
            BEGIN
                -- Döntős játéktípus: a döntő forduló ResultPoint/Amount értékei SOHA nem adódnak hozzá a FinalPoint/FinalTruckPoint-hoz!
                ;WITH PrelimScores AS (
                    SELECT 
                        s.PlayerID, 
                        SUM(ISNULL(CAST(s.ResultPoint AS DECIMAL(18,2)), 0)) AS TotalResultPoint,
                        SUM(ISNULL(CAST(s.Amount AS DECIMAL(18,2)), 0)) AS TotalAmount
                    FROM [PTA].[tblGameSchedule] s
                    INNER JOIN [PTA].[tblEventRoundDesk] rd ON s.EventRoundDeskID = rd.EventRoundDeskID
                    INNER JOIN [PTA].[tblEventRound] r ON rd.EventRoundID = r.EventRoundID
                    LEFT JOIN [PTA].[tblGameTypeRounds] gtr ON r.RoundID = gtr.RoundID
                    WHERE r.EventID = @EventID 
                      AND s.ActiveFlg = 1
                      AND ISNULL(gtr.FinalRoundFlg, 0) = 0
                    GROUP BY s.PlayerID
                )
                UPDATE p
                SET 
                    p.FinalPoint = CASE WHEN p.ScoreCountFlg = 1 THEN a.TotalResultPoint ELSE NULL END,
                    p.FinalTruckPoint = CASE WHEN p.ScoreCountFlg = 1 THEN a.TotalAmount ELSE NULL END,
                    p.FinalPosition = NULL,
                    p.LastUpdatedUserID = @UserID,
                    p.updatedAt = @Now
                FROM [PTA].[tblEventPlayer] p
                LEFT JOIN PrelimScores a ON p.EventPlayerID = a.PlayerID
                WHERE p.EventID = @EventID
                  AND p.ActiveFlg = 1;

                -- Ha a döntő publikálva van, és mind a négy ülésnek van Position értéke:
                -- a négy döntős FinalPoint = NULL, FinalTruckPoint = NULL, FinalPosition = Position (1–4) (csak ha ScoreCountFlg = 1)
                DECLARE @PublishedFinalRoundID INT = (
                    SELECT TOP 1 r.EventRoundID
                    FROM [PTA].[tblEventRound] r
                    INNER JOIN [PTA].[tblGameTypeRounds] gtr ON r.RoundID = gtr.RoundID
                    LEFT JOIN [PTA].[tblEventRoundStatus] rs ON r.EventRoundStatusID = rs.EventRoundStatusID
                    WHERE r.EventID = @EventID
                      AND gtr.FinalRoundFlg = 1
                      AND (r.EventRoundStatusID = 5 OR ISNULL(rs.SName, N'') IN (N'Publikált', N'Közzétett'))
                );

                IF @PublishedFinalRoundID IS NOT NULL
                   AND (
                       SELECT COUNT(*)
                       FROM [PTA].[tblGameSchedule] gs
                       INNER JOIN [PTA].[tblEventRoundDesk] rd ON gs.EventRoundDeskID = rd.EventRoundDeskID
                       WHERE rd.EventRoundID = @PublishedFinalRoundID
                         AND rd.ActiveFlg = 1
                         AND gs.ActiveFlg = 1
                   ) = 4
                   AND (
                       SELECT COUNT(*)
                       FROM [PTA].[tblGameSchedule] gs
                       INNER JOIN [PTA].[tblEventRoundDesk] rd ON gs.EventRoundDeskID = rd.EventRoundDeskID
                       WHERE rd.EventRoundID = @PublishedFinalRoundID
                         AND rd.ActiveFlg = 1
                         AND gs.ActiveFlg = 1
                         AND gs.Position IS NOT NULL
                   ) = 4
                BEGIN
                    UPDATE p
                    SET
                        p.FinalPoint = NULL,
                        p.FinalTruckPoint = NULL,
                        p.FinalPosition = fs.Position,
                        p.LastUpdatedUserID = @UserID,
                        p.updatedAt = @Now
                    FROM [PTA].[tblEventPlayer] p
                    INNER JOIN (
                        SELECT gs.PlayerID, gs.Position
                        FROM [PTA].[tblGameSchedule] gs
                        INNER JOIN [PTA].[tblEventRoundDesk] rd ON gs.EventRoundDeskID = rd.EventRoundDeskID
                        WHERE rd.EventRoundID = @PublishedFinalRoundID
                          AND rd.ActiveFlg = 1
                          AND gs.ActiveFlg = 1
                    ) fs ON p.EventPlayerID = fs.PlayerID
                    WHERE p.EventID = @EventID
                      AND p.ScoreCountFlg = 1;
                END
            END
            ELSE IF @Action IN (N'Pta.CloseRound', N'Pta.PublishRound')
            BEGIN
                ;WITH AggregatedScores AS (
                    SELECT 
                        s.PlayerID, 
                        SUM(ISNULL(CAST(s.ResultPoint AS DECIMAL(18,2)), 0)) AS TotalResultPoint,
                        SUM(ISNULL(CAST(s.Amount AS DECIMAL(18,2)), 0)) AS TotalAmount
                    FROM [PTA].[tblGameSchedule] s
                    INNER JOIN [PTA].[tblEventRoundDesk] rd ON s.EventRoundDeskID = rd.EventRoundDeskID
                    INNER JOIN [PTA].[tblEventRound] r ON rd.EventRoundID = r.EventRoundID
                    WHERE r.EventID = @EventID 
                      AND s.ActiveFlg = 1
                    GROUP BY s.PlayerID
                )
                UPDATE p
                SET 
                    p.FinalPoint = CASE WHEN p.ScoreCountFlg = 1 THEN a.TotalResultPoint ELSE NULL END,
                    p.FinalTruckPoint = CASE WHEN p.ScoreCountFlg = 1 THEN a.TotalAmount ELSE NULL END,
                    p.FinalPosition = CASE WHEN p.ScoreCountFlg = 1 THEN p.FinalPosition ELSE NULL END,
                    p.LastUpdatedUserID = @UserID,
                    p.updatedAt = @Now
                FROM [PTA].[tblEventPlayer] p
                LEFT JOIN AggregatedScores a ON p.EventPlayerID = a.PlayerID
                WHERE p.EventID = @EventID
                  AND p.ActiveFlg = 1;
            END
        END
        ELSE IF @Action = N'Pta.SetDeskResults'
        BEGIN
            DECLARE @RoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');

            -- KAPU VALIDĂCIÓK
            -- 1. Esemény státusz ellenőrzése
            DECLARE @EventStatusName NVARCHAR(200) = (SELECT s.StatusName FROM [EJ].[tblEvent] e INNER JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id WHERE e.id = @EventID);
            IF LOWER(REPLACE(REPLACE(@EventStatusName, N'á', N'a'), N'é', N'e')) NOT LIKE N'%jatek%'
            BEGIN
                THROW 50003, N'Permission Denied: Az esemény státusza nem Játék!', 1;
            END

            -- 2. Forduló státusz ellenőrzése
            DECLARE @CurrentRoundID INT;
            DECLARE @CurrentRoundStatusName NVARCHAR(50);
            DECLARE @GameMasterUserID BIGINT;
            
            SELECT 
                @CurrentRoundID = r.EventRoundID,
                @CurrentRoundStatusName = rs.SName,
                @GameMasterUserID = rd.GameMasterUserID
            FROM [PTA].[tblEventRoundDesk] rd
            INNER JOIN [PTA].[tblEventRound] r ON rd.EventRoundID = r.EventRoundID
            INNER JOIN [PTA].[tblEventRoundStatus] rs ON r.EventRoundStatusID = rs.EventRoundStatusID
            WHERE rd.EventRoundDeskID = @RoundDeskID;

            IF @CurrentRoundStatusName IN (N'Lezárt', N'Publikált', N'Közzétett')
            BEGIN
                THROW 50004, N'Permission Denied: A forduló már lezárt vagy publikált!', 1;
            END

            -- 3. Hívó ellenőrzése (GM vagy Szervező)
            DECLARE @IsOrganizer BIT = (SELECT CASE WHEN EXISTS (
                SELECT 1 FROM [EJ].[tblEventUser] eu 
                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id 
                INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID AND eu.EventID = @EventID AND eu.ActiveFlg = 1
                  AND (r.RoleName IN (N'Organizer', N'Szervező', N'Házigazda', N'Tulajdonos') OR r.Code IN (N'organizer', N'host', N'owner') OR r.RoleTypeID = 1)
            ) THEN 1 ELSE 0 END);

            DECLARE @IsGameMaster BIT = (SELECT CASE WHEN EXISTS (
                SELECT 1 FROM [EJ].[tblEventUser] eu 
                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id 
                INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID AND eu.EventID = @EventID AND eu.ActiveFlg = 1
                  AND (r.RoleName IN (N'Játékmester', N'Game Master', N'Gamemaster', N'Munkatárs') OR r.Code IN (N'game_master', N'staff') OR r.RoleTypeID = 2)
            ) THEN 1 ELSE 0 END);
            
            IF @IsOrganizer = 0 AND @IsGameMaster = 0 AND (@GameMasterUserID IS NULL OR @GameMasterUserID <> @UserID)
            BEGIN
                THROW 50005, N'Permission Denied: Csak a Játékmester vagy Szervező pontozhat!', 1;
            END

            -- Ha a hívó Játékmester, vagy az asztalnak nincs még GM-je, beállítjuk az asztalhoz
            IF @IsGameMaster = 1 OR @GameMasterUserID IS NULL
            BEGIN
                UPDATE [PTA].[tblEventRoundDesk]
                SET GameMasterUserID = @UserID,
                    LastUpdatedUserID = @UserID,
                    updatedAt = @Now
                WHERE EventRoundDeskID = @RoundDeskID;
            END

            -- EREDMÉNY MENTÉSE
            UPDATE s
            SET Amount = j.Amount,
                OnTrack = j.OnTrack,
                Position = j.Position,
                ResultPoint = j.ResultPoint,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            FROM [PTA].[tblGameSchedule] s
            JOIN OPENJSON(@Json, '$.Payload.Seats')
            WITH (PlayerID INT, Amount DECIMAL(18,2), OnTrack INT, Position INT, ResultPoint INT) j
            ON s.PlayerID = j.PlayerID
            WHERE s.EventRoundDeskID = @RoundDeskID;

            -- AUTO-PROGRESS FOLYAMATBAN-RA
            IF @CurrentRoundStatusName IN (N'Megnyitva', N'Kisorsolva')
            BEGIN
                DECLARE @FolyamatbanStatusID INT = (SELECT TOP 1 EventRoundStatusID FROM [PTA].[tblEventRoundStatus] WHERE SName = N'Folyamatban');
                IF @FolyamatbanStatusID IS NOT NULL
                BEGIN
                    UPDATE [PTA].[tblEventRound] SET EventRoundStatusID = @FolyamatbanStatusID, LastUpdatedUserID = @UserID, updatedAt = @Now WHERE EventRoundID = @CurrentRoundID;
                    
                    DECLARE @AutoPayload NVARCHAR(MAX) = JSON_QUERY((
                        SELECT @CurrentRoundID AS EventRoundID, @FolyamatbanStatusID AS ToStatusID 
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    ));

                    -- SignalR Outbox a gamer, organizer és contributor csoportokra
                    INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
                    VALUES 
                        ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', 'Pta.SetRoundStatus', @AutoPayload),
                        ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', 'Pta.SetRoundStatus', @AutoPayload),
                        ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', 'Pta.SetRoundStatus', @AutoPayload);
                END
            END
        END
        ELSE IF @Action = N'Pta.ClaimDesk'
        BEGIN
            DECLARE @ClaimRoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');
            DECLARE @ClaimGameMasterUserID INT = JSON_VALUE(@Json, '$.Payload.GameMasterUserID');

            IF @ClaimRoundDeskID IS NOT NULL
            BEGIN
                UPDATE [PTA].[tblEventRoundDesk] 
                SET GameMasterUserID = @ClaimGameMasterUserID, LastUpdatedUserID = @UserID, updatedAt = @Now 
                WHERE EventRoundDeskID = @ClaimRoundDeskID;
            END
        END
        ELSE IF @Action = N'Pta.PatchDesk'
        BEGIN
            DECLARE @PatchRoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');
            DECLARE @PatchPhotoUrl NVARCHAR(500) = JSON_VALUE(@Json, '$.Payload.PhotoUrl');
            DECLARE @PatchSName NVARCHAR(50) = JSON_VALUE(@Json, '$.Payload.SName');
            
            -- Ha SName = 'Lezárt', akkor beállítjuk a CompletedAtUtc-t
            DECLARE @NewCompletedAt DATETIMEOFFSET = NULL;
            IF @PatchSName = N'Lezárt'
            BEGIN
                SET @NewCompletedAt = @Now;
            END

            UPDATE [PTA].[tblEventRoundDesk]
            SET AzurePhotoUrl = COALESCE(@PatchPhotoUrl, AzurePhotoUrl),
                CompletedAtUtc = COALESCE(@NewCompletedAt, CompletedAtUtc),
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE EventRoundDeskID = @PatchRoundDeskID;
        END
        ELSE IF @Action = N'Pta.Reset'
        BEGIN
            DECLARE @ResetToStatusID INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            
            IF OBJECT_ID(N'[PTA].[tblEventSpecialPrize]', N'U') IS NOT NULL
            BEGIN
                UPDATE [PTA].[tblEventSpecialPrize]
                SET WinnerEventPlayerID = NULL, LastUpdatedUserID = @UserID, updatedAt = @Now
                WHERE EventID = @EventID AND WinnerEventPlayerID IS NOT NULL;
            END
            DELETE FROM [PTA].[tblGameSchedule] WHERE PlayerID IN (SELECT EventPlayerID FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID);
            DELETE FROM [PTA].[tblEventRoundDesk] WHERE EventRoundID IN (SELECT EventRoundID FROM [PTA].[tblEventRound] WHERE EventID = @EventID);
            -- NEM töröljük a PTA.tblEventPlayer sorokat Resetkor, mert itt vannak tárolva az importált csoportok (RegionName, TeamName, OrganizationName, CompanyName) és a ScoreCountFlg! Csak az eredményeket nullázzuk:
            UPDATE [PTA].[tblEventPlayer]
            SET FinalPoint = NULL,
                FinalTruckPoint = NULL,
                FinalPosition = NULL,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE EventID = @EventID;
            DELETE FROM [PTA].[tblEventRound] WHERE EventID = @EventID;
            DELETE FROM [PTA].[tblEventDesk] WHERE EventID = @EventID;

            UPDATE [EJ].[tblEvent]
            SET EventStatusID = @ResetToStatusID,
                PrevEventStatusID = NULL,
                PendingApprovalID = NULL,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE id = @EventID;
        END
        ELSE IF @Action = N'Pta.SetSpecialPrizeWinner'
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM [EJ].[tblEventUser] eu
                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
                INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID
                  AND eu.EventID = @EventID
                  AND eu.ActiveFlg = 1
                  AND (r.RoleName IN (N'Organizer', N'Szervező', N'Házigazda', N'Tulajdonos') OR r.Code IN (N'organizer', N'host', N'owner') OR r.RoleTypeID = 1)
            )
            BEGIN
                THROW 50403, N'Permission Denied: Csak a szervező hirdethet különdíj-nyertest!', 1;
            END

            DECLARE @SPW_PrizeKind NVARCHAR(16) = LOWER(LTRIM(RTRIM(JSON_VALUE(@Json, '$.Payload.PrizeKind'))));
            DECLARE @SPW_WinnerID INT = TRY_CAST(JSON_VALUE(@Json, '$.Payload.WinnerEventPlayerID') AS INT);

            IF @SPW_PrizeKind IS NULL OR @SPW_PrizeKind NOT IN (N'surprise', N'weighted')
            BEGIN
                THROW 50400, N'Érvénytelen különdíj típus (PrizeKind).', 1;
            END

            IF NOT EXISTS (
                SELECT 1
                FROM [PTA].[tblEventSpecialPrize]
                WHERE EventID = @EventID
                  AND PrizeKind = @SPW_PrizeKind
                  AND LTRIM(RTRIM(PrizeName)) <> N''
            )
            BEGIN
                THROW 50404, N'Ez a különdíj nincs bekapcsolva ezen az eseményen.', 1;
            END

            IF @SPW_WinnerID IS NULL OR NOT EXISTS (
                SELECT 1
                FROM [PTA].[tblEventPlayer]
                WHERE EventPlayerID = @SPW_WinnerID
                  AND EventID = @EventID
                  AND ActiveFlg = 1
            )
            BEGIN
                THROW 50400, N'A megadott nyertes nem aktív játékosa az eseménynek.', 1;
            END

            UPDATE [PTA].[tblEventSpecialPrize]
            SET WinnerEventPlayerID = @SPW_WinnerID,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE EventID = @EventID
              AND PrizeKind = @SPW_PrizeKind;
        END
        ELSE IF @Action = N'Pta.SetScoreCount'
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM [EJ].[tblEventUser] eu
                INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
                INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID
                  AND eu.EventID = @EventID
                  AND eu.ActiveFlg = 1
                  AND (r.RoleName IN (N'Organizer', N'Szervező', N'Házigazda', N'Tulajdonos') OR r.Code IN (N'organizer', N'host', N'owner') OR r.RoleTypeID = 1)
            )
            BEGIN
                THROW 50403, N'Permission Denied: Csak a szervező módosíthatja a pontszámítás flaget!', 1;
            END

            DECLARE @SSC_EventPlayerID INT = TRY_CAST(JSON_VALUE(@Json, '$.Payload.EventPlayerID') AS INT);
            IF @SSC_EventPlayerID IS NULL OR NOT EXISTS (
                SELECT 1
                FROM [PTA].[tblEventPlayer]
                WHERE EventPlayerID = @SSC_EventPlayerID
                  AND EventID = @EventID
                  AND ActiveFlg = 1
            )
            BEGIN
                THROW 50404, N'A megadott játékos nem található ezen az eseményen.', 1;
            END

            DECLARE @SSC_RawVal NVARCHAR(16), @SSC_Type INT;
            SELECT TOP 1 @SSC_RawVal = [value], @SSC_Type = [type]
            FROM OPENJSON(@Json, '$.Payload')
            WHERE [key] IN ('ScoreCountFlg', 'scoreCountFlg');

            DECLARE @SSC_ScoreCountFlg BIT = CASE
                WHEN @SSC_Type IN (1, 2, 3) AND LOWER(@SSC_RawVal) IN ('true', '1') THEN CAST(1 AS BIT)
                WHEN @SSC_Type IN (1, 2, 3) AND LOWER(@SSC_RawVal) IN ('false', '0') THEN CAST(0 AS BIT)
                ELSE NULL
            END;

            IF @SSC_ScoreCountFlg IS NULL
            BEGIN
                THROW 50400, N'A ScoreCountFlg mező megadása kötelező (true/false vagy 1/0).', 1;
            END

            UPDATE [PTA].[tblEventPlayer]
            SET ScoreCountFlg = @SSC_ScoreCountFlg,
                FinalPoint = CASE WHEN @SSC_ScoreCountFlg = 0 THEN NULL ELSE FinalPoint END,
                FinalTruckPoint = CASE WHEN @SSC_ScoreCountFlg = 0 THEN NULL ELSE FinalTruckPoint END,
                FinalPosition = CASE WHEN @SSC_ScoreCountFlg = 0 THEN NULL ELSE FinalPosition END,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            WHERE EventPlayerID = @SSC_EventPlayerID
              AND EventID = @EventID;
        END
        ELSE
        BEGIN
            THROW 50002, N'Ismeretlen Action', 1;
        END

        COMMIT TRANSACTION;
        
        -- RS1: API response
        SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID, @Action AS Action;

        -- RS2: SignalR Hotload (Dinamikus kiküldés a tblEventActionRule alapján)
        DECLARE @HotloadJson NVARCHAR(MAX) = (
            SELECT 
                @EventID AS EventID,
                @Action AS Action,
                JSON_QUERY(@Json, '$.Payload') AS Payload 
            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
        );

        -- 1. Lekérdezzük a szabályt az adatbázisból
        DECLARE @OrgNotify BIT, @ContNotify BIT, @PartNotify BIT, @UserNotify BIT, @GroupNotify BIT;
        SELECT 
            @OrgNotify = OrganizerNotifyFlg,
            @ContNotify = ContributorNotifyFlg,
            @PartNotify = ParticipantNotifyFlg,
            @UserNotify = UserNotifyFlg,
            @GroupNotify = GroupNotifyFlg
        FROM [EJ].[tblEventActionRule]
        WHERE [Action] = @Action AND ActiveFlg = 1;

        -- Ha nincs benne a táblában a szabály, biztonsági hálóként küldjük mindenkinek
        IF @OrgNotify IS NULL
        BEGIN
            SET @OrgNotify = 1; SET @ContNotify = 1; SET @PartNotify = 1; SET @UserNotify = 0; SET @GroupNotify = 0;
        END

        -- 2. Alapértelmezett (visszhang) Célcsoportok generálása
        IF @Action NOT IN (N'Pta.SetRoundStatus', N'Pta.CloseRound', N'Pta.PublishRound', N'Pta.ShowDisplay', N'Pta.SeatFinal', N'Pta.SetSpecialPrizeWinner', N'Pta.SetScoreCount')
        BEGIN
            IF @OrgNotify = 1 INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_organizer', @Action, @HotloadJson);
            IF @ContNotify = 1 INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_contributor', @Action, @HotloadJson);
            IF @PartNotify = 1 
            BEGIN
                INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_participant', @Action, @HotloadJson);
                INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload) VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @HotloadJson);
            END
        END
        
        IF @UserNotify = 1
        BEGIN
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            SELECT 'event_' + CAST(@EventID AS VARCHAR) + '_user_' + CAST(ID AS VARCHAR), @Action, @HotloadJson
            FROM @TargetEventUserIDs;
        END

        -- GROUP csatorna logikát eltávolítottuk, a kliensek már nem csatlakoznak rá.

        -- 3. EGYEDI JĂTÉKOS-ÉRTESëTÉSEK FORDULÓ ZĂRĂSKOR
        -- Ha PublishRound történt, kiküldjük egyenként a privát csatornájukra
        IF @Action = N'Pta.SeatFinal'
        BEGIN
            DECLARE @SeatFinalRoundID_Var INT = JSON_VALUE(@Json, '$.Payload.EventRoundID');
            DECLARE @SeatFinalRoundDeskID_Var INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');

            DECLARE @SeatFinalPayload NVARCHAR(MAX) = (
                SELECT
                    @EventID AS EventID,
                    @Action AS Action,
                    JSON_QUERY((
                        SELECT
                            @SeatFinalRoundID_Var AS EventRoundID,
                            @SeatFinalRoundDeskID_Var AS EventRoundDeskID,
                            JSON_QUERY(@Json, '$.Payload.Seats') AS Seats,
                            JSON_QUERY((
                                SELECT
                                    GameScheduleID,
                                    EventRoundDeskID,
                                    PlayerID,
                                    PlayColorHex,
                                    PlayColorHex AS ColorHex,
                                    SeatNo,
                                    ActiveFlg
                                FROM @InsertedFinalSchedules
                                ORDER BY SeatNo
                                FOR JSON PATH
                            )) AS Schedules
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @SeatFinalPayload);
        END

        IF @Action IN (N'Pta.SetSpecialPrizeWinner', N'Pta.SetScoreCount')
        BEGIN
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @HotloadJson);
        END

        IF @Action = N'Pta.PublishRound'
        BEGIN
            DECLARE @RoundID_Var INT = JSON_VALUE(@Json, '$.Payload.EventRoundID');
            DECLARE @RoundStatusID_Var INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            SELECT 
                'event_' + CAST(@EventID AS VARCHAR) + '_user_' + CAST(ep.EventUserID AS VARCHAR),
                @Action,
                (
                    SELECT 
                        @EventID AS EventID,
                        @Action AS Action,
                        JSON_QUERY((
                            SELECT 
                                @RoundID_Var AS EventRoundID,
                                @RoundStatusID_Var AS ToStatusID,
                                JSON_QUERY(CASE WHEN gs.PlayerID IS NOT NULL THEN (
                                    SELECT 
                                        gs.PlayerID,
                                        gs.EventRoundDeskID,
                                        gs.Amount,
                                        gs.OnTrack,
                                        gs.Position,
                                        gs.ResultPoint
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
                                ) ELSE NULL END) AS Seat,
                                JSON_QUERY((
                                    SELECT 
                                        ep.EventPlayerID,
                                        ep.FinalPoint,
                                        ep.FinalTruckPoint,
                                        ep.FinalPosition
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER, INCLUDE_NULL_VALUES
                                )) AS Player
                            FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                        )) AS Payload
                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                )
            FROM [PTA].[tblEventPlayer] ep
            OUTER APPLY (
                SELECT TOP 1 gs.PlayerID, gs.EventRoundDeskID, gs.Amount, gs.OnTrack, gs.Position, gs.ResultPoint
                FROM [PTA].[tblGameSchedule] gs
                INNER JOIN [PTA].[tblEventRoundDesk] rd ON gs.EventRoundDeskID = rd.EventRoundDeskID
                WHERE gs.PlayerID = ep.EventPlayerID
                  AND rd.EventRoundID = @RoundID_Var
                  AND gs.ActiveFlg = 1
                  AND rd.ActiveFlg = 1
            ) gs
            WHERE ep.EventID = @EventID AND ep.EventUserID IS NOT NULL AND ep.ActiveFlg = 1;
        END

        -- 4. STĂTUSZ FRISSëTÉS (Kizárólag Gamer csatornára)
        IF @Action IN (N'Pta.SetRoundStatus', N'Pta.CloseRound', N'Pta.PublishRound')
        BEGIN
            DECLARE @GamerRoundID_Var INT = JSON_VALUE(@Json, '$.Payload.EventRoundID');
            DECLARE @GamerStatusID_Var INT = JSON_VALUE(@Json, '$.Payload.ToStatusID');
            
            DECLARE @StatusPayload NVARCHAR(MAX) = (
                SELECT 
                    @EventID AS EventID,
                    @Action AS Action,
                    JSON_QUERY((
                        SELECT 
                            @GamerRoundID_Var AS EventRoundID,
                            @GamerStatusID_Var AS ToStatusID
                        FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                    )) AS Payload
                FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
            );

            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            VALUES ('event_' + CAST(@EventID AS VARCHAR) + '_gamer', @Action, @StatusPayload);
        END

        -- 5. ASZTAL EREDMÉNY CÉLZOTT KĂśLDÉSE (Csak GM)
        IF @Action = N'Pta.SetDeskResults'
        BEGIN
            DECLARE @SDR_RoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');
            
            -- JM (GameMaster) értesítése
            INSERT INTO @SignalRTargets (TargetGroup, EventName, CustomPayload)
            SELECT 'event_' + CAST(@EventID AS VARCHAR) + '_user_' + CAST(eu.id AS VARCHAR), @Action, @HotloadJson
            FROM [PTA].[tblEventRoundDesk] rd
            INNER JOIN [EJ].[tblEventUser] eu ON rd.GameMasterUserID = eu.UserID AND eu.EventID = @EventID
            WHERE rd.EventRoundDeskID = @SDR_RoundDeskID;
        END

        SELECT 
            TargetGroup,
            EventName,
            CustomPayload AS PayloadJson
        FROM @SignalRTargets;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID, NULL AS Action;
    END CATCH
END



