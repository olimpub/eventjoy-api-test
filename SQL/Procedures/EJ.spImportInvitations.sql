CREATE OR ALTER PROCEDURE [EJ].[spImportInvitations]
    @Json NVARCHAR(MAX),
    @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    BEGIN TRY
        DECLARE @EventID BIGINT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

        IF @EventID IS NULL
        BEGIN
            THROW 50000, N'EventID is required', 1;
        END

        DECLARE @EventName NVARCHAR(200);
        SELECT @EventName = Title FROM [EJ].[tblEvent] WHERE id = @EventID;

        -- 1. Temp tábla létrehozása
        CREATE TABLE #Invitations (
            RowID INT IDENTITY(1,1),
            FirstName NVARCHAR(150),
            LastName NVARCHAR(150),
            Email NVARCHAR(300),
            Phone NVARCHAR(50),
            RoleName NVARCHAR(200),
            TicketName NVARCHAR(200),
            OrganizationName NVARCHAR(100) NULL,
            TeamName NVARCHAR(100) NULL,
            RegionName NVARCHAR(100) NULL,
            CompanyName NVARCHAR(100) NULL,
            TargetUserID BIGINT NULL,
            RoleID BIGINT NULL,
            RoleTypeID BIGINT NULL,
            EventRoleID BIGINT NULL,
            EventTicketID BIGINT NULL,
            EventRoleTicketID BIGINT NULL,
            ResultMsg NVARCHAR(MAX) NULL,
            ValidationCode NVARCHAR(10) NULL,
            EventUserUID UNIQUEIDENTIFIER NULL
        );

        INSERT INTO #Invitations (FirstName, LastName, Email, Phone, RoleName, TicketName, OrganizationName, TeamName, RegionName, CompanyName)
        SELECT 
            NULLIF(TRIM(JSON_VALUE(value, '$."Keresztnév"')), ''),
            NULLIF(TRIM(JSON_VALUE(value, '$."Vezetéknév"')), ''),
            NULLIF(TRIM(LOWER(JSON_VALUE(value, '$."Email-cím"'))), ''),
            NULLIF(TRIM(JSON_VALUE(value, '$."Telefonszám"')), ''),
            NULLIF(TRIM(JSON_VALUE(value, '$."Szerepkör"')), ''),
            NULLIF(TRIM(JSON_VALUE(value, '$."Jegy"')), ''),
            COALESCE(NULLIF(TRIM(JSON_VALUE(value, '$."OrganizationName"')), ''), NULLIF(TRIM(JSON_VALUE(value, '$."Szervezet"')), '')),
            COALESCE(NULLIF(TRIM(JSON_VALUE(value, '$."TeamName"')), ''), NULLIF(TRIM(JSON_VALUE(value, '$."Csapat"')), '')),
            COALESCE(NULLIF(TRIM(JSON_VALUE(value, '$."RegionName"')), ''), NULLIF(TRIM(JSON_VALUE(value, '$."Régió"')), '')),
            COALESCE(NULLIF(TRIM(JSON_VALUE(value, '$."CompanyName"')), ''), NULLIF(TRIM(JSON_VALUE(value, '$."Cég"')), ''))
        FROM OPENJSON(@Json, '$.Invitations');

        UPDATE #Invitations
        SET 
            ValidationCode = CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS NVARCHAR(10)),
            EventUserUID = NEWID();

        -- 1/B. Csoportosítási Flagek ellenőrzése
        DECLARE @OrgGrpFlg BIT = 0, @TeamGrpFlg BIT = 0, @RegionGrpFlg BIT = 0, @CompanyGrpFlg BIT = 0;
        SELECT 
            @OrgGrpFlg = ISNULL(OrganizationGrpFlg, 0),
            @TeamGrpFlg = ISNULL(TeamGrpFlg, 0),
            @RegionGrpFlg = ISNULL(RegionGrpFlg, 0),
            @CompanyGrpFlg = ISNULL(CompanyGrpFlg, 0)
        FROM [PTA].[tblEventSettings]
        WHERE EventID = @EventID;

        -- Eldobjuk a kikapcsolt flageket (akkor is, ha küldték)
        IF @OrgGrpFlg = 0 UPDATE #Invitations SET OrganizationName = NULL;
        IF @TeamGrpFlg = 0 UPDATE #Invitations SET TeamName = NULL;
        IF @RegionGrpFlg = 0 UPDATE #Invitations SET RegionName = NULL;
        IF @CompanyGrpFlg = 0 UPDATE #Invitations SET CompanyName = NULL;

        -- Kötelező mezők validálása (csak ha a flag be van kapcsolva)
        IF @OrgGrpFlg = 1 UPDATE #Invitations SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Hiányzó Szervezet') WHERE OrganizationName IS NULL;
        IF @TeamGrpFlg = 1 UPDATE #Invitations SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Hiányzó Csapat') WHERE TeamName IS NULL;
        IF @RegionGrpFlg = 1 UPDATE #Invitations SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Hiányzó Régió') WHERE RegionName IS NULL;
        IF @CompanyGrpFlg = 1 UPDATE #Invitations SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Hiányzó Cég') WHERE CompanyName IS NULL;

        -- 2. User Matching (Email alapán)
        -- tblUser alapján
        UPDATE i
        SET TargetUserID = u.id
        FROM #Invitations i
        JOIN [EJ].[tblUser] u ON LOWER(u.EmailAddress) = i.Email
        WHERE i.Email IS NOT NULL AND i.Email <> '' AND i.TargetUserID IS NULL;

        -- tblUserLoginIdentifier alapján
        UPDATE i
        SET TargetUserID = uid.UserID
        FROM #Invitations i
        JOIN [EJ].[tblUserLoginIdentifier] uid ON uid.IdentifierValueNormalized = i.Email AND uid.IdentifierTypeID = 1
        WHERE i.Email IS NOT NULL AND i.Email <> '' AND i.TargetUserID IS NULL;

        -- Hiányzó Userek létrehozása
        DECLARE @NewUsers TABLE (InsertedID BIGINT, RowID INT);
        MERGE INTO [EJ].[tblUser] AS target
        USING (SELECT RowID, FirstName, LastName, Email, Phone FROM #Invitations WHERE TargetUserID IS NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (FirstName, LastName, EmailAddress, PhoneNumber, StatusID, createdAt, updatedAt)
            VALUES (source.FirstName, source.LastName, source.Email, source.Phone, 1, @Now, @Now)
        OUTPUT inserted.id, source.RowID INTO @NewUsers;

        -- TargetUserID frissítése az újaknál
        UPDATE i
        SET TargetUserID = nu.InsertedID
        FROM #Invitations i
        JOIN @NewUsers nu ON i.RowID = nu.RowID;

        -- LoginIdentifier bejegyzés az új usereknek
        INSERT INTO [EJ].[tblUserLoginIdentifier] (UserID, IdentifierTypeID, IdentifierValueRaw, IdentifierValueNormalized, IsPrimary, IsVerified, ActiveFlg, createdAt, updatedAt)
        SELECT nu.InsertedID, 1, i.Email, i.Email, 1, 0, 1, @Now, @Now
        FROM @NewUsers nu
        JOIN #Invitations i ON nu.RowID = i.RowID
        WHERE i.Email IS NOT NULL AND i.Email <> '';

        -- 3. Szerepkör (Role) Validálás
        UPDATE i
        SET 
            RoleID = r.id,
            RoleTypeID = r.RoleTypeID
        FROM #Invitations i
        JOIN [EJ].[tblRole] r ON r.RoleName = i.RoleName;

        UPDATE #Invitations
        SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Ismeretlen szerepkör')
        WHERE RoleID IS NULL;

        -- EventRole ellenőrzés
        UPDATE i
        SET EventRoleID = er.id
        FROM #Invitations i
        JOIN [EJ].[tblEventRole] er ON er.RoleID = i.RoleID AND er.EventID = @EventID
        WHERE i.RoleID IS NOT NULL;

        -- Hiányzó EventRole-ok létrehozása
        DECLARE @NewEventRoles TABLE (InsertedID BIGINT, RoleID BIGINT);
        MERGE INTO [EJ].[tblEventRole] AS target
        USING (SELECT DISTINCT RoleID FROM #Invitations WHERE RoleID IS NOT NULL AND EventRoleID IS NULL) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (EventID, RoleID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.RoleID, 1, @UserID, @Now, @Now)
        OUTPUT inserted.id, source.RoleID INTO @NewEventRoles;

        UPDATE i
        SET EventRoleID = ner.InsertedID
        FROM #Invitations i
        JOIN @NewEventRoles ner ON i.RoleID = ner.RoleID
        WHERE i.EventRoleID IS NULL;

        -- 4. Jegy (Ticket) Ellenőrzése
        UPDATE #Invitations
        SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Hiányzó jegy adat')
        WHERE RoleTypeID <> 1 AND (TicketName IS NULL OR TicketName = '');

        UPDATE i
        SET EventTicketID = et.id
        FROM #Invitations i
        JOIN [EJ].[tblEventTicket] et ON et.TicketName = i.TicketName AND et.EventID = @EventID
        WHERE i.TicketName IS NOT NULL AND i.TicketName <> '';

        UPDATE #Invitations
        SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Ismeretlen jegy')
        WHERE EventTicketID IS NULL AND (TicketName IS NOT NULL AND TicketName <> '');

        -- 5. Role-Ticket összerendelés ellenőrzése
        UPDATE i
        SET EventRoleTicketID = ert.id
        FROM #Invitations i
        JOIN [EJ].[tblEventRoleTicket] ert ON ert.EventRoleID = i.EventRoleID AND ert.EventTicketID = i.EventTicketID AND ert.EventID = @EventID
        WHERE i.EventRoleID IS NOT NULL AND i.EventTicketID IS NOT NULL;

        UPDATE #Invitations
        SET ResultMsg = CONCAT(ISNULL(ResultMsg + '; ', ''), N'Ismeretlen Jegy + szerepkör!')
        WHERE EventRoleTicketID IS NULL 
          AND EventRoleID IS NOT NULL 
          AND EventTicketID IS NOT NULL
          AND RoleTypeID <> 1;

        -- 6. Hiba riportolás
        DECLARE @ErrorCount INT;
        SELECT @ErrorCount = COUNT(*) FROM #Invitations WHERE ResultMsg IS NOT NULL;

        IF @ErrorCount > 0
        BEGIN
            SELECT 
                -1 AS ReturnValue, 
                N'Az importálás sikertelen hibás sorok miatt.' AS ReturnDescription,
                @EventID AS EventID,
                NULL AS BatchID;
                
            SELECT * FROM #Invitations;
            RETURN;
        END

        -- 7. Sikeres Mentés

        -- ValidationCode frissítése 3 napos lejárattal az ÉRINTETT usereknél
        UPDATE u
        SET 
            ValidationCode = i.ValidationCode,
            ValidationCodeExpiry = DATEADD(day, 3, @Now),
            updatedAt = @Now
        FROM [EJ].[tblUser] u
        JOIN #Invitations i ON u.id = i.TargetUserID;

        -- Meghívók rögzítése vagy frissítése
        DECLARE @EventUserActions TABLE (ActionName NVARCHAR(10), RowID INT);

        MERGE INTO [EJ].[tblEventUser] AS target
        USING (SELECT * FROM #Invitations) AS source
        ON target.EventID = @EventID AND target.UserID = source.TargetUserID AND target.EventRoleID = source.EventRoleID
        WHEN MATCHED THEN
            UPDATE SET 
                EventTicketID = source.EventTicketID,
                ActiveFlg = 1,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
        WHEN NOT MATCHED THEN
            INSERT (
                EventID, UserID, EventRoleID, EventTicketID, EventUserStatusID, ActiveFlg, 
                LastUpdatedUserID, createdAt, updatedAt, EventUserUID
            )
            VALUES (
                @EventID, source.TargetUserID, source.EventRoleID, source.EventTicketID, 1, 1, 
                @UserID, @Now, @Now, source.EventUserUID
            )
        OUTPUT $action, source.RowID INTO @EventUserActions(ActionName, RowID);

        -- 7/B. PTA Játékosok létrehozása vagy frissítése (csak ha van tblEventSettings és RoleTypeID = 3)
        IF EXISTS (SELECT 1 FROM [PTA].[tblEventSettings] WHERE EventID = @EventID)
        BEGIN
            MERGE INTO [PTA].[tblEventPlayer] AS target
            USING (
                SELECT 
                    eu.id AS EventUserID, 
                    ISNULL(i.FirstName, '') + ' ' + ISNULL(i.LastName, '') AS NickName,
                    i.OrganizationName, i.TeamName, i.CompanyName, i.RegionName
                FROM #Invitations i
                JOIN [EJ].[tblEventUser] eu ON eu.EventID = @EventID AND eu.UserID = i.TargetUserID AND eu.EventRoleID = i.EventRoleID
                WHERE i.RoleTypeID = 3
            ) AS source
            ON target.EventID = @EventID AND target.EventUserID = source.EventUserID
            WHEN MATCHED THEN
                UPDATE SET
                    NickName = source.NickName,
                    OrganizationName = source.OrganizationName,
                    TeamName = source.TeamName,
                    CompanyName = source.CompanyName,
                    RegionName = source.RegionName,
                    ActiveFlg = 1,
                    LastUpdatedUserID = @UserID,
                    updatedAt = @Now
            WHEN NOT MATCHED THEN
                INSERT (
                    EventID, EventUserID, NickName, 
                    OrganizationName, TeamName, CompanyName, RegionName, 
                    ActiveFlg, LastUpdatedUserID, createdAt, updatedAt
                )
                VALUES (
                    @EventID, source.EventUserID, source.NickName,
                    source.OrganizationName, source.TeamName, source.CompanyName, source.RegionName,
                    1, @UserID, @Now, @Now
                );
        END

        -- 8. Outbox Email küldés (CSAK az újonnan hozzáadott felhasználóknak)
        DECLARE @BatchID UNIQUEIDENTIFIER = NEWID();
        DECLARE @TemplateID INT;
        SELECT @TemplateID = id FROM [EJ].[tblEmailTemplate] WHERE MailerSendID = 'jy7zpl9rkm5l5vx6';
        
        DECLARE @Mode NVARCHAR(50) = (SELECT ParamValue FROM [EJ].[tblSystemParam] WHERE ParamName = 'RunningMode');
        DECLARE @BaseUrl NVARCHAR(500) = (SELECT ParamValue FROM [EJ].[tblSystemParam] WHERE ParamName = 'FrontendBaseUrl_' + @Mode);

        DECLARE @OutboxIDs TABLE (EmailID INT, RowID INT);
        
        MERGE INTO [EJ].[tblEmailOutbox] AS target
        USING (
            SELECT i.* 
            FROM #Invitations i
            JOIN @EventUserActions eua ON i.RowID = eua.RowID
            WHERE eua.ActionName = 'INSERT' AND i.Email IS NOT NULL AND i.Email <> ''
        ) AS source
        ON 1=0
        WHEN NOT MATCHED THEN
            INSERT (BatchID, TemplateID, RefID, UserID, EmailName, EmailAddress, createdAt, StatusID)
            VALUES (@BatchID, @TemplateID, source.TargetUserID, source.TargetUserID, '', source.Email, @Now, 0)
        OUTPUT inserted.id, source.RowID INTO @OutboxIDs;

        -- FirstName
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt)
        SELECT o.EmailID, 'FirstName', ISNULL(i.FirstName, ''), @UserID, @Now, @Now
        FROM @OutboxIDs o JOIN #Invitations i ON o.RowID = i.RowID;

        -- EventName
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt)
        SELECT o.EmailID, 'EventName', ISNULL(@EventName, ''), @UserID, @Now, @Now
        FROM @OutboxIDs o JOIN #Invitations i ON o.RowID = i.RowID;

        -- EntryCode
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt)
        SELECT o.EmailID, 'EntryCode', i.ValidationCode, @UserID, @Now, @Now
        FROM @OutboxIDs o JOIN #Invitations i ON o.RowID = i.RowID;

        -- EntryLink
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt)
        SELECT o.EmailID, 'EntryLink', @BaseUrl + '/invite/' + CAST(i.EventUserUID AS NVARCHAR(36)), @UserID, @Now, @Now
        FROM @OutboxIDs o JOIN #Invitations i ON o.RowID = i.RowID;

        -- Sikeres válasz
        SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID, @BatchID AS BatchID;
        SELECT * FROM #Invitations;

    END TRY
    BEGIN CATCH
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID, NULL AS BatchID;
    END CATCH
END
GO
