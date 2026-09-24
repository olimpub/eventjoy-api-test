SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [EJ].[spDeviceJoin]
    @Json NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    DECLARE @EventID BIGINT, @EventUserID BIGINT, @UserID BIGINT;

    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @DeviceId NVARCHAR(100) = LOWER(JSON_VALUE(@Json, '$.DeviceId'));
        DECLARE @EventUID UNIQUEIDENTIFIER = JSON_VALUE(@Json, '$.EventUID');
        DECLARE @TeamID INT = JSON_VALUE(@Json, '$.TeamId');
        DECLARE @LastName NVARCHAR(100) = JSON_VALUE(@Json, '$.LastName');
        DECLARE @FirstName NVARCHAR(100) = JSON_VALUE(@Json, '$.FirstName');
        
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

        -- 1. Event keresése (Active, OPFlg = 1, státusz Bejelentkezés vagy azutáni)
        -- Bejelentkezés stádium jellemzően 'bejelentkez', de ha már 'jatek' az is jó.
        SELECT @EventID = e.id
        FROM [EJ].[tblEvent] e
        JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id
        JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id
        WHERE e.EventUID = @EventUID AND e.ActiveFlg = 1 AND et.OPFlg = 1
          AND (s.StatusName LIKE '%bejelentkez%' OR s.StatusName LIKE '%játék%' OR s.StatusName LIKE '%jatek%');

        IF @EventID IS NULL
        BEGIN
            THROW 50000, N'A helyszíni belépés csak a bejelentkezés kezdetétől él, vagy nem érvényes Olimpub esemény.', 1;
        END

        -- 2. User keresése (Identifier alapján)
        DECLARE @LoginTypeID INT = (SELECT id FROM [EJ].[tblLoginIdentifierType] WHERE Code = 'device');
        
        SELECT @UserID = UserID 
        FROM [EJ].[tblLoginIdentifier] 
        WHERE LoginIdentifierTypeID = @LoginTypeID AND LOWER(IdentifierValue) = @DeviceId AND ActiveFlg = 1;

        IF @UserID IS NULL
        BEGIN
            -- 3. Új User létrehozása, ha nincs
            INSERT INTO [EJ].[tblUser] (FirstName, LastName, StatusID, createdAt, updatedAt)
            VALUES (@FirstName, @LastName, 1, @Now, @Now);
            
            SET @UserID = SCOPE_IDENTITY();

            INSERT INTO [EJ].[tblLoginIdentifier] (UserID, LoginIdentifierTypeID, IdentifierValue, ActiveFlg, createdAt, updatedAt)
            VALUES (@UserID, @LoginTypeID, @DeviceId, 1, @Now, @Now);
        END
        ELSE
        BEGIN
            -- Frissítsük a nevet, hátha elgépelte korábban, most jót adott meg
            UPDATE [EJ].[tblUser]
            SET FirstName = @FirstName, LastName = @LastName, updatedAt = @Now
            WHERE id = @UserID;
        END

        -- 4. EventUser keresése vagy létrehozása (Játékos role, Belépett status)
        -- A 'Belépett' státusz ID-ját kikeresni:
        DECLARE @BelepettStatusID INT = (SELECT id FROM [EJ].[tblEventUserStatus] WHERE StatusName LIKE '%belépett%' OR StatusName LIKE '%belepett%');
        IF @BelepettStatusID IS NULL SET @BelepettStatusID = 2; -- Fallback
        
        -- Játékos Role kikeresése ezen az eseményen (3-as az alap Játékos role id)
        DECLARE @PlayerRoleID INT = (SELECT id FROM [EJ].[tblEventRole] WHERE EventID = @EventID AND RoleID = 3 AND ActiveFlg = 1);
        
        SELECT @EventUserID = id
        FROM [EJ].[tblEventUser]
        WHERE EventID = @EventID AND UserID = @UserID AND ActiveFlg = 1;

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

        -- 5. Csapat (TeamId) bekötése, ha van
        IF @TeamID IS NOT NULL
        BEGIN
            -- Ellenőrizzük, hogy létezik-e a csapat ezen az eseményen és aktív-e
            IF NOT EXISTS (SELECT 1 FROM [OP].[tblTeam] WHERE id = @TeamID AND EventID = @EventID AND ActiveFlg = 1)
            BEGIN
                THROW 50001, N'A választott csapat nem létezik vagy inaktív.', 1;
            END

            -- Ellenőrizzük, hogy tele van-e a csapat
            DECLARE @MaxTeamSize INT = (SELECT MaxTeamSize FROM [OP].[tblEventSettings] WHERE EventID = @EventID);
            DECLARE @CurrentTeamSize INT = (SELECT COUNT(*) FROM [OP].[tblTeamMember] WHERE TeamID = @TeamID AND ActiveFlg = 1);
            
            -- Ha már benne van a csapatban, ne dobjunk hibát, hogy tele van, hagyjuk jóvá
            IF NOT EXISTS (SELECT 1 FROM [OP].[tblTeamMember] WHERE TeamID = @TeamID AND EventUserID = @EventUserID AND ActiveFlg = 1)
            BEGIN
                IF @CurrentTeamSize >= @MaxTeamSize
                BEGIN
                    THROW 50002, N'A csapat betelt.', 1;
                END
                
                -- Töröljük a korábbi tagságot, ha máshol volt
                UPDATE [OP].[tblTeamMember] SET ActiveFlg = 0 WHERE EventUserID = @EventUserID;

                INSERT INTO [OP].[tblTeamMember] (TeamID, EventUserID, ActiveFlg)
                VALUES (@TeamID, @EventUserID, 1);
            END
        END

        COMMIT TRANSACTION;
        
        SELECT 1 AS ReturnValue, N'Belépés kész.' AS ReturnDescription, @EventID AS EventID, @EventUserID AS EventUserID, @UserID AS UserID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID, NULL AS EventUserID, NULL AS UserID;
    END CATCH
END
GO
