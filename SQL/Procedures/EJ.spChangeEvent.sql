CREATE   PROCEDURE [EJ].[spChangeEvent]
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

            -- INSERT Players
            DECLARE @NewPlayers TABLE (InsertedID INT, TempId NVARCHAR(100));
            MERGE INTO [PTA].[tblEventPlayer] AS target
            USING (
                SELECT TempId, EventUserID, Name, TeamName, CompanyName, OrganizationName, RegionName, ActiveFlg
                FROM OPENJSON(@Json, '$.Payload.Players')
                WITH (TempId NVARCHAR(64), EventUserID INT, Name NVARCHAR(200), TeamName NVARCHAR(200), CompanyName NVARCHAR(200), OrganizationName NVARCHAR(200), RegionName NVARCHAR(200), ActiveFlg BIT)
            ) AS source ON 1=0
            WHEN NOT MATCHED THEN INSERT (EventID, EventUserID, NickName, TeamName, CompanyName, OrganizationName, RegionName, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.EventUserID, source.Name, source.TeamName, source.CompanyName, source.OrganizationName, source.RegionName, source.ActiveFlg, @UserID, @Now, @Now)
            OUTPUT inserted.EventPlayerID, source.TempId INTO @NewPlayers;

            -- INSERT Schedules
            INSERT INTO [PTA].[tblGameSchedule] (EventRoundDeskID, PlayerID, PlayColorHex, Amount, OnTrack, Position, ResultPoint, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT rd.InsertedID, p.InsertedID, j.ColorHex, j.Amount, j.OnTrack, j.Position, j.ResultPoint, j.ActiveFlg, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.Payload.Schedules')
            WITH (RoundDeskTempId NVARCHAR(64), PlayerTempId NVARCHAR(64), ColorHex NVARCHAR(10), Amount INT, OnTrack INT, Position INT, ResultPoint INT, ActiveFlg BIT) j
            JOIN @NewRoundDesks rd ON j.RoundDeskTempId = rd.TempId
            JOIN @NewPlayers p ON j.PlayerTempId = p.TempId;

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

            -- 2. Aggregáció (csak ha Lezárt vagy Publikált)
            IF @Action IN (N'Pta.CloseRound', N'Pta.PublishRound')
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
                    p.FinalPoint = a.TotalResultPoint,
                    p.FinalTruckPoint = a.TotalAmount,
                    p.LastUpdatedUserID = @UserID,
                    p.updatedAt = @Now
                FROM [PTA].[tblEventPlayer] p
                INNER JOIN AggregatedScores a ON p.EventPlayerID = a.PlayerID
                WHERE p.EventID = @EventID;
            END
        END
        ELSE IF @Action = N'Pta.SetDeskResults'
        BEGIN
            DECLARE @RoundDeskID INT = JSON_VALUE(@Json, '$.Payload.EventRoundDeskID');

            -- KAPU VALIDÁCIÓK
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
                INNER JOIN [EJ].[tblEventRoleTicket] ert ON eu.EventTicketID = ert.EventTicketID 
                INNER JOIN [EJ].[tblEventRole] er ON ert.EventRoleID = er.id 
                INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
                WHERE eu.UserID = @UserID AND eu.EventID = @EventID AND (r.RoleName = N'Organizer' OR r.Code = N'organizer')
            ) THEN 1 ELSE 0 END);
            
            IF @GameMasterUserID <> @UserID AND @IsOrganizer = 0
            BEGIN
                THROW 50005, N'Permission Denied: Csak a Játékmester vagy Szervező pontozhat!', 1;
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
            
            DELETE FROM [PTA].[tblGameSchedule] WHERE PlayerID IN (SELECT EventPlayerID FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID);
            DELETE FROM [PTA].[tblEventRoundDesk] WHERE EventRoundID IN (SELECT EventRoundID FROM [PTA].[tblEventRound] WHERE EventID = @EventID);
            DELETE FROM [PTA].[tblEventPlayer] WHERE EventID = @EventID;
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
        IF @Action NOT IN (N'Pta.SetRoundStatus', N'Pta.CloseRound', N'Pta.PublishRound')
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

        -- 3. EGYEDI JÁTÉKOS-ÉRTESÍTÉSEK FORDULÓ ZÁRÁSKOR
        -- Ha PublishRound történt, kiküldjük egyenként a privát csatornájukra
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
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
                                ) ELSE NULL END) AS Seat,
                                JSON_QUERY((
                                    SELECT 
                                        ep.EventPlayerID,
                                        ep.FinalPoint,
                                        ep.FinalTruckPoint,
                                        ep.FinalPosition
                                    FOR JSON PATH, WITHOUT_ARRAY_WRAPPER
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
                WHERE gs.PlayerID = ep.EventPlayerID AND rd.EventRoundID = @RoundID_Var
            ) gs
            WHERE ep.EventID = @EventID AND ep.EventUserID IS NOT NULL AND ep.ActiveFlg = 1;
        END

        -- 4. STÁTUSZ FRISSÍTÉS (Kizárólag Gamer csatornára)
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

        -- 5. ASZTAL EREDMÉNY CÉLZOTT KÜLDÉSE (Csak GM)
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
