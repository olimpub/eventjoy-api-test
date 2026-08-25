-- Created by GitHub Copilot in SSMS - review carefully before executing
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ==============================================================================================
-- [EJ].[spGetInvitationByUid]
-- Felelősség: Esemény meghívó (EventUser) adatainak lekérdezése egyedi azonosító alapján,
-- kibővítve Event, EventRole és User (opcionális) adatokkal.
-- ==============================================================================================
ALTER PROCEDURE [EJ].[spGetInvitationByUid]
    @UID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success';

    BEGIN TRY
        -- Meghívó létezésének ellenőrzése
        IF NOT EXISTS(SELECT 1 FROM [EJ].[tblEventUser] WHERE [EventUserUID] = @UID)
        BEGIN
            SET @ReturnValue = -1;
            SET @ReturnDescription = 'Nincs ilyen meghívó (UID)!';
        END

        -- RS 1: Visszatérési állapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- Ha sikeres a validáció, adjuk vissza az adatokat
        IF (@ReturnValue = 1)
        BEGIN
            DECLARE @Results TABLE(
                ResultNo SMALLINT,
                ResultName NVARCHAR(100)
            );

            INSERT INTO @Results (ResultNo, ResultName)
            VALUES
            (1, 'ReturnStatus'),
            (2, 'ResultList'),
            (3, 'InvitationData');

            -- RS 2: ResultSet lista
            SELECT * FROM @Results ORDER BY ResultNo;

            -- RS 3: Meghívó adatok bővítve
            SELECT 
                EU.ID AS EventUserID, 
                EU.EventID, 
                EU.UserID, 
                EU.EventRoleID, 
                EU.EventUserStatusID,
                EU.ActiveFlg,
                E.Title AS EventName,
                E.StartAtUtc AS EventFromDate,
                E.EndAtUtc AS EventToDate,
                R.RoleName AS EventRoleName,
                U.EmailAddress AS UserEmail,
                U.PhoneNumber AS UserPhone
            FROM [EJ].[tblEventUser] EU
            LEFT JOIN [EJ].[tblEvent] E ON EU.EventID = E.ID
            LEFT JOIN [EJ].[tblEventRole] ER ON EU.EventRoleID = ER.ID
            LEFT JOIN [EJ].[tblRole] R ON ER.RoleID = R.ID
            LEFT JOIN [EJ].[tblUser] U ON EU.UserID = U.ID
            WHERE EU.[EventUserUID] = @UID;
        END
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        
        -- RS 1: Visszatérési állapot hiba esetén
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END
GO
