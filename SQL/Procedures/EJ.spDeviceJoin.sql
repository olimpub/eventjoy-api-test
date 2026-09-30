SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
ALTER PROCEDURE [EJ].[spDeviceJoin]
    @Json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    DECLARE @EventID BIGINT, @EventUserID BIGINT, @UserID BIGINT;
    DECLARE @ActualNickname NVARCHAR(100);

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @DeviceId NVARCHAR(100) = LOWER(JSON_VALUE(@Json, '$.DeviceId'));
        DECLARE @EventUID UNIQUEIDENTIFIER = JSON_VALUE(@Json, '$.EventUID');
        DECLARE @Nickname NVARCHAR(100) = LTRIM(RTRIM(JSON_VALUE(@Json, '$.Nickname')));
        
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        DECLARE @IsRejoin BIT = 0;

        IF @Nickname IS NULL OR LEN(@Nickname) < 2
        BEGIN
            SET @IsRejoin = 1;
        END

        -- 1. Cél esemény keresése
        IF @EventUID IS NOT NULL
        BEGIN
            SELECT @EventID = e.id
            FROM [EJ].[tblEvent] e
            JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id
            JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id
            WHERE e.EventUID = @EventUID AND e.ActiveFlg = 1 AND et.OPFlg = 1
              AND s.InProgressFlg = 1;
        END
        ELSE
        BEGIN
            SELECT @EventID = e.id
            FROM [OP].[tblEventSettings] op
            JOIN [EJ].[tblEvent] e ON e.id = op.EventID
            JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id
            WHERE op.CurrentFlg = 1 AND e.ActiveFlg = 1
              AND s.InProgressFlg = 1;
        END

        IF @EventID IS NULL
        BEGIN
            THROW 50000, N'Nincs aktuális Olimpub esemény, vagy a belépés még nem nyílt meg.', 1;
        END

        -- 2. User keresése (Identifier alapján)
        DECLARE @LoginTypeID INT = (SELECT id FROM [EJ].[tblLoginIdentifierType] WHERE Code = 'device');
        IF @LoginTypeID IS NULL SET @LoginTypeID = 2; -- Fallback
        
        SELECT @UserID = UserID 
        FROM [EJ].[tblUserLoginIdentifier] 
        WHERE IdentifierTypeID = @LoginTypeID AND LOWER(IdentifierValueNormalized) = @DeviceId AND ActiveFlg = 1;

        -- 3. EventUser keresése, ha megvan a User
        IF @UserID IS NOT NULL
        BEGIN
            SELECT @EventUserID = id
            FROM [EJ].[tblEventUser]
            WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1;
        END

        -- REJOIN LOGIC
        IF @IsRejoin = 1
        BEGIN
            IF @UserID IS NULL OR @EventUserID IS NULL
            BEGIN
                COMMIT TRANSACTION;
                SELECT 404 AS ReturnValue, N'Nincs belépés ezen az eszközön.' AS ReturnDescription, @EventID AS EventID, NULL AS EventUserID, NULL AS UserID, NULL AS Nickname;
                RETURN;
            END
            ELSE
            BEGIN
                SELECT @ActualNickname = Nickname FROM [EJ].[tblUser] WHERE id = @UserID;
                UPDATE [EJ].[tblEventUser] SET updatedAt = @Now WHERE id = @EventUserID;
            END
        END
        -- JOIN LOGIC
        ELSE
        BEGIN
            IF @UserID IS NULL
            BEGIN
                -- Új User létrehozása, ha nincs
                INSERT INTO [EJ].[tblUser] (Nickname, FirstName, LastName, EmailAddress, PhoneNumber, StatusID, createdAt, updatedAt)
                VALUES (@Nickname, NULL, NULL, NULL, NULL, 1, @Now, @Now);
                
                SET @UserID = SCOPE_IDENTITY();
                SET @ActualNickname = @Nickname;

                INSERT INTO [EJ].[tblUserLoginIdentifier] (UserID, IdentifierTypeID, IdentifierValueRaw, IdentifierValueNormalized, IsPrimary, IsVerified, ActiveFlg, createdAt, updatedAt)
                VALUES (@UserID, @LoginTypeID, @DeviceId, @DeviceId, 0, 1, 1, @Now, @Now);
            END
            ELSE
            BEGIN
                -- Ellenőrizzük, van-e már válasza ezen az eseményen
                DECLARE @HasAnswer BIT = 0;
                IF @EventUserID IS NOT NULL
                BEGIN
                    IF EXISTS (SELECT 1 FROM [OP].[tblAnswer] WHERE EventUserID = @EventUserID)
                       OR EXISTS (SELECT 1 FROM [OP].[tblExtraAnswer] WHERE EventUserID = @EventUserID)
                    BEGIN
                        SET @HasAnswer = 1;
                    END
                END

                IF @HasAnswer = 0
                BEGIN
                    UPDATE [EJ].[tblUser]
                    SET Nickname = @Nickname, updatedAt = @Now
                    WHERE id = @UserID;
                    SET @ActualNickname = @Nickname;
                END
                ELSE
                BEGIN
                    -- Ha már van válasza, a tárolt nickname marad
                    SELECT @ActualNickname = Nickname FROM [EJ].[tblUser] WHERE id = @UserID;
                    IF @ActualNickname IS NULL SET @ActualNickname = @Nickname;
                END
            END

            -- EventUser létrehozása vagy frissítése
            DECLARE @BelepettStatusID INT = (SELECT id FROM [EJ].[tblEventUserStatus] WHERE StatusName LIKE '%belépett%' OR StatusName LIKE '%belepett%');
            IF @BelepettStatusID IS NULL SET @BelepettStatusID = 2; 
            
            DECLARE @PlayerRoleID INT = (SELECT id FROM [EJ].[tblEventRole] WHERE EventID = @EventID AND RoleID = 3 AND ActiveFlg = 1);
            
            IF @EventUserID IS NULL
            BEGIN
                INSERT INTO [EJ].[tblEventUser] (
                    EventID, UserID, EventRoleID, EventUserStatusID, EventUserUID, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt
                )
                VALUES (
                    @EventID, @UserID, @PlayerRoleID, @BelepettStatusID, NEWID(), 1, @UserID, @Now, @Now
                );
                SET @EventUserID = SCOPE_IDENTITY();
            END
            ELSE
            BEGIN
                UPDATE [EJ].[tblEventUser]
                SET EventUserStatusID = @BelepettStatusID, updatedAt = @Now, LastUpdatedUserID = @UserID
                WHERE id = @EventUserID;
            END
        END

        COMMIT TRANSACTION;
        
        SELECT 1 AS ReturnValue, N'Belépés kész.' AS ReturnDescription, @EventID AS EventID, @EventUserID AS EventUserID, @UserID AS UserID, @ActualNickname AS Nickname;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID, NULL AS EventUserID, NULL AS UserID, NULL AS Nickname;
    END CATCH
END
