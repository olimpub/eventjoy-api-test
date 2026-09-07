
    
    CREATE PROCEDURE [EJ].[spRegisterUser]
        @EmailAddress NVARCHAR(300),
        @PhoneNumber NVARCHAR(50),
        @PasswordHash NVARCHAR(512)
    AS
    BEGIN
        SET NOCOUNT ON;
        DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'
        
        BEGIN TRY
            -- Ellenőrizzük, hogy létezik-e már a rendszerben ez a fiók
            IF EXISTS(SELECT 1 FROM [EJ].[tblUser] WHERE (EmailAddress = @EmailAddress AND @EmailAddress IS NOT NULL) OR (PhoneNumber = @PhoneNumber AND
  @PhoneNumber IS NOT NULL))
            BEGIN
                SET @ReturnValue = -1
                SET @ReturnDescription = N'Ez az e-mail cím vagy telefonszám már regisztrálva van!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
                RETURN
            END
    
            -- Felhasználó Létrehozása (StatusID = 2, vagyis aktív)
            INSERT INTO [EJ].[tblUser] (EmailAddress, PhoneNumber, Password, StatusID)
            VALUES (@EmailAddress, @PhoneNumber, @PasswordHash, 2)
            
            DECLARE @NewUserId INT = SCOPE_IDENTITY()
    
            -- RESULT SET 1
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    
            -- RESULT SET 2 (Ebből csinál a C# JWT tokent)
            SELECT 
                @NewUserId AS UserID,
                @EmailAddress AS EmailAddress,
                @PhoneNumber AS PhoneNumber
                
        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END

