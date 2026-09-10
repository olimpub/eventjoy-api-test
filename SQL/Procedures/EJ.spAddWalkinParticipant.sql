CREATE OR ALTER PROCEDURE [EJ].[spAddWalkinParticipant]
    @EventID BIGINT,
    @UserID INT,
    @FirstName NVARCHAR(150),
    @LastName NVARCHAR(150),
    @Email NVARCHAR(300),
    @Phone NVARCHAR(50),
    @OrganizationName NVARCHAR(100),
    @TeamName NVARCHAR(100),
    @RegionName NVARCHAR(100),
    @CompanyName NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
    BEGIN TRY
        -- 1. Validations
        IF NOT EXISTS (SELECT 1 FROM [EJ].[tblEvent] WHERE id = @EventID AND ActiveFlg = 1)
        BEGIN
            SELECT -1 AS ReturnValue, N'Az esemény nem található vagy inaktív.' AS ReturnDescription, NULL AS EventUserID;
            RETURN;
        END

        IF @Email IS NULL OR TRIM(@Email) = ''
        BEGIN
            SELECT 400 AS ReturnValue, N'Add meg az e-mail címet.' AS ReturnDescription, NULL AS EventUserID;
            RETURN;
        END

        IF @LastName IS NULL OR TRIM(@LastName) = '' OR @FirstName IS NULL OR TRIM(@FirstName) = ''
        BEGIN
            SELECT 400 AS ReturnValue, N'Vezetéknév és keresztnév kötelező.' AS ReturnDescription, NULL AS EventUserID;
            RETURN;
        END

        IF @Phone IS NOT NULL AND TRIM(@Phone) <> '' AND NOT (@Phone LIKE '+36%' OR @Phone LIKE '06%')
        BEGIN
            SELECT 400 AS ReturnValue, N'Érvénytelen telefonszám.' AS ReturnDescription, NULL AS EventUserID;
            RETURN;
        END

        -- Grouping validations
        DECLARE @OrgGrpFlg BIT = 0, @TeamGrpFlg BIT = 0, @RegionGrpFlg BIT = 0, @CompanyGrpFlg BIT = 0;
        SELECT 
            @OrgGrpFlg = ISNULL(OrganizationGrpFlg, 0),
            @TeamGrpFlg = ISNULL(TeamGrpFlg, 0),
            @RegionGrpFlg = ISNULL(RegionGrpFlg, 0),
            @CompanyGrpFlg = ISNULL(CompanyGrpFlg, 0)
        FROM [PTA].[tblEventSettings]
        WHERE EventID = @EventID;

        IF @OrgGrpFlg = 1 AND (@OrganizationName IS NULL OR TRIM(@OrganizationName) = '')
        BEGIN
            SELECT 400 AS ReturnValue, N'Hiányzó Szervezet' AS ReturnDescription, NULL AS EventUserID; RETURN;
        END
        IF @TeamGrpFlg = 1 AND (@TeamName IS NULL OR TRIM(@TeamName) = '')
        BEGIN
            SELECT 400 AS ReturnValue, N'Hiányzó Csapat' AS ReturnDescription, NULL AS EventUserID; RETURN;
        END
        IF @RegionGrpFlg = 1 AND (@RegionName IS NULL OR TRIM(@RegionName) = '')
        BEGIN
            SELECT 400 AS ReturnValue, N'Hiányzó Régió' AS ReturnDescription, NULL AS EventUserID; RETURN;
        END
        IF @CompanyGrpFlg = 1 AND (@CompanyName IS NULL OR TRIM(@CompanyName) = '')
        BEGIN
            SELECT 400 AS ReturnValue, N'Hiányzó Cég' AS ReturnDescription, NULL AS EventUserID; RETURN;
        END

        -- Auth check: is the caller an Organizer?
        IF NOT EXISTS (
            SELECT 1 FROM [EJ].[tblEventUser] eu
            JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
            JOIN [EJ].[tblRole] r ON er.RoleID = r.id
            WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND r.RoleTypeID = 1
        )
        BEGIN
            SELECT 403 AS ReturnValue, N'Nincs jogosultságod (csak szervező végezheti).' AS ReturnDescription, NULL AS EventUserID;
            RETURN;
        END

        -- Capacity check
        DECLARE @Capacity INT;
        SELECT @Capacity = Capacity FROM [EJ].[tblEvent] WHERE id = @EventID;
        IF ISNULL(@Capacity, 0) > 0
        BEGIN
            DECLARE @ActiveCount INT;
            SELECT @ActiveCount = COUNT(*) FROM [EJ].[tblEventUser] eu
            JOIN [EJ].[tblEventUserStatus] eus ON eu.EventUserStatusID = eus.id
            WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1 AND eus.Code NOT IN ('rejected', 'cancelled_by_user', 'left', 'no_show');

            IF @ActiveCount >= @Capacity
            BEGIN
                SELECT 400 AS ReturnValue, N'A létszám betelt.' AS ReturnDescription, NULL AS EventUserID;
                RETURN;
            END
        END

        -- Duplicate check
        DECLARE @TargetUserID BIGINT = NULL;
        SELECT TOP 1 @TargetUserID = id FROM [EJ].[tblUser] WHERE LOWER(EmailAddress) = LOWER(TRIM(@Email));
        IF @TargetUserID IS NULL
        BEGIN
            SELECT TOP 1 @TargetUserID = UserID FROM [EJ].[tblUserLoginIdentifier] WHERE IdentifierValueNormalized = LOWER(TRIM(@Email)) AND IdentifierTypeID = 1;
        END
        IF @TargetUserID IS NULL AND @Phone IS NOT NULL AND TRIM(@Phone) <> ''
        BEGIN
            SELECT TOP 1 @TargetUserID = id FROM [EJ].[tblUser] WHERE PhoneNumber = TRIM(@Phone);
        END

        IF @TargetUserID IS NOT NULL
        BEGIN
            DECLARE @DupEventUserID BIGINT;
            SELECT TOP 1 @DupEventUserID = eu.id FROM [EJ].[tblEventUser] eu
            WHERE eu.EventID = @EventID AND eu.UserID = @TargetUserID AND eu.ActiveFlg = 1;

            IF @DupEventUserID IS NOT NULL
            BEGIN
                SELECT 409 AS ReturnValue, N'Ez a résztvevő már szerepel a listán.' AS ReturnDescription, @DupEventUserID AS EventUserID;
                RETURN;
            END
        END

        -- Determine TargetUserID. Create tblUser if NULL because tblEventUser.UserID is NOT NULL.
        IF @TargetUserID IS NULL
        BEGIN
            INSERT INTO [EJ].[tblUser] (FirstName, LastName, EmailAddress, PhoneNumber, StatusID, createdAt, updatedAt)
            VALUES (TRIM(@FirstName), TRIM(@LastName), LOWER(TRIM(@Email)), TRIM(@Phone), 1, @Now, @Now);
            SET @TargetUserID = SCOPE_IDENTITY();
        END

        -- EventRoleID for Player
        DECLARE @PlayerRoleID BIGINT, @PlayerEventRoleID BIGINT;
        SELECT @PlayerRoleID = id FROM [EJ].[tblRole] WHERE RoleTypeID = 3 AND RoleName = N'Játékos';
        SELECT TOP 1 @PlayerEventRoleID = id FROM [EJ].[tblEventRole] WHERE EventID = @EventID AND RoleID = @PlayerRoleID AND ActiveFlg = 1;

        IF @PlayerEventRoleID IS NULL
        BEGIN
            SELECT 400 AS ReturnValue, N'Nincs játékos szerepkör az eseményen.' AS ReturnDescription, NULL AS EventUserID;
            RETURN;
        END

        -- Ticket for Player
        DECLARE @PlayerEventTicketID BIGINT = NULL;
        SELECT TOP 1 @PlayerEventTicketID = EventTicketID FROM [EJ].[tblEventRoleTicket] ert
        JOIN [EJ].[tblEventTicket] et ON ert.EventTicketID = et.id
        WHERE ert.EventID = @EventID AND ert.EventRoleID = @PlayerEventRoleID AND et.ActiveFlg = 1
        ORDER BY et.Price ASC; -- prefer free

        -- Determine Status
        DECLARE @EventStatusID BIGINT, @EventFlowID BIGINT;
        SELECT @EventStatusID = e.EventStatusID, @EventFlowID = et.EventFlowID FROM [EJ].[tblEvent] e JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id WHERE e.id = @EventID;

        DECLARE @CheckInStepID INT;
        SELECT TOP 1 @CheckInStepID = StepID FROM [EJ].[tblEventFlowStatus] efs
        JOIN [EJ].[tblEventStatus] es ON efs.ToStatusID = es.id
        WHERE efs.EventFlowID = @EventFlowID AND (es.Code = 'checkin' OR es.StatusName LIKE N'%bejelentkez%');

        DECLARE @CurrentStepID INT;
        SELECT TOP 1 @CurrentStepID = StepID FROM [EJ].[tblEventFlowStatus] WHERE EventFlowID = @EventFlowID AND ToStatusID = @EventStatusID;

        DECLARE @EventUserStatusID BIGINT;
        IF @CurrentStepID >= @CheckInStepID
        BEGIN
            SELECT @EventUserStatusID = id FROM [EJ].[tblEventUserStatus] WHERE Code = 'checkedin';
        END
        ELSE
        BEGIN
            SELECT @EventUserStatusID = id FROM [EJ].[tblEventUserStatus] WHERE Code = 'invited' AND NeedUserApprovalFlg = 1;
        END

        -- Insert EventUser
        DECLARE @EventUserUID UNIQUEIDENTIFIER = NEWID();
        DECLARE @NewEventUserID BIGINT;
        
        INSERT INTO [EJ].[tblEventUser] (
            EventID, UserID, EventRoleID, EventTicketID, EventUserStatusID, PrevEventUserStatusID, 
            ActiveFlg, LastUpdatedUserID, createdAt, updatedAt, EventUserUID
        )
        VALUES (
            @EventID, @TargetUserID, @PlayerEventRoleID, @PlayerEventTicketID, @EventUserStatusID, NULL,
            1, @UserID, @Now, @Now, @EventUserUID
        );
        SET @NewEventUserID = SCOPE_IDENTITY();

        -- Insert EventPlayer if settings exist
        IF EXISTS (SELECT 1 FROM [PTA].[tblEventSettings] WHERE EventID = @EventID)
        BEGIN
            INSERT INTO [PTA].[tblEventPlayer] (
                EventID, EventUserID, NickName, OrganizationName, TeamName, CompanyName, RegionName,
                ActiveFlg, LastUpdatedUserID, createdAt, updatedAt
            )
            VALUES (
                @EventID, @NewEventUserID, TRIM(@FirstName) + ' ' + TRIM(@LastName),
                IIF(@OrgGrpFlg = 1, TRIM(@OrganizationName), NULL),
                IIF(@TeamGrpFlg = 1, TRIM(@TeamName), NULL),
                IIF(@CompanyGrpFlg = 1, TRIM(@CompanyName), NULL),
                IIF(@RegionGrpFlg = 1, TRIM(@RegionName), NULL),
                1, @UserID, @Now, @Now
            );
        END

        -- Outbox
        DECLARE @BatchID UNIQUEIDENTIFIER = NEWID();
        DECLARE @TemplateID INT;
        SELECT @TemplateID = id FROM [EJ].[tblEmailTemplate] WHERE MailerSendID = 'jy7zpl9rkm5l5vx6';

        DECLARE @Mode NVARCHAR(50) = (SELECT ParamValue FROM [EJ].[tblSystemParam] WHERE ParamName = 'RunningMode');
        DECLARE @BaseUrl NVARCHAR(500) = (SELECT ParamValue FROM [EJ].[tblSystemParam] WHERE ParamName = 'FrontendBaseUrl_' + @Mode);
        DECLARE @EventName NVARCHAR(200) = (SELECT Title FROM [EJ].[tblEvent] WHERE id = @EventID);
        DECLARE @ValidationCode NVARCHAR(10) = CAST(ABS(CHECKSUM(NEWID())) % 900000 + 100000 AS NVARCHAR(10));
        
        UPDATE [EJ].[tblUser] SET ValidationCode = @ValidationCode, ValidationCodeExpiry = DATEADD(day, 3, @Now), updatedAt = @Now WHERE id = @TargetUserID;

        DECLARE @OutboxID TABLE (id INT);
        INSERT INTO [EJ].[tblEmailOutbox] (BatchID, TemplateID, RefID, UserID, EmailName, EmailAddress, createdAt, StatusID)
        OUTPUT inserted.id INTO @OutboxID
        VALUES (@BatchID, @TemplateID, @TargetUserID, @TargetUserID, '', LOWER(TRIM(@Email)), @Now, 0);

        DECLARE @InsertedOutboxID INT = (SELECT TOP 1 id FROM @OutboxID);
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt) VALUES (@InsertedOutboxID, 'FirstName', TRIM(@FirstName), @UserID, @Now, @Now);
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt) VALUES (@InsertedOutboxID, 'EventName', @EventName, @UserID, @Now, @Now);
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt) VALUES (@InsertedOutboxID, 'EntryCode', @ValidationCode, @UserID, @Now, @Now);
        INSERT INTO [EJ].[tblEmailOutboxParams] (EmailID, ParamName, ParamValue, LastUpdatedUserID, createdAt, updatedAt) VALUES (@InsertedOutboxID, 'EntryLink', @BaseUrl + '/invite/' + CAST(@EventUserUID AS NVARCHAR(36)), @UserID, @Now, @Now);

        SELECT 0 AS ReturnValue, N'Résztvevő felvéve, meghívó elküldve.' AS ReturnDescription, @NewEventUserID AS EventUserID, @BatchID AS BatchID;

    END TRY
    BEGIN CATCH
        SELECT 500 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventUserID, NULL AS BatchID;
    END CATCH
END
GO

