SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
    
    CREATE PROCEDURE [EJ].[spCheckEmail]
        @EmailAddress NVARCHAR(300)
    AS
    BEGIN
        SET NOCOUNT ON;
    
        DECLARE     
            @ReturnValue INT = 1,
            @ReturnDescription VARCHAR(MAX) = 'Success'
    
        BEGIN TRY
            -- Alapértékek
            DECLARE @Exists BIT = 0;
            DECLARE @HasPassword BIT = 0;
            DECLARE @StatusID INT = 0;
    
            -- Adatok lekérése
            SELECT 
                @Exists = 1,
                @HasPassword = CASE WHEN [Password] IS NOT NULL AND [Password] != '' THEN 1 ELSE 0 END,
                @StatusID = StatusID
            FROM [EJ].[tblUser]
            WHERE EmailAddress = @EmailAddress;
    
            -- =========================================================================
            -- RESULT SET 1: Állapot
            -- =========================================================================
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
            
            -- =========================================================================
            -- RESULT SET 2: Az e-mail cím analízise
            -- =========================================================================
            SELECT 
                @Exists AS UserExists, 
                @HasPassword AS HasPassword, 
                @StatusID AS StatusID;

        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            
            -- Hiba esetén is vissza kell adni az 1. Result Set-et
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END


