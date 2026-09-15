SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
ALTER PROCEDURE [EJ].[spSocialLogin]
    @Provider NVARCHAR(50),      -- 'Google', 'Apple', vagy 'Facebook'
    @ProviderId NVARCHAR(256),   -- A szolgĂˇltatĂłtĂłl kapott egyedi azonosĂ­tĂł
    @EmailAddress NVARCHAR(300) = NULL,
    @FirstName NVARCHAR(150) = NULL,
    @LastName NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'
    DECLARE @UserId INT = NULL;

    BEGIN TRY
        -- 1. KeresĂ©s ProviderId alapjĂˇn
        IF @Provider = 'Google'
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE GoogleId = @ProviderId;
        ELSE IF @Provider = 'Apple'
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE AppleId = @ProviderId;
        ELSE IF @Provider = 'Facebook'
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE FacebookId = @ProviderId;

        -- 2. Ha nem talĂˇltuk ProviderId alapjĂˇn, nĂ©zzĂĽk meg Email alapjĂˇn!
        IF @UserId IS NULL AND @EmailAddress IS NOT NULL
        BEGIN
            SELECT @UserId = Id FROM [EJ].[tblUser] WHERE EmailAddress = @EmailAddress;
            
            -- Ha megvan email alapjĂˇn, akkor kĂ¶ssĂĽk hozzĂˇ a kĂ¶zĂ¶ssĂ©gi azonosĂ­tĂłt!
            IF @UserId IS NOT NULL
            BEGIN
                IF @Provider = 'Google' UPDATE [EJ].[tblUser] SET GoogleId = @ProviderId, StatusID = 2, LastUpdatedUserID = @UserId WHERE Id = @UserId;
                ELSE IF @Provider = 'Apple' UPDATE [EJ].[tblUser] SET AppleId = @ProviderId, StatusID = 2, LastUpdatedUserID = @UserId WHERE Id = @UserId;
                ELSE IF @Provider = 'Facebook' UPDATE [EJ].[tblUser] SET FacebookId = @ProviderId, StatusID = 2, LastUpdatedUserID = @UserId WHERE Id = @UserId;
            END
        END

        -- 3. Ha mĂ©g mindig nem talĂˇltuk (Teljesen Ăşj FelhasznĂˇlĂł)
        IF @UserId IS NULL
        BEGIN
            INSERT INTO [EJ].[tblUser] (EmailAddress, FirstName, LastName, StatusID, GoogleId, AppleId, FacebookId)
            VALUES (
                @EmailAddress, 
                @FirstName, 
                @LastName, 
                2, -- AktĂ­v (mert a Google/Apple mĂˇr validĂˇlta)
                CASE WHEN @Provider = 'Google' THEN @ProviderId ELSE NULL END,
                CASE WHEN @Provider = 'Apple' THEN @ProviderId ELSE NULL END,
                CASE WHEN @Provider = 'Facebook' THEN @ProviderId ELSE NULL END
            );
            
            SET @UserId = SCOPE_IDENTITY();
            UPDATE [EJ].[tblUser] SET LastUpdatedUserID = @UserId WHERE Id = @UserId;
        END

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

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1
        SELECT @ReturnDescription = ERROR_MESSAGE()
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    END CATCH
END


