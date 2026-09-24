SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSaveEvent]
    @Json NVARCHAR(MAX),
    @UserID INT = NULL -- Ăšj paraméter a JWT user miatt
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @IsNewEvent BIT = CASE WHEN @EventID IS NULL THEN 1 ELSE 0 END;
        DECLARE @EventLocationID INT = JSON_VALUE(@Json, '$.Event.EventLocationID');
        DECLARE @EventTypeID INT = JSON_VALUE(@Json, '$.Event.EventTypeID');
        
        DECLARE @IsOP BIT = 0;
        IF @EventTypeID IS NOT NULL
        BEGIN
            SELECT @IsOP = ISNULL(OPFlg, 0) FROM [EJ].[tblEventType] WHERE id = @EventTypeID;
        END
        
        -- Időbélyeg inicializálása a konzisztens auditáláshoz
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        
        -- ==========================================
        -- 1. LOCATION (Helyszín) kezelése
        -- ==========================================
        DECLARE @LocName NVARCHAR(200) = JSON_VALUE(@Json, '$.Location.LocationName');
        IF @LocName IS NOT NULL AND @EventLocationID IS NULL
        BEGIN
            INSERT INTO [EJ].[tblEventLocation] (LocationName, ZipCode, City, AddressLine1, Country, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT 
                LocationName, PostalCode, City, AddressLine1, CountryCode, 1, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.Location')
            WITH (
                LocationName NVARCHAR(200),
                PostalCode NVARCHAR(20),
                City NVARCHAR(100),
                AddressLine1 NVARCHAR(300),
                CountryCode NVARCHAR(100)
            );
            
            SET @EventLocationID = SCOPE_IDENTITY();
        END
        
        -- ==========================================
        -- 2. EVENT (Esemény) UPSERT
        -- ==========================================
        IF @IsNewEvent = 1
        BEGIN
            INSERT INTO [EJ].[tblEvent] (
                Title, Description, EventTypeID, EventStatusID, EventUID, StartAtUtc, EndAtUtc,
                OnlineFlg, OnlineURL, EventLocationID, Capacity, PublicFlg, ActiveFlg, CreatedByUserID,
                LastUpdatedUserID, createdAt, updatedAt, EventImageUrl, ContactOrganizerID, ContactName, ContactEmail, ContactPhone
            )
            SELECT 
                Title, Description, EventTypeID, EventStatusID, ISNULL(EventUID, NEWID()), 
                CONVERT(DATETIME2, StartAtUtc, 127), CONVERT(DATETIME2, EndAtUtc, 127),
                OnlineFlg, OnlineURL, @EventLocationID, Capacity, PublicFlg, ActiveFlg, @UserID,
                @UserID, @Now, @Now, EventImageUrl, ContactOrganizerID, ContactName, ContactEmail, ContactPhone
            FROM OPENJSON(@Json, '$.Event')
            WITH (
                Title NVARCHAR(200), Description NVARCHAR(MAX), EventTypeID INT, EventStatusID INT,
                EventUID UNIQUEIDENTIFIER, StartAtUtc NVARCHAR(100), EndAtUtc NVARCHAR(100),
                OnlineFlg BIT, OnlineURL NVARCHAR(500), Capacity INT, PublicFlg BIT, ActiveFlg BIT,
                EventImageUrl NVARCHAR(500), ContactOrganizerID BIGINT, ContactName NVARCHAR(200),
                ContactEmail NVARCHAR(320), ContactPhone NVARCHAR(50)
            );

            SET @EventID = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE e
            SET 
                Title = j.Title,
                Description = j.Description,
                EventTypeID = j.EventTypeID,
                EventStatusID = j.EventStatusID,
                StartAtUtc = CONVERT(DATETIME2, j.StartAtUtc, 127),
                EndAtUtc = CONVERT(DATETIME2, j.EndAtUtc, 127),
                OnlineFlg = j.OnlineFlg,
                OnlineURL = j.OnlineURL,
                EventLocationID = @EventLocationID,
                Capacity = j.Capacity,
                PublicFlg = j.PublicFlg,
                ActiveFlg = j.ActiveFlg,
                EventImageUrl = j.EventImageUrl,
                ContactOrganizerID = j.ContactOrganizerID,
                ContactName = j.ContactName,
                ContactEmail = j.ContactEmail,
                ContactPhone = j.ContactPhone,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
            FROM [EJ].[tblEvent] e
            CROSS APPLY OPENJSON(@Json, '$.Event')
            WITH (
                Title NVARCHAR(200), Description NVARCHAR(MAX), EventTypeID INT, EventStatusID INT,
                StartAtUtc NVARCHAR(100), EndAtUtc NVARCHAR(100), OnlineFlg BIT, OnlineURL NVARCHAR(500),
                Capacity INT, PublicFlg BIT, ActiveFlg BIT, EventImageUrl NVARCHAR(500),
                ContactOrganizerID BIGINT, ContactName NVARCHAR(200), ContactEmail NVARCHAR(320), ContactPhone NVARCHAR(50)
            ) j
            WHERE e.id = @EventID;
        END

        -- ==========================================
        -- 3. LABELS (Címkék)
        -- ==========================================
        SELECT 
            id AS LabelID,
            Name AS LabelName
        INTO #IncomingLabels
        FROM OPENJSON(@Json, '$.Labels')
        WITH (id INT '$.id', Name NVARCHAR(100) '$.Name');

        INSERT INTO [EJ].[tblLabel] (LabelName, LastUpdatedUserID, createdAt, updatedAt, ActiveFlg)
        SELECT DISTINCT LabelName, @UserID, @Now, @Now, 1
        FROM #IncomingLabels 
        WHERE LabelID IS NULL 
          AND LabelName NOT IN (SELECT LabelName FROM [EJ].[tblLabel]);

        UPDATE i
        SET i.LabelID = l.id
        FROM #IncomingLabels i
        JOIN [EJ].[tblLabel] l ON i.LabelName = l.LabelName
        WHERE i.LabelID IS NULL;

        DELETE FROM [EJ].[tblEventLabel] 
        WHERE EventID = @EventID 
          AND LabelID NOT IN (SELECT LabelID FROM #IncomingLabels WHERE LabelID IS NOT NULL);

        INSERT INTO [EJ].[tblEventLabel] (EventID, LabelID, LastUpdatedUserID, createdAt, updatedAt)
        SELECT @EventID, LabelID, @UserID, @Now, @Now 
        FROM #IncomingLabels
        WHERE LabelID NOT IN (SELECT LabelID FROM [EJ].[tblEventLabel] WHERE EventID = @EventID);

        -- ==========================================
        -- 4. ROLES (Szerepkörök)
        -- ==========================================
        CREATE TABLE #IncomingRoles (
            TempId NVARCHAR(100),
            RealEventRoleID INT,
            RoleID INT,
            ActiveFlg BIT,
            NewEventRoleID INT
        );

        IF @IsOP = 1
        BEGIN
            -- Olimpub eseménynél fixen 3 role van, a frontend-ről jövőket felülírjuk
            INSERT INTO #IncomingRoles (TempId, RealEventRoleID, RoleID, ActiveFlg)
            SELECT 'auto_role_' + CAST(r.RoleID AS NVARCHAR(10)), er.id, r.RoleID, 1
            FROM (VALUES (1), (3), (7)) AS r(RoleID) -- 1: Szervező, 3: Játékos, 7: Játékmester
            LEFT JOIN [EJ].[tblEventRole] er ON er.EventID = @EventID AND er.RoleID = r.RoleID;
        END
        ELSE
        BEGIN
            INSERT INTO #IncomingRoles (TempId, RealEventRoleID, RoleID, ActiveFlg)
            SELECT 
                TempId,
                TRY_CAST(TempId AS INT) AS RealEventRoleID,
                RoleID,
                ActiveFlg
            FROM OPENJSON(@Json, '$.Roles')
            WITH (TempId NVARCHAR(100), RoleID INT, ActiveFlg BIT);
        END

        UPDATE [EJ].[tblEventRole]
        SET ActiveFlg = 0, updatedAt = @Now, LastUpdatedUserID = @UserID
        WHERE EventID = @EventID 
          AND id NOT IN (SELECT RealEventRoleID FROM #IncomingRoles WHERE RealEventRoleID IS NOT NULL);

        UPDATE er
        SET 
            RoleID = i.RoleID,
            ActiveFlg = i.ActiveFlg,
            updatedAt = @Now,
            LastUpdatedUserID = @UserID
        FROM [EJ].[tblEventRole] er
        JOIN #IncomingRoles i ON er.id = i.RealEventRoleID
        WHERE i.RealEventRoleID IS NOT NULL;

        DECLARE @NewRoleIDs TABLE (InsertedID INT, TempId NVARCHAR(100));
        
        MERGE INTO [EJ].[tblEventRole] AS target
        USING (SELECT * FROM #IncomingRoles WHERE RealEventRoleID IS NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (EventID, RoleID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.RoleID, source.ActiveFlg, @UserID, @Now, @Now)
        OUTPUT inserted.id, source.TempId INTO @NewRoleIDs;

        UPDATE i
        SET i.NewEventRoleID = COALESCE(i.RealEventRoleID, n.InsertedID)
        FROM #IncomingRoles i
        LEFT JOIN @NewRoleIDs n ON i.TempId = n.TempId;

        -- ==========================================
        -- 5. TICKETS (Jegyek)
        -- ==========================================
        CREATE TABLE #IncomingTickets (
            TempId NVARCHAR(100), RealEventTicketID INT, Code NVARCHAR(100), TicketName NVARCHAR(200),
            Description NVARCHAR(MAX), Price DECIMAL(18,2), CurrencyCode NVARCHAR(3), Capacity INT,
            RegistrationStartAtUtc DATETIME2, RegistrationEndAtUtc DATETIME2, TemplateID INT, ActiveFlg BIT,
            NewEventTicketID INT
        );

        INSERT INTO #IncomingTickets (
                TempId, RealEventTicketID, Code, TicketName, Description, Price, CurrencyCode, Capacity,
                RegistrationStartAtUtc, RegistrationEndAtUtc, TemplateID, ActiveFlg
            )
            SELECT 
                TempId, TRY_CAST(TempId AS INT), Code, TicketName, Description, Price, CurrencyCode, Capacity,
                CONVERT(DATETIME2, RegistrationStartAtUtc, 127), CONVERT(DATETIME2, RegistrationEndAtUtc, 127),
                TemplateID, ActiveFlg
            FROM OPENJSON(@Json, '$.Tickets')
            WITH (
                TempId NVARCHAR(100), Code NVARCHAR(100), TicketName NVARCHAR(200), Description NVARCHAR(MAX),
                Price DECIMAL(18,2), CurrencyCode NVARCHAR(3), Capacity INT, RegistrationStartAtUtc NVARCHAR(100),
                RegistrationEndAtUtc NVARCHAR(100), TemplateID INT, ActiveFlg BIT
            );
        

        UPDATE [EJ].[tblEventTicket]
        SET ActiveFlg = 0, updatedAt = @Now, LastUpdatedUserID = @UserID
        WHERE EventID = @EventID 
          AND id NOT IN (SELECT RealEventTicketID FROM #IncomingTickets WHERE RealEventTicketID IS NOT NULL);

        UPDATE et
        SET 
            Code = i.Code,
            TicketName = i.TicketName,
            Description = i.Description,
            Price = i.Price,
            CurrencyCode = i.CurrencyCode,
            Capacity = i.Capacity,
            RegistrationStart = i.RegistrationStartAtUtc,
            RegistrationEnd = i.RegistrationEndAtUtc,
            TemplateID = i.TemplateID,
            ActiveFlg = i.ActiveFlg,
            updatedAt = @Now,
            LastUpdatedUserID = @UserID
        FROM [EJ].[tblEventTicket] et
        JOIN #IncomingTickets i ON et.id = i.RealEventTicketID
        WHERE i.RealEventTicketID IS NOT NULL;

        DECLARE @NewTicketIDs TABLE (InsertedID INT, TempId NVARCHAR(100));
        
        MERGE INTO [EJ].[tblEventTicket] AS target
        USING (SELECT * FROM #IncomingTickets WHERE RealEventTicketID IS NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (
                EventID, Code, TicketName, Description, Price, CurrencyCode, Capacity,
                RegistrationStart, RegistrationEnd, TemplateID, ActiveFlg,
                LastUpdatedUserID, createdAt, updatedAt
            )
            VALUES (
                @EventID, source.Code, source.TicketName, source.Description, source.Price,
                source.CurrencyCode, source.Capacity, source.RegistrationStartAtUtc,
                source.RegistrationEndAtUtc, source.TemplateID, source.ActiveFlg,
                @UserID, @Now, @Now
            )
        OUTPUT inserted.id, source.TempId INTO @NewTicketIDs;

        UPDATE i
        SET i.NewEventTicketID = COALESCE(i.RealEventTicketID, n.InsertedID)
        FROM #IncomingTickets i
        LEFT JOIN @NewTicketIDs n ON i.TempId = n.TempId;

        -- ==========================================
        -- 6. ROLE TICKETS (Kapcsoló tábla)
        -- ==========================================
        DELETE rt
        FROM [EJ].[tblEventRoleTicket] rt
        JOIN [EJ].[tblEventRole] er ON rt.EventRoleID = er.id
        WHERE er.EventID = @EventID;

        INSERT INTO [EJ].[tblEventRoleTicket] (EventID, EventRoleID, EventTicketID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            SELECT 
                @EventID,
                r.NewEventRoleID,
                t.NewEventTicketID,
                1, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.RoleTickets')
            WITH (RoleTempId NVARCHAR(100), TicketTempId NVARCHAR(100)) j
            JOIN #IncomingRoles r ON r.TempId = j.RoleTempId
            JOIN #IncomingTickets t ON t.TempId = j.TicketTempId;
        

        -- ==========================================
        -- 7. PTA Beállítások
        -- ==========================================
        IF JSON_QUERY(@Json, '$.PtaSettings') IS NOT NULL
        BEGIN
            IF EXISTS(SELECT 1 FROM [PTA].[tblEventSettings] WHERE EventID = @EventID)
            BEGIN
                UPDATE p
                SET 
                    GameTypeID = j.GameTypeID,
                    PairModeID = j.PairModeID,
                    ChampinshipID = j.ChampionshipID,
                    Category = j.Category,
                    Point1 = j.Point1,
                    Point2 = j.Point2,
                    Point3 = j.Point3,
                    Point4 = j.Point4,
                    MaxParticipants = j.MaxParticipants,
                    OrganizationGrpFlg = j.OrganizationGrpFlg,
                    TeamGrpFlg = j.TeamGrpFlg,
                    RegionGrpFlg = j.RegionGrpFlg,
                    CompanyGrpFlg = j.CompanyGrpFlg,
                    PhotoUploadMadatoryFlg = j.PhotoUploadMandatoryFlg,
                    ExtraPrizeFlg = j.ExtraPrizeFlg,
                    ShowUserPositionFlg = j.ShowUserPositionFlg,
                    LastUpdatedUserID = @UserID,
                    updatedAt = @Now
                FROM [PTA].[tblEventSettings] p
                CROSS APPLY OPENJSON(@Json, '$.PtaSettings')
                WITH (
                    GameTypeID INT, PairModeID INT, ChampionshipID INT, Category INT,
                    Point1 SMALLINT, Point2 SMALLINT, Point3 SMALLINT, Point4 SMALLINT,
                    MaxParticipants INT, OrganizationGrpFlg BIT, TeamGrpFlg BIT, RegionGrpFlg BIT,
                    CompanyGrpFlg BIT, PhotoUploadMandatoryFlg BIT, ExtraPrizeFlg BIT, ShowUserPositionFlg BIT
                ) j
                WHERE p.EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [PTA].[tblEventSettings] (
                    EventID, GameTypeID, PairModeID, ChampinshipID, Category,
                    Point1, Point2, Point3, Point4, MaxParticipants, OrganizationGrpFlg, TeamGrpFlg,
                    RegionGrpFlg, CompanyGrpFlg, PhotoUploadMadatoryFlg, ExtraPrizeFlg, ShowUserPositionFlg,
                    LastUpdatedUserID, createdAt, updatedAt
                )
                SELECT 
                    @EventID, GameTypeID, PairModeID, ChampionshipID, Category,
                    Point1, Point2, Point3, Point4, MaxParticipants, OrganizationGrpFlg, TeamGrpFlg,
                    RegionGrpFlg, CompanyGrpFlg, PhotoUploadMandatoryFlg, ExtraPrizeFlg, ShowUserPositionFlg,
                    @UserID, @Now, @Now
                FROM OPENJSON(@Json, '$.PtaSettings')
                WITH (
                    GameTypeID INT, PairModeID INT, ChampionshipID INT, Category INT,
                    Point1 SMALLINT, Point2 SMALLINT, Point3 SMALLINT, Point4 SMALLINT,
                    MaxParticipants INT, OrganizationGrpFlg BIT, TeamGrpFlg BIT, RegionGrpFlg BIT,
                    CompanyGrpFlg BIT, PhotoUploadMandatoryFlg BIT, ExtraPrizeFlg BIT, ShowUserPositionFlg BIT
                );
            END

            DELETE FROM [PTA].[tblEventPrize] WHERE EventID = @EventID;
            INSERT INTO [PTA].[tblEventPrize] (EventID, PrizeID, LastUpdatedUserID, createdAt, updatedAt)
            SELECT @EventID, PrizeID, @UserID, @Now, @Now
            FROM OPENJSON(@Json, '$.PtaPrizes')
            WITH (PrizeID INT);
        END

        -- ==========================================
        -- 7.5 OP Beállítások (Olimpub)
        -- ==========================================
        IF @IsOP = 1 AND JSON_QUERY(@Json, '$.OpSettings') IS NOT NULL
        BEGIN
            DECLARE @DeskCountHint INT = JSON_VALUE(@Json, '$.OpSettings.DeskCountHint');
            DECLARE @MaxTeamSize INT = ISNULL(JSON_VALUE(@Json, '$.OpSettings.MaxTeamSize'), 8);
            DECLARE @PlannedDurationMin INT = JSON_VALUE(@Json, '$.OpSettings.PlannedDurationMin');
            DECLARE @ShadowAwardFlg BIT = ISNULL(JSON_VALUE(@Json, '$.OpSettings.ShadowAwardFlg'), 1);
            DECLARE @TopicIdsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.OpSettings.TopicIds');
            DECLARE @ExtraGameIdsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.OpSettings.ExtraGameIds');
            DECLARE @KabalaIdsJson NVARCHAR(MAX) = JSON_QUERY(@Json, '$.OpSettings.KabalaIds');

            IF EXISTS(SELECT 1 FROM [OP].[tblEventSettings] WHERE EventID = @EventID)
            BEGIN
                UPDATE [OP].[tblEventSettings]
                SET DeskCountHint = @DeskCountHint,
                    MaxTeamSize = @MaxTeamSize,
                    PlannedDurationMin = @PlannedDurationMin,
                    ShadowAwardFlg = @ShadowAwardFlg
                WHERE EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [OP].[tblEventSettings] (EventID, DeskCountHint, MaxTeamSize, PlannedDurationMin, ShadowAwardFlg)
                VALUES (@EventID, @DeskCountHint, @MaxTeamSize, @PlannedDurationMin, @ShadowAwardFlg);
            END

            -- Témakörök szinkronizációja
            DELETE FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID AND TopicID NOT IN (SELECT CAST(value AS INT) FROM OPENJSON(@TopicIdsJson));
            INSERT INTO [OP].[tblEventSettingTopic] (EventID, TopicID)
            SELECT @EventID, CAST(value AS INT) FROM OPENJSON(@TopicIdsJson)
            WHERE CAST(value AS INT) NOT IN (SELECT TopicID FROM [OP].[tblEventSettingTopic] WHERE EventID = @EventID);

            -- Extra játékok szinkronizációja
            DELETE FROM [OP].[tblEventSettingExtraGame] WHERE EventID = @EventID AND ExtraGameId NOT IN (SELECT value FROM OPENJSON(@ExtraGameIdsJson));
            INSERT INTO [OP].[tblEventSettingExtraGame] (EventID, ExtraGameId)
            SELECT @EventID, value FROM OPENJSON(@ExtraGameIdsJson)
            WHERE value NOT IN (SELECT ExtraGameId FROM [OP].[tblEventSettingExtraGame] WHERE EventID = @EventID);

            -- Kabalák (EventSettingKabala) szinkronizációja
            DELETE FROM [OP].[tblEventSettingKabala] WHERE EventID = @EventID AND KabalaID NOT IN (SELECT CAST(value AS INT) FROM OPENJSON(@KabalaIdsJson));
            INSERT INTO [OP].[tblEventSettingKabala] (EventID, KabalaID)
            SELECT @EventID, CAST(value AS INT) FROM OPENJSON(@KabalaIdsJson)
            WHERE CAST(value AS INT) NOT IN (SELECT KabalaID FROM [OP].[tblEventSettingKabala] WHERE EventID = @EventID);

            -- Csapatok szinkronizációja (Kabalák alapján)
            -- 1. Insert új csapatokat
            INSERT INTO [OP].[tblTeam] (EventID, KabalaID, ActiveFlg)
            SELECT @EventID, CAST(value AS INT), 1
            FROM OPENJSON(@KabalaIdsJson)
            WHERE CAST(value AS INT) NOT IN (SELECT KabalaID FROM [OP].[tblTeam] WHERE EventID = @EventID);

            -- 2. Töröljük (inaktiváljuk) amiket kivettek, HA nincs TeamMember
            UPDATE t
            SET t.ActiveFlg = 0
            FROM [OP].[tblTeam] t
            LEFT JOIN OPENJSON(@KabalaIdsJson) j ON t.KabalaID = CAST(j.value AS INT)
            WHERE t.EventID = @EventID AND j.value IS NULL
              AND NOT EXISTS (SELECT 1 FROM [OP].[tblTeamMember] tm WHERE tm.TeamID = t.id AND tm.ActiveFlg = 1);
              
            -- 3. Visszakapcsoljuk, ami eddig inaktív volt de visszajött
            UPDATE t
            SET t.ActiveFlg = 1
            FROM [OP].[tblTeam] t
            JOIN OPENJSON(@KabalaIdsJson) j ON t.KabalaID = CAST(j.value AS INT)
            WHERE t.EventID = @EventID AND t.ActiveFlg = 0;
        END

        -- ==========================================
        -- 8. Szervező (EventUser) létrehozása (csak Create esetén)
        -- ==========================================
        IF @IsNewEvent = 1 AND @UserID IS NOT NULL
        BEGIN
            DECLARE @OrganizerEventRoleID INT;
            
            -- Megpróbáljuk megkeresni a "Szervező" (1) vagy "Tulajdonos" (11) szerepkört
            SELECT TOP 1 @OrganizerEventRoleID = NewEventRoleID
            FROM #IncomingRoles 
            WHERE RoleID IN (1, 11)
            ORDER BY CASE WHEN RoleID = 11 THEN 1 ELSE 2 END; -- Preferáljuk a tulajdonost (11)

            -- Ha nincs sem 1-es, sem 11-es a beküldöttek között (tehát nem hoznak létre admin/tulajdonos role-t)
            IF @OrganizerEventRoleID IS NULL
            BEGIN
                 -- Automatikusan legenerálunk egy Tulajdonos (11) szerepkört az eseményhez
                 INSERT INTO [EJ].[tblEventRole] (EventID, RoleID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
                 VALUES (@EventID, 11, 1, @UserID, @Now, @Now);

                 SET @OrganizerEventRoleID = SCOPE_IDENTITY();
            END

            -- Végül beírjuk a Felhasználót az eseményhez (Jegy nélkül)
            INSERT INTO [EJ].[tblEventUser] (
                EventID, UserID, EventRoleID, EventUserStatusID, ActiveFlg, 
                LastUpdatedUserID, createdAt, updatedAt
            )
            VALUES (
                @EventID, @UserID, @OrganizerEventRoleID, 1, 1, 
                @UserID, @Now, @Now
            );
        END

        COMMIT TRANSACTION;
        
        -- ==========================================
        -- 9. RETURN
        -- ==========================================
        SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID;
    END CATCH
END


