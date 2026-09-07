CREATE PROCEDURE [EJ].[spSocialLogin]
    @Provider NVARCHAR(50),      -- 'Google', 'Apple', vagy 'Facebook'
    @ProviderId NVARCHAR(256),   -- A szolgáltatótól kapott egyedi azonosító
    @EmailAddress NVARCHAR(300) = NULL,
    @FirstName NVARCHAR(150) = NULL,
    @LastName NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'
    DECLARE @UserId INT = NULL;

    BEGIN TRY
        -- 1. Keresés ProviderId alapján
        IF @Provider = 'Google'
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE GoogleId = @ProviderId;
        ELSE IF @Provider = 'Apple'
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE AppleId = @ProviderId;
        ELSE IF @Provider = 'Facebook'
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE FacebookId = @ProviderId;

        -- 2. Ha nem találtuk ProviderId alapján, nézzük meg Email alapján!
        IF @UserId IS NULL AND @EmailAddress IS NOT NULL
        BEGIN
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE EmailAddress = @EmailAddress;
            
            -- Ha megvan email alapján, akkor kössük hozzá a közösségi azonosítót!
            IF @UserId IS NOT NULL
            BEGIN
                IF @Provider = 'Google' UPDATE [EJ].[tblUser] SET GoogleId = @ProviderId, StatusID = 2 WHERE Id = @UserId;
                ELSE IF @Provider = 'Apple' UPDATE [EJ].[tblUser] SET AppleId = @ProviderId, StatusID = 2 WHERE Id = @UserId;
                ELSE IF @Provider = 'Facebook' UPDATE [EJ].[tblUser] SET FacebookId = @ProviderId, StatusID = 2 WHERE Id = @UserId;
            END
        END

        -- 3. Ha még mindig nem találtuk (Teljesen új Felhasználó)
        IF @UserId IS NULL
        BEGIN
            INSERT INTO [EJ].[tblUser] (EmailAddress, FirstName, LastName, StatusID, GoogleId, AppleId, FacebookId)
            VALUES (
                @EmailAddress, 
                @FirstName, 
                @LastName, 
                2, -- Aktív (mert a Google/Apple már validálta)
                CASE WHEN @Provider = 'Google' THEN @ProviderId ELSE NULL END,
                CASE WHEN @Provider = 'Apple' THEN @ProviderId ELSE NULL END,
                CASE WHEN @Provider = 'Facebook' THEN @ProviderId ELSE NULL END
            );
            
            SET @UserId = SCOPE_IDENTITY();
        END

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

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1
        SELECT @ReturnDescription = ERROR_MESSAGE()
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    END CATCH
END

