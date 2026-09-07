
    
    CREATE PROCEDURE [EJ].[spGetAuthData]
        @IdentityValue NVARCHAR(300)
    AS
    BEGIN
        SET NOCOUNT ON;
    
        DECLARE     
            @ReturnValue INT = 1,
            @ReturnDescription VARCHAR(MAX) = 'Success'
    
        BEGIN TRY
            -- Megnézzük, van-e ilyen Aktív (StatusID = 2) felhasználó email vagy telefon alapján
            IF EXISTS(SELECT 1 FROM [EJ].[tblUser] WHERE (EmailAddress = @IdentityValue OR PhoneNumber = @IdentityValue) AND StatusID = 2)
            BEGIN
                -- RESULT SET 1
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
                
                -- RESULT SET 2: Visszaadjuk az adatait és a titkosított jelszavát a C#-nak!
                SELECT TOP 1 
                    Id AS UserID, 
                    EmailAddress, 
                    FirstName, 
                    LastName,
                    [Password] AS PasswordHash
                FROM [EJ].[tblUser]
                WHERE (EmailAddress = @IdentityValue OR PhoneNumber = @IdentityValue) AND StatusID = 2
            END
            ELSE
            BEGIN
                -- Ha nem létezik, vagy nincs aktiválva
                SET @ReturnValue = -1
                SET @ReturnDescription = N'Ezzel az azonosítóval nem található aktív fiók!'
                SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
            END
        END TRY
        BEGIN CATCH
            SET @ReturnValue=-1
            SELECT @ReturnDescription=ERROR_MESSAGE()

            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END

