SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spCreateOrGetPlayerPass]
    @EventID BIGINT,
    @EventUserID BIGINT,
    @CallerUserID BIGINT,
    @Rotate BIT = 0,
    @NewPassToken NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

    -- 1. Ellenőrizzük, hogy a hívó szervező vagy játékmester-e ezen az eseményen
    IF NOT EXISTS (
        SELECT 1 FROM [EJ].[tblEventUser] eu
        INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
        INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
        WHERE eu.EventID = @EventID AND eu.UserID = @CallerUserID AND eu.ActiveFlg = 1
          AND (
              r.RoleTypeID = 1 
              OR r.RoleName IN (N'Organizer', N'Szervező', N'Házigazda', N'Tulajdonos') 
              OR r.Code IN (N'organizer', N'host', N'owner')
              OR r.RoleTypeID = 2 
              OR r.RoleName IN (N'Játékmester', N'Game Master', N'Gamemaster', N'Munkatárs') 
              OR r.Code IN (N'game_master', N'staff')
          )
    )
    BEGIN
        SELECT 403 AS ReturnValue, N'Ehhez nincs jogosultságod.' AS ReturnDescription;
        RETURN;
    END

    -- 2. Ellenőrizzük a célzott résztvevőt (EventUser):
    -- Játékos vagy Játékmester lehet, és léteznie kell UserID-nak
    DECLARE @TargetUserID BIGINT;
    DECLARE @TargetRoleTypeID BIGINT;
    DECLARE @TargetRoleName NVARCHAR(100);
    DECLARE @TargetRoleCode NVARCHAR(100);

    SELECT 
        @TargetUserID = eu.UserID,
        @TargetRoleTypeID = r.RoleTypeID,
        @TargetRoleName = r.RoleName,
        @TargetRoleCode = r.Code
    FROM [EJ].[tblEventUser] eu
    INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
    INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
    WHERE eu.id = @EventUserID AND eu.EventID = @EventID AND eu.ActiveFlg = 1;

    IF @TargetRoleTypeID IS NULL
    BEGIN
        SELECT 400 AS ReturnValue, N'Ez a kód csak játékosnak vagy játékmesternek adható.' AS ReturnDescription;
        RETURN;
    END

    DECLARE @IsTargetPlayer BIT = 0;
    DECLARE @IsTargetGameMaster BIT = 0;

    IF (
        @TargetRoleTypeID = 3 
        OR @TargetRoleName IN (N'Játékos', N'Player', N'Résztvevő', N'Participant') 
        OR @TargetRoleCode IN (N'player', N'participant')
    )
    BEGIN
        SET @IsTargetPlayer = 1;
    END

    IF (
        @TargetRoleName IN (N'Játékmester', N'Game Master', N'Gamemaster', N'Munkatárs')
        OR @TargetRoleCode IN (N'game_master', N'staff')
        OR @TargetRoleTypeID = 2
    )
    BEGIN
        SET @IsTargetGameMaster = 1;
    END

    -- Játékos vagy Játékmester szerepkör ellenőrzése
    IF @IsTargetPlayer = 0 AND @IsTargetGameMaster = 0
    BEGIN
        SELECT 400 AS ReturnValue, N'Ez a kód csak játékosnak vagy játékmesternek adható.' AS ReturnDescription;
        RETURN;
    END

    IF @TargetUserID IS NULL
    BEGIN
        SELECT 400 AS ReturnValue, N'Ehhez a játékoshoz nincs fiók.' AS ReturnDescription;
        RETURN;
    END

    -- 3. Lejárat számítása:
    -- kiadástól 24 óra, vagy az esemény vége + 2 óra, amelyik későbbi.
    DECLARE @Expiry24h DATETIMEOFFSET = DATEADD(hour, 24, @Now);
    DECLARE @EndAtUtc DATETIMEOFFSET = (SELECT EndAtUtc FROM [EJ].[tblEvent] WHERE id = @EventID);
    DECLARE @ExpiryEventEnd DATETIMEOFFSET = CASE WHEN @EndAtUtc IS NOT NULL THEN DATEADD(hour, 2, @EndAtUtc) ELSE @Expiry24h END;
    DECLARE @CalculatedExpiry DATETIMEOFFSET = CASE WHEN @ExpiryEventEnd > @Expiry24h THEN @ExpiryEventEnd ELSE @Expiry24h END;

    -- 4. Meglévő kód keresése
    DECLARE @ExistingPassID BIGINT;
    DECLARE @ExistingPassToken NVARCHAR(128);
    DECLARE @ExistingExpiresAtUtc DATETIMEOFFSET;

    SELECT TOP 1
        @ExistingPassID = id,
        @ExistingPassToken = PassToken,
        @ExistingExpiresAtUtc = ExpiresAtUtc
    FROM [EJ].[tblPlayerDevicePass]
    WHERE EventID = @EventID AND EventUserID = @EventUserID AND ActiveFlg = 1
    ORDER BY id DESC;

    -- Ha Rotate = 0 és van élő kód: ugyanazt adjuk vissza
    IF @Rotate = 0 AND @ExistingPassID IS NOT NULL AND @ExistingExpiresAtUtc > @Now
    BEGIN
        SELECT 
            1 AS ReturnValue,
            N'Belépő kész.' AS ReturnDescription,
            @ExistingPassToken AS PassToken,
            @ExistingExpiresAtUtc AS ExpiresAtUtc;
        RETURN;
    END

    -- Egyébként (Rotate = 1 vagy lejárt kód):
    -- Előző kódok inaktiválása
    UPDATE [EJ].[tblPlayerDevicePass]
    SET ActiveFlg = 0, updatedAt = @Now
    WHERE EventID = @EventID AND EventUserID = @EventUserID AND ActiveFlg = 1;

    -- Új pass beszúrása
    INSERT INTO [EJ].[tblPlayerDevicePass] (
        EventID,
        EventUserID,
        PassToken,
        DeviceId,
        BoundAtUtc,
        ExpiresAtUtc,
        ActiveFlg,
        CreatedByUserID,
        createdAt,
        updatedAt
    ) VALUES (
        @EventID,
        @EventUserID,
        @NewPassToken,
        NULL,
        NULL,
        @CalculatedExpiry,
        1,
        @CallerUserID,
        @Now,
        @Now
    );

    SELECT 
        1 AS ReturnValue,
        N'Belépő kész.' AS ReturnDescription,
        @NewPassToken AS PassToken,
        @CalculatedExpiry AS ExpiresAtUtc;
END
GO
