-- Created by GitHub Copilot in SSMS - review carefully before executing
SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- ==============================================================================================
-- [EJ].[spVerifyInvitationCode]
-- Felelősség: Meghívó kód ellenőrzése, User azonosítása/létrehozása és hozzárendelése.
-- (Visszaadja a User adatait a JWT tokenhez, akárcsak az spVerifyOTP)
-- ==============================================================================================
CREATE OR ALTER PROCEDURE [EJ].[spVerifyInvitationCode]
    @UID UNIQUEIDENTIFIER,
    @ValidationCode NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = -1;
    DECLARE @ReturnDescription VARCHAR(MAX) = 'Érvénytelen kód vagy UID!';
    DECLARE @UserID BIGINT = NULL;
    DECLARE @EmailAddress NVARCHAR(255) = NULL;

    BEGIN TRY
        -- 1. Meghívó keresése
        IF NOT EXISTS(SELECT 1 FROM [EJ].[tblEventUser] WHERE [EventUserUID] = @UID)
        BEGIN
            SET @ReturnValue = -1;
            SET @ReturnDescription = 'Nincs ilyen meghívó!';
        END
        ELSE
        BEGIN
            -- =========================================================================
            -- TODO: 2. KÓD ELLENŐRZÉSE
            -- Ide jön a kód ellenőrző logika (pl. tblUserOtp vagy ahova le lett mentve)
            -- =========================================================================
            -- PÉLDA (cseréld le a valós ellenőrzésre!):
            -- IF NOT EXISTS(SELECT 1 FROM tblUserOtp WHERE Code = @ValidationCode ...)
            --     THROW 51000, 'Hibás kód!', 1;
            
            -- =========================================================================
            -- TODO: 3. USER LÉTREHOZÁS VAGY KERESÉS
            -- (Mivel csak UID van, ki kell olvasni az emailt a meghívóból és ez alapján keresni a tblUser-ben)
            -- =========================================================================
            
            -- Hozzunk egy dummy sikeres futást:
            SET @ReturnValue = 1;
            SET @ReturnDescription = 'Sikeres kód ellenőrzés!';
            
            -- @UserID = (Az azonosított vagy frissen létrehozott User ID-ja)
            
            -- 4. tblEventUser FRISSÍTÉSE
            -- UPDATE [EJ].[tblEventUser] 
            -- SET UserID = @UserID 
            -- WHERE [EventUserUID] = @UID;
        END

        -- RS 1: Visszatérési állapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- RS 2: User adatok a JWT-hez (Csak ha sikeres volt)
        IF (@ReturnValue = 1 AND @UserID IS NOT NULL)
        BEGIN
            SELECT 
                ID AS UserID, 
                EmailAddress, 
                FirstName, 
                LastName 
            FROM [EJ].[tblUser] 
            WHERE ID = @UserID;
        END
        ELSE IF (@ReturnValue = 1 AND @UserID IS NULL)
        BEGIN
            -- Biztonsági tartalék, ha elfelejtenéd beállítani a @UserID-t
            SELECT 0 AS UserID, 'test@example.com' AS EmailAddress, '' AS FirstName, '' AS LastName;
        END

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnValue AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
