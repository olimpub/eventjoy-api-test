SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

    
    ALTER PROCEDURE [EJ].[spVerifyOTP]
        @IdentityValue NVARCHAR(300),
        @ValidationCode NVARCHAR(10)
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'
        
        BEGIN TRY
            DECLARE @UserId INT;
    
            -- 1. MegkeressĂĽk a usert az IdentityValue (E-mail/Telefon) alapjĂˇn
            SELECT @UserId = Id 
            FROM [EJ].[tblUser] 
            WHERE EmailAddress = @IdentityValue OR PhoneNumber = @IdentityValue;
    
            IF @UserId IS NULL
            BEGIN
                SET @ReturnValue = -1
                SET @ReturnDescription = 'Ă‰rvĂ©nytelen felhasznĂˇlĂł!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
                RETURN
            END
    
            -- 2. EllenĹ‘rizzĂĽk az OTP kĂłdot a megtalĂˇlt UserID-hoz
            IF EXISTS(SELECT 1 FROM [EJ].[tblUser]  WHERE id = @UserId AND ValidationCode = @ValidationCode AND ValidationCodeExpiry > GETDATE())
            BEGIN
                -- BeĂˇllĂ­tjuk felhasznĂˇltra
                UPDATE [EJ].[tblUser] SET ValidationCode = NULL,ValidationCodeExpiry=NULL, LastUpdatedUserID = @UserId  WHERE id = @UserId
                
                -- Ha eddig "Pending" (1) volt a stĂˇtusza, most aktivĂˇljuk (2)
                UPDATE [EJ].[tblUser] SET StatusID = 2, LastUpdatedUserID = @UserId WHERE Id = @UserId AND StatusID = 1
    
                -- RESULT SET 1
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    
                -- RESULT SET 2 (EbbĹ‘l kĂ©szĂĽl a JWT Token)
                SELECT TOP 1 
                    Id AS UserID, 
                    EmailAddress, 
                    FirstName, 
                    LastName,
                    IsSysadmin
                FROM [EJ].[tblUser]
                WHERE Id = @UserId
            END
            ELSE
            BEGIN
                SET @ReturnValue = -1
                SET @ReturnDescription = N'Ă‰rvĂ©nytelen kĂłd!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
            END
        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END


