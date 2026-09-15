SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

    
    ALTER PROCEDURE [EJ].[spRegisterUser]
        @EmailAddress NVARCHAR(300),
        @PhoneNumber NVARCHAR(50),
        @PasswordHash NVARCHAR(512)
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'
        
        BEGIN TRY
            -- EllenĹ‘rizzĂĽk, hogy lĂ©tezik-e mĂˇr a rendszerben ez a fiĂłk
            IF EXISTS(SELECT 1 FROM [EJ].[tblUser] WHERE (EmailAddress = @EmailAddress AND @EmailAddress IS NOT NULL) OR (PhoneNumber = @PhoneNumber AND
  @PhoneNumber IS NOT NULL))
            BEGIN
                SET @ReturnValue = -1
                SET @ReturnDescription = N'Ez az e-mail cĂ­m vagy telefonszĂˇm mĂˇr regisztrĂˇlva van!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
                RETURN
            END
    
            -- FelhasznĂˇlĂł LĂ©trehozĂˇsa (StatusID = 2, vagyis aktĂ­v)
            INSERT INTO [EJ].[tblUser] (EmailAddress, PhoneNumber, Password, StatusID)
            VALUES (@EmailAddress, @PhoneNumber, @PasswordHash, 2)
            
            DECLARE @NewUserId INT = SCOPE_IDENTITY()
            UPDATE [EJ].[tblUser] SET LastUpdatedUserID = @NewUserId WHERE id = @NewUserId;
    
            -- RESULT SET 1
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    
            -- RESULT SET 2 (EbbĹ‘l csinĂˇl a C# JWT tokent)
            SELECT 
                @NewUserId AS UserID,
                @EmailAddress AS EmailAddress,
                @PhoneNumber AS PhoneNumber, 0 AS IsSysadmin
                
        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END


