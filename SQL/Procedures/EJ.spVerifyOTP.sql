
    
    CREATE PROCEDURE [EJ].[spVerifyOTP]
        @IdentityValue NVARCHAR(300),
        @ValidationCode NVARCHAR(10)
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'
        
        BEGIN TRY
            DECLARE @UserId INT;
    
            -- 1. Megkeressük a usert az IdentityValue (E-mail/Telefon) alapján
            SELECT @UserId = Id 
            FROM [EJ].[tblUser] 
            WHERE EmailAddress = @IdentityValue OR PhoneNumber = @IdentityValue;
    
            IF @UserId IS NULL
            BEGIN
                SET @ReturnValue = -1
                SET @ReturnDescription = 'Érvénytelen felhasználó!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
                RETURN
            END
    
            -- 2. Ellenőrizzük az OTP kódot a megtalált UserID-hoz
            IF EXISTS(SELECT 1 FROM [EJ].[tblUser]  WHERE id = @UserId AND ValidationCode = @ValidationCode AND ValidationCodeExpiry > GETDATE())
            BEGIN
                -- Beállítjuk felhasználtra
                UPDATE [EJ].[tblUser] SET ValidationCode = NULL,ValidationCodeExpiry=NULL  WHERE id = @UserId
                
                -- Ha eddig "Pending" (1) volt a státusza, most aktiváljuk (2)
                UPDATE [EJ].[tblUser] SET StatusID = 2 WHERE Id = @UserId AND StatusID = 1
    
                -- RESULT SET 1
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    
                -- RESULT SET 2 (Ebből készül a JWT Token)
                SELECT TOP 1 
                    Id AS UserID, 
                    EmailAddress, 
                    FirstName, 
                    LastName
                FROM [EJ].[tblUser]
                WHERE Id = @UserId
            END
            ELSE
            BEGIN
                SET @ReturnValue = -1
                SET @ReturnDescription = N'Érvénytelen kód!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
            END
        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END

