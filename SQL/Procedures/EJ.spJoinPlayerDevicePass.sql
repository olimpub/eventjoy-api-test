SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spJoinPlayerDevicePass]
    @PassToken NVARCHAR(128),
    @DeviceId UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

    IF @DeviceId IS NULL
    BEGIN
        SELECT 400 AS ReturnValue, N'Hiányzik az eszköz.' AS ReturnDescription;
        RETURN;
    END

    -- 1. Pass keresése
    DECLARE @PassID BIGINT;
    DECLARE @EventID BIGINT;
    DECLARE @EventUserID BIGINT;
    DECLARE @BoundDeviceId UNIQUEIDENTIFIER;
    DECLARE @ExpiresAtUtc DATETIMEOFFSET;
    DECLARE @ActiveFlg BIT;

    SELECT TOP 1
        @PassID = id,
        @EventID = EventID,
        @EventUserID = EventUserID,
        @BoundDeviceId = DeviceId,
        @ExpiresAtUtc = ExpiresAtUtc,
        @ActiveFlg = ActiveFlg
    FROM [EJ].[tblPlayerDevicePass]
    WHERE PassToken = @PassToken;

    IF @PassID IS NULL OR @ActiveFlg = 0 OR @ExpiresAtUtc <= @Now
    BEGIN
        SELECT 404 AS ReturnValue, N'A belépő kód nem érvényes.' AS ReturnDescription;
        RETURN;
    END

    -- 2. Kötés ellenőrzése
    IF @BoundDeviceId IS NULL
    BEGIN
        -- Első olvasás: kötjük ehhez az eszközhöz
        UPDATE [EJ].[tblPlayerDevicePass]
        SET DeviceId = @DeviceId,
            BoundAtUtc = @Now,
            updatedAt = @Now
        WHERE id = @PassID;
    END
    ELSE IF @BoundDeviceId <> @DeviceId
    BEGIN
        -- Másik eszköz: 409
        SELECT 409 AS ReturnValue, N'Ez a belépő már másik telefonhoz tartozik.' AS ReturnDescription;
        RETURN;
    END

    -- 3. Résztvevő és Esemény adatok lekérdezése
    DECLARE @UserID BIGINT;
    DECLARE @Email NVARCHAR(300);
    DECLARE @IsSysadmin BIT = 0;
    DECLARE @CurrentEUStatusID BIGINT;
    DECLARE @TargetRoleTypeID BIGINT;
    DECLARE @TargetRoleName NVARCHAR(100);
    DECLARE @TargetRoleCode NVARCHAR(100);
    DECLARE @EventStatusName NVARCHAR(200);

    SELECT 
        @UserID = eu.UserID,
        @Email = u.EmailAddress,
        @IsSysadmin = ISNULL(u.IsSysadmin, 0),
        @CurrentEUStatusID = eu.EventUserStatusID,
        @TargetRoleTypeID = r.RoleTypeID,
        @TargetRoleName = r.RoleName,
        @TargetRoleCode = r.Code
    FROM [EJ].[tblEventUser] eu
    LEFT JOIN [EJ].[tblUser] u ON eu.UserID = u.id
    LEFT JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
    LEFT JOIN [EJ].[tblRole] r ON er.RoleID = r.id
    WHERE eu.id = @EventUserID;

    SELECT 
        @EventStatusName = s.StatusName
    FROM [EJ].[tblEvent] e
    LEFT JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id
    WHERE e.id = @EventID;

    -- Játékmester-e a célzott résztvevő?
    DECLARE @IsTargetGameMaster BIT = 0;
    IF (
        @TargetRoleName IN (N'Játékmester', N'Game Master', N'Gamemaster', N'Munkatárs')
        OR @TargetRoleCode IN (N'game_master', N'staff')
        OR @TargetRoleTypeID = 2
    )
    BEGIN
        SET @IsTargetGameMaster = 1;
    END

    -- 4. Beléptetés (CheckIn) döntés:
    -- eventStatusReachedCheckIn (Bejelentkezés, sorsolás, játék, lezárás, eredmény).
    DECLARE @NormalizedStatus NVARCHAR(200) = LOWER(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(ISNULL(@EventStatusName, ''), N'á', 'a'), N'é', 'e'), N'í', 'i'), N'ó', 'o'), N'ö', 'o'), N'ő', 'o'), N'ú', 'u'), N'ü', 'u'), N'ű', 'u'));
    
    DECLARE @ReachedCheckIn BIT = 0;
    IF @NormalizedStatus LIKE N'%bejelentkez%' 
       OR @NormalizedStatus LIKE N'%sorsol%' 
       OR @NormalizedStatus LIKE N'%jatek%' 
       OR @NormalizedStatus LIKE N'%folyamat%' 
       OR @NormalizedStatus LIKE N'%lezar%' 
       OR @NormalizedStatus LIKE N'%befejez%' 
       OR @NormalizedStatus LIKE N'%eredmeny%' 
       OR @NormalizedStatus LIKE N'%ceremon%' 
       OR @NormalizedStatus LIKE N'%szunet%' 
       OR @NormalizedStatus LIKE N'%vege%'
    BEGIN
        SET @ReachedCheckIn = 1;
    END

    DECLARE @CheckedIn BIT = 0;

    IF @IsTargetGameMaster = 1
    BEGIN
        -- Játékmesternél a státuszt NEM módosítjuk:
        -- Még bejelentkezés előtt: változatlan, CheckedIn = false
        -- Bejelentkezés vagy később: változatlan, CheckedIn = true
        SET @CheckedIn = @ReachedCheckIn;
    END
    ELSE
    BEGIN
        -- Játékos esetén:
        -- Belépett státusz azonosító: 11
        DECLARE @BelepettStatusID INT = 11;

        IF @ReachedCheckIn = 1
        BEGIN
            IF @CurrentEUStatusID <> @BelepettStatusID
            BEGIN
                UPDATE [EJ].[tblEventUser]
                SET PrevEventUserStatusID = CASE WHEN PrevEventUserStatusID IS NULL THEN EventUserStatusID ELSE PrevEventUserStatusID END,
                    EventUserStatusID = @BelepettStatusID,
                    updatedAt = @Now
                WHERE id = @EventUserID;
            END
            SET @CheckedIn = 1;
        END
        ELSE
        BEGIN
            IF @CurrentEUStatusID = @BelepettStatusID
            BEGIN
                SET @CheckedIn = 1;
            END
            ELSE
            BEGIN
                SET @CheckedIn = 0;
            END
        END
    END

    -- 5. Válasz
    SELECT 
        1 AS ReturnValue,
        N'Belépés kész.' AS ReturnDescription,
        @EventID AS EventID,
        @EventUserID AS EventUserID,
        @UserID AS UserID,
        @Email AS Email,
        @IsSysadmin AS IsSysadmin,
        @CheckedIn AS CheckedIn;
END
GO
