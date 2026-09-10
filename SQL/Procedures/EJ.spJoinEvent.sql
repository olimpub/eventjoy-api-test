CREATE OR ALTER PROCEDURE [EJ].[spJoinEvent]
    @EventUID UNIQUEIDENTIFIER,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    SET QUOTED_IDENTIFIER ON;
    DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
    BEGIN TRY
        -- 1. Check Event
        DECLARE @EventID BIGINT, @EventStatusID BIGINT, @EventFlowID BIGINT, @Capacity INT;
        SELECT 
            @EventID = e.id, 
            @EventStatusID = e.EventStatusID,
            @EventFlowID = et.EventFlowID,
            @Capacity = e.Capacity
        FROM [EJ].[tblEvent] e
        JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id
        WHERE e.EventUID = @EventUID AND e.ActiveFlg = 1;

        IF @EventID IS NULL
        BEGIN
            SELECT 404 AS ReturnValue, N'Esemény nem található.' AS ReturnDescription, NULL AS EventID, NULL AS EventUserID;
            RETURN;
        END

        -- 2. Check if CheckInOpen
        DECLARE @CheckInStepID INT;
        SELECT TOP 1 @CheckInStepID = StepID FROM [EJ].[tblEventFlowStatus] efs
        JOIN [EJ].[tblEventStatus] es ON efs.ToStatusID = es.id
        WHERE efs.EventFlowID = @EventFlowID AND (es.Code = 'checkin' OR es.StatusName LIKE N'%bejelentkez%');

        DECLARE @CurrentStepID INT;
        SELECT TOP 1 @CurrentStepID = StepID FROM [EJ].[tblEventFlowStatus] WHERE EventFlowID = @EventFlowID AND ToStatusID = @EventStatusID;

        IF @CurrentStepID < @CheckInStepID OR @CheckInStepID IS NULL
        BEGIN
            SELECT 400 AS ReturnValue, N'A helyszíni belépés a bejelentkezéstől él.' AS ReturnDescription, @EventID AS EventID, NULL AS EventUserID;
            RETURN;
        END

        -- 3. Check Name
        DECLARE @FirstName NVARCHAR(150), @LastName NVARCHAR(150);
        SELECT @FirstName = FirstName, @LastName = LastName FROM [EJ].[tblUser] WHERE id = @UserID;
        IF @FirstName IS NULL OR TRIM(@FirstName) = '' OR @LastName IS NULL OR TRIM(@LastName) = ''
        BEGIN
            SELECT 400 AS ReturnValue, N'Add meg a neved.' AS ReturnDescription, @EventID AS EventID, NULL AS EventUserID;
            RETURN;
        END

        -- 4. Find Statuses
        DECLARE @StatusCheckedIn BIGINT;
        SELECT @StatusCheckedIn = id FROM [EJ].[tblEventUserStatus] WHERE Code = 'checkedin';

        DECLARE @PlayerRoleID BIGINT, @PlayerEventRoleID BIGINT;
        SELECT @PlayerRoleID = id FROM [EJ].[tblRole] WHERE RoleTypeID = 3 AND RoleName = N'Játékos';
        SELECT TOP 1 @PlayerEventRoleID = id FROM [EJ].[tblEventRole] WHERE EventID = @EventID AND RoleID = @PlayerRoleID AND ActiveFlg = 1;

        IF @PlayerEventRoleID IS NULL
        BEGIN
            SELECT 400 AS ReturnValue, N'Nincs játékos szerepkör az eseményen.' AS ReturnDescription, @EventID AS EventID, NULL AS EventUserID;
            RETURN;
        END

        -- 5. Existing rows for user
        DECLARE @ExistingEventUserID BIGINT, @ExistingEventRoleID BIGINT, @ExistingStatusID BIGINT;
        SELECT TOP 1 
            @ExistingEventUserID = eu.id,
            @ExistingEventRoleID = eu.EventRoleID,
            @ExistingStatusID = eu.EventUserStatusID
        FROM [EJ].[tblEventUser] eu
        WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1
        ORDER BY CASE WHEN eu.EventRoleID = @PlayerEventRoleID THEN 0 ELSE 1 END ASC;

        IF @ExistingEventUserID IS NOT NULL
        BEGIN
            -- User is already on the event
            IF @ExistingEventRoleID = @PlayerEventRoleID
            BEGIN
                IF @ExistingStatusID = @StatusCheckedIn
                BEGIN
                    -- Already checked in Player
                    SELECT 0 AS ReturnValue, N'Már beléptél.' AS ReturnDescription, @EventID AS EventID, @ExistingEventUserID AS EventUserID;
                    RETURN;
                END
                ELSE
                BEGIN
                    -- Update Player to checked in
                    UPDATE [EJ].[tblEventUser] 
                    SET PrevEventUserStatusID = EventUserStatusID, EventUserStatusID = @StatusCheckedIn, LastUpdatedUserID = @UserID, updatedAt = @Now
                    WHERE id = @ExistingEventUserID;

                    SELECT 0 AS ReturnValue, N'Belépés kész.' AS ReturnDescription, @EventID AS EventID, @ExistingEventUserID AS EventUserID;
                    RETURN;
                END
            END
            ELSE
            BEGIN
                -- User is an Organizer or GameMaster
                SELECT 0 AS ReturnValue, N'Belépés kész (Szervezőként / Játékmesterként).' AS ReturnDescription, @EventID AS EventID, @ExistingEventUserID AS EventUserID;
                RETURN;
            END
        END

        -- 6. New User Insertion - check capacity first!
        IF ISNULL(@Capacity, 0) > 0
        BEGIN
            DECLARE @ActiveCount INT;
            SELECT @ActiveCount = COUNT(*) FROM [EJ].[tblEventUser] eu
            JOIN [EJ].[tblEventUserStatus] eus ON eu.EventUserStatusID = eus.id
            WHERE eu.EventID = @EventID AND eu.ActiveFlg = 1 AND eus.Code NOT IN ('rejected', 'cancelled_by_user', 'left', 'no_show');

            IF @ActiveCount >= @Capacity
            BEGIN
                SELECT 400 AS ReturnValue, N'A létszám betelt.' AS ReturnDescription, @EventID AS EventID, NULL AS EventUserID;
                RETURN;
            END
        END

        -- 7. Ticket for Player
        DECLARE @PlayerEventTicketID BIGINT = NULL;
        SELECT TOP 1 @PlayerEventTicketID = EventTicketID FROM [EJ].[tblEventRoleTicket] ert
        JOIN [EJ].[tblEventTicket] et ON ert.EventTicketID = et.id
        WHERE ert.EventID = @EventID AND ert.EventRoleID = @PlayerEventRoleID AND et.ActiveFlg = 1
        ORDER BY et.Price ASC; -- prefer free

        -- Insert EventUser
        DECLARE @EventUserUID UNIQUEIDENTIFIER = NEWID();
        DECLARE @NewEventUserID BIGINT;
        
        INSERT INTO [EJ].[tblEventUser] (
            EventID, UserID, EventRoleID, EventTicketID, EventUserStatusID, PrevEventUserStatusID, 
            ActiveFlg, LastUpdatedUserID, createdAt, updatedAt, EventUserUID
        )
        VALUES (
            @EventID, @UserID, @PlayerEventRoleID, @PlayerEventTicketID, @StatusCheckedIn, NULL,
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
                NULL, NULL, NULL, NULL,
                1, @UserID, @Now, @Now
            );
        END

        SELECT 0 AS ReturnValue, N'Belépés kész.' AS ReturnDescription, @EventID AS EventID, @NewEventUserID AS EventUserID;

    END TRY
    BEGIN CATCH
        SELECT 500 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID, NULL AS EventUserID;
    END CATCH
END
GO
