
    
    CREATE PROCEDURE [EJ].[spCheckIdentity]
        @IdentityValue NVARCHAR(300)
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
            DECLARE @UserID INT = NULL;
    
            -- Adatok lekérése E-MAIL VAGY TELEFONSZÁM alapján!
            IF EXISTS(SELECT * FROM [EJ].[tblUser] usr WHERE usr.EmailAddress = @IdentityValue OR usr.PhoneNumber = @IdentityValue)
            BEGIN
                SELECT 
                    @Exists = 1,
                    @HasPassword = CASE WHEN [Password] IS NOT NULL AND [Password] != '' THEN 1 ELSE 0 END,
                    @StatusID = StatusID
                FROM [EJ].[tblUser]
                WHERE EmailAddress = @IdentityValue OR PhoneNumber = @IdentityValue;
            END
            ELSE IF EXISTS(SELECT * FROM [EJ].[tblUserLoginIdentifier] le WHERE le.IdentifierValueNormalized = @IdentityValue )
            BEGIN
                 SELECT TOP 1 @UserID = le.UserID FROM [EJ].[tblUserLoginIdentifier] le WHERE le.IdentifierValueNormalized = @IdentityValue 
                 SELECT 
                    @Exists = 1,
                    @HasPassword = CASE WHEN [Password] IS NOT NULL AND [Password] != '' THEN 1 ELSE 0 END,
                    @StatusID = StatusID
                FROM [EJ].[tblUser]
                WHERE id = @UserID;
            END

            -- RESULT SET 1
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
            
            -- RESULT SET 2
            SELECT 
                @Exists AS UserExists, 
                @HasPassword AS HasPassword, 
                @StatusID AS StatusID;

        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1
            SELECT @ReturnDescription = ERROR_MESSAGE()
            
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        END CATCH
    END

