CREATE OR ALTER PROCEDURE [EJ].[spSaveEvent]
    @Json NVARCHAR(MAX),
    @UserID INT = NULL -- Új paraméter a JWT user miatt
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @IsNewEvent BIT = CASE WHEN @EventID IS NULL THEN 1 ELSE 0 END;
        DECLARE @EventLocationID INT = JSON_VALUE(@Json, '$.Event.EventLocationID');
        
        -- ==========================================
        -- 1. LOCATION (Helyszín) kezelése
        -- ==========================================
        DECLARE @LocName NVARCHAR(200) = JSON_VALUE(@Json, '$.Location.LocationName');
        IF @LocName IS NOT NULL AND @EventLocationID IS NULL
        BEGIN
            INSERT INTO [EJ].[tblEventLocation] (LocationName, City, AddressLine1, CountryCode)
            SELECT 
                LocationName, City, AddressLine1, CountryCode
            FROM OPENJSON(@Json, '$.Location')
            WITH (
                LocationName NVARCHAR(200),
                City NVARCHAR(100),
                AddressLine1 NVARCHAR(300),
                CountryCode NVARCHAR(8)
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
                OnlineFlg, OnlineURL, EventLocationID, Capacity, PublicFlg, ActiveFlg,
                ContactName, ContactEmail, ContactPhone, OrganizationID
            )
            SELECT 
                Title, Description, EventTypeID, EventStatusID, EventUID, 
                CONVERT(DATETIME2, StartAtUtc, 127), CONVERT(DATETIME2, EndAtUtc, 127),
                OnlineFlg, OnlineURL, @EventLocationID, Capacity, PublicFlg, ActiveFlg,
                ContactName, ContactEmail, ContactPhone, OrganizationID
            FROM OPENJSON(@Json, '$.Event')
            WITH (
                Title NVARCHAR(200), Description NVARCHAR(MAX), EventTypeID INT, EventStatusID INT,
                EventUID UNIQUEIDENTIFIER, StartAtUtc NVARCHAR(100), EndAtUtc NVARCHAR(100),
                OnlineFlg BIT, OnlineURL NVARCHAR(500), Capacity INT, PublicFlg BIT, ActiveFlg BIT,
                ContactName NVARCHAR(200), ContactEmail NVARCHAR(200), ContactPhone NVARCHAR(50), OrganizationID INT
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
                ContactName = j.ContactName,
                ContactEmail = j.ContactEmail,
                ContactPhone = j.ContactPhone,
                OrganizationID = j.OrganizationID
            FROM [EJ].[tblEvent] e
            CROSS APPLY OPENJSON(@Json, '$.Event')
            WITH (
                Title NVARCHAR(200), Description NVARCHAR(MAX), EventTypeID INT, EventStatusID INT,
                StartAtUtc NVARCHAR(100), EndAtUtc NVARCHAR(100), OnlineFlg BIT, OnlineURL NVARCHAR(500),
                Capacity INT, PublicFlg BIT, ActiveFlg BIT, ContactName NVARCHAR(200), 
                ContactEmail NVARCHAR(200), ContactPhone NVARCHAR(50), OrganizationID INT
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

        INSERT INTO [EJ].[tblLabel] (Name)
        SELECT DISTINCT LabelName 
        FROM #IncomingLabels 
        WHERE LabelID IS NULL 
          AND LabelName NOT IN (SELECT Name FROM [EJ].[tblLabel]);

        UPDATE i
        SET i.LabelID = l.id
        FROM #IncomingLabels i
        JOIN [EJ].[tblLabel] l ON i.LabelName = l.Name
        WHERE i.LabelID IS NULL;

        DELETE FROM [EJ].[tblEventLabel] 
        WHERE EventID = @EventID 
          AND LabelID NOT IN (SELECT LabelID FROM #IncomingLabels WHERE LabelID IS NOT NULL);

        INSERT INTO [EJ].[tblEventLabel] (EventID, LabelID)
        SELECT @EventID, LabelID 
        FROM #IncomingLabels
        WHERE LabelID NOT IN (SELECT LabelID FROM [EJ].[tblEventLabel] WHERE EventID = @EventID);

        -- ==========================================
        -- 4. ROLES (Szerepkörök)
        -- ==========================================
        SELECT 
            TempId,
            TRY_CAST(TempId AS INT) AS RealEventRoleID,
            RoleID,
            ActiveFlg,
            CAST(NULL AS INT) AS NewEventRoleID
        INTO #IncomingRoles
        FROM OPENJSON(@Json, '$.Roles')
        WITH (TempId NVARCHAR(100), RoleID INT, ActiveFlg BIT);

        UPDATE [EJ].[tblEventRole]
        SET ActiveFlg = 0
        WHERE EventID = @EventID 
          AND id NOT IN (SELECT RealEventRoleID FROM #IncomingRoles WHERE RealEventRoleID IS NOT NULL);

        UPDATE er
        SET 
            RoleID = i.RoleID,
            ActiveFlg = i.ActiveFlg
        FROM [EJ].[tblEventRole] er
        JOIN #IncomingRoles i ON er.id = i.RealEventRoleID
        WHERE i.RealEventRoleID IS NOT NULL;

        DECLARE @NewRoleIDs TABLE (InsertedID INT, TempId NVARCHAR(100));
        
        MERGE INTO [EJ].[tblEventRole] AS target
        USING (SELECT * FROM #IncomingRoles WHERE RealEventRoleID IS NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (EventID, RoleID, ActiveFlg)
            VALUES (@EventID, source.RoleID, source.ActiveFlg)
        OUTPUT inserted.id, source.TempId INTO @NewRoleIDs;

        UPDATE i
        SET i.NewEventRoleID = COALESCE(i.RealEventRoleID, n.InsertedID)
        FROM #IncomingRoles i
        LEFT JOIN @NewRoleIDs n ON i.TempId = n.TempId;

        -- ==========================================
        -- 5. TICKETS (Jegyek)
        -- ==========================================
        SELECT 
            TempId,
            TRY_CAST(TempId AS INT) AS RealEventTicketID,
            Code, TicketName, Description, Price, CurrencyCode, Capacity,
            CONVERT(DATETIME2, RegistrationStartAtUtc, 127) AS RegistrationStartAtUtc,
            CONVERT(DATETIME2, RegistrationEndAtUtc, 127) AS RegistrationEndAtUtc,
            TemplateID, ActiveFlg,
            CAST(NULL AS INT) AS NewEventTicketID
        INTO #IncomingTickets
        FROM OPENJSON(@Json, '$.Tickets')
        WITH (
            TempId NVARCHAR(100), Code NVARCHAR(100), TicketName NVARCHAR(200), Description NVARCHAR(MAX),
            Price DECIMAL(18,2), CurrencyCode NVARCHAR(3), Capacity INT, RegistrationStartAtUtc NVARCHAR(100),
            RegistrationEndAtUtc NVARCHAR(100), TemplateID INT, ActiveFlg BIT
        );

        UPDATE [EJ].[tblEventTicket]
        SET ActiveFlg = 0
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
            RegistrationStartAtUtc = i.RegistrationStartAtUtc,
            RegistrationEndAtUtc = i.RegistrationEndAtUtc,
            TemplateID = i.TemplateID,
            ActiveFlg = i.ActiveFlg
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
                RegistrationStartAtUtc, RegistrationEndAtUtc, TemplateID, ActiveFlg
            )
            VALUES (
                @EventID, source.Code, source.TicketName, source.Description, source.Price,
                source.CurrencyCode, source.Capacity, source.RegistrationStartAtUtc,
                source.RegistrationEndAtUtc, source.TemplateID, source.ActiveFlg
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

        INSERT INTO [EJ].[tblEventRoleTicket] (EventRoleID, EventTicketID)
        SELECT 
            r.NewEventRoleID,
            t.NewEventTicketID
        FROM OPENJSON(@Json, '$.RoleTickets')
        WITH (RoleTempId NVARCHAR(100), TicketTempId NVARCHAR(100)) j
        JOIN #IncomingRoles r ON r.TempId = j.RoleTempId
        JOIN #IncomingTickets t ON t.TempId = j.TicketTempId;

        -- ==========================================
        -- 7. PTA Beállítások
        -- ==========================================
        IF JSON_QUERY(@Json, '$.PtaSettings') IS NOT NULL
        BEGIN
            IF EXISTS(SELECT 1 FROM [EJ].[tblEventPTA] WHERE EventID = @EventID)
            BEGIN
                UPDATE p
                SET 
                    GameTypeID = j.GameTypeID,
                    PairModeID = j.PairModeID,
                    ChampinshipID = j.ChampionshipID,
                    ChampinshipFlg = j.ChampionshipFlg,
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
                    ShowUserPositionFlg = j.ShowUserPositionFlg
                FROM [EJ].[tblEventPTA] p
                CROSS APPLY OPENJSON(@Json, '$.PtaSettings')
                WITH (
                    GameTypeID INT, PairModeID INT, ChampionshipID INT, ChampionshipFlg BIT, Category INT,
                    Point1 DECIMAL(9,2), Point2 DECIMAL(9,2), Point3 DECIMAL(9,2), Point4 DECIMAL(9,2),
                    MaxParticipants INT, OrganizationGrpFlg BIT, TeamGrpFlg BIT, RegionGrpFlg BIT,
                    CompanyGrpFlg BIT, PhotoUploadMandatoryFlg BIT, ExtraPrizeFlg BIT, ShowUserPositionFlg BIT
                ) j
                WHERE p.EventID = @EventID;
            END
            ELSE
            BEGIN
                INSERT INTO [EJ].[tblEventPTA] (
                    EventID, GameTypeID, PairModeID, ChampinshipID, ChampinshipFlg, Category,
                    Point1, Point2, Point3, Point4, MaxParticipants, OrganizationGrpFlg, TeamGrpFlg,
                    RegionGrpFlg, CompanyGrpFlg, PhotoUploadMadatoryFlg, ExtraPrizeFlg, ShowUserPositionFlg
                )
                SELECT 
                    @EventID, GameTypeID, PairModeID, ChampionshipID, ChampionshipFlg, Category,
                    Point1, Point2, Point3, Point4, MaxParticipants, OrganizationGrpFlg, TeamGrpFlg,
                    RegionGrpFlg, CompanyGrpFlg, PhotoUploadMandatoryFlg, ExtraPrizeFlg, ShowUserPositionFlg
                FROM OPENJSON(@Json, '$.PtaSettings')
                WITH (
                    GameTypeID INT, PairModeID INT, ChampionshipID INT, ChampionshipFlg BIT, Category INT,
                    Point1 DECIMAL(9,2), Point2 DECIMAL(9,2), Point3 DECIMAL(9,2), Point4 DECIMAL(9,2),
                    MaxParticipants INT, OrganizationGrpFlg BIT, TeamGrpFlg BIT, RegionGrpFlg BIT,
                    CompanyGrpFlg BIT, PhotoUploadMandatoryFlg BIT, ExtraPrizeFlg BIT, ShowUserPositionFlg BIT
                );
            END

            DELETE FROM [EJ].[tblEventPTAPrize] WHERE EventID = @EventID;
            INSERT INTO [EJ].[tblEventPTAPrize] (EventID, PrizeID)
            SELECT @EventID, PrizeID
            FROM OPENJSON(@Json, '$.PtaPrizes')
            WITH (PrizeID INT);
        END

        -- ==========================================
        -- 8. Szervező (EventUser) létrehozása (csak Create esetén)
        -- ==========================================
        IF @IsNewEvent = 1 AND @UserID IS NOT NULL
        BEGIN
            DECLARE @OrganizerEventRoleID INT;
            DECLARE @OrganizerEventTicketID INT;
            
            SELECT TOP 1 @OrganizerEventRoleID = NewEventRoleID
            FROM #IncomingRoles WHERE RoleID = 1;

            SELECT TOP 1 @OrganizerEventTicketID = t.NewEventTicketID
            FROM OPENJSON(@Json, '$.RoleTickets') WITH (RoleTempId NVARCHAR(100), TicketTempId NVARCHAR(100)) j
            JOIN #IncomingRoles r ON r.TempId = j.RoleTempId
            JOIN #IncomingTickets t ON t.TempId = j.TicketTempId
            WHERE r.RoleID = 1;

            IF @OrganizerEventRoleID IS NOT NULL AND @OrganizerEventTicketID IS NOT NULL
            BEGIN
                INSERT INTO [EJ].[tblEventUser] (
                    EventID, UserID, EventRoleID, EventTicketID, EventUserStatusID, ActiveFlg
                )
                VALUES (
                    @EventID, @UserID, @OrganizerEventRoleID, @OrganizerEventTicketID, 1, 1
                );
            END
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
GO
