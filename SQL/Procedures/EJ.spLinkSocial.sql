SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
ALTER PROCEDURE [EJ].[spLinkSocial]
    @UserID BIGINT,
    @Provider NVARCHAR(50),
    @ProviderId NVARCHAR(256),
    @EmailAddress NVARCHAR(320) = NULL,
    @FirstName NVARCHAR(150) = NULL,
    @LastName NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = N'FiĂłk csatolva.';

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 1. Validate inputs
        IF @Provider NOT IN ('Google', 'Facebook')
            THROW 50000, N'Ismeretlen belĂ©pĂ©si mĂłd.', 1;

        IF NULLIF(LTRIM(RTRIM(@ProviderId)), '') IS NULL
            THROW 50000, N'HiĂˇnyzĂł fiĂłkazonosĂ­tĂł.', 1;

        IF NULLIF(LTRIM(RTRIM(@EmailAddress)), '') IS NULL
            THROW 50000, N'A fiĂłkhoz nincs e-mail cĂ­m. FacebooknĂˇl engedĂ©lyezd az e-mailt.', 1;

        -- 2. ĂśtkĂ¶zĂ©s â€” ProviderId
        DECLARE @ExistingUserId BIGINT = NULL;
        IF @Provider = 'Google'
            SELECT @ExistingUserId = id FROM [EJ].[tblUser] WHERE GoogleId = @ProviderId;
        ELSE IF @Provider = 'Facebook'
            SELECT @ExistingUserId = id FROM [EJ].[tblUser] WHERE FacebookId = @ProviderId;

        IF @ExistingUserId IS NOT NULL AND @ExistingUserId <> @UserID
            THROW 50000, N'Ez a fiĂłk mĂˇr mĂˇsik EventJoy-felhasznĂˇlĂłhoz tartozik.', 1;

        -- 3. ĂśtkĂ¶zĂ©s â€” E-mail cĂ­m
        DECLARE @EmailConflictUserId BIGINT = NULL;
        -- Check tblUser
        SELECT TOP 1 @EmailConflictUserId = id FROM [EJ].[tblUser] WHERE EmailAddress = @EmailAddress AND id <> @UserID;
        IF @EmailConflictUserId IS NULL
        BEGIN
            -- Check tblLoginIdentifier
            SELECT TOP 1 @EmailConflictUserId = UserID FROM [EJ].[tblUserLoginIdentifier] 
            WHERE IdentifierValueNormalized = LOWER(@EmailAddress) AND IdentifierTypeID = 1 AND ActiveFlg = 1 AND UserID <> @UserID;
        END

        IF @EmailConflictUserId IS NOT NULL
            THROW 50000, N'Ez az e-mail cĂ­m mĂˇr mĂˇsik fiĂłkhoz tartozik.', 1;

        -- 4. MĂˇr van mĂˇs csatolt fiĂłkja ugyanezen a provideren
        DECLARE @CurrentGoogleId NVARCHAR(256), @CurrentFacebookId NVARCHAR(256), @OldEmail NVARCHAR(320);
        SELECT @CurrentGoogleId = GoogleId, @CurrentFacebookId = FacebookId, @OldEmail = EmailAddress
        FROM [EJ].[tblUser] WHERE id = @UserID;

        IF @Provider = 'Google' AND @CurrentGoogleId IS NOT NULL AND @CurrentGoogleId <> @ProviderId
            THROW 50000, N'MĂˇr van csatolt Google-fiĂłkod. ElĹ‘bb vĂˇlaszd le.', 1;
        IF @Provider = 'Facebook' AND @CurrentFacebookId IS NOT NULL AND @CurrentFacebookId <> @ProviderId
            THROW 50000, N'MĂˇr van csatolt Facebook-fiĂłkod. ElĹ‘bb vĂˇlaszd le.', 1;

        -- 5-7. Update tblUser (fill-if-empty)
        UPDATE [EJ].[tblUser]
        SET EmailAddress = COALESCE(NULLIF(LTRIM(RTRIM(EmailAddress)), ''), NULLIF(LTRIM(RTRIM(@EmailAddress)), '')),
            FirstName = COALESCE(NULLIF(LTRIM(RTRIM(FirstName)), ''), NULLIF(LTRIM(RTRIM(@FirstName)), '')),
            LastName = COALESCE(NULLIF(LTRIM(RTRIM(LastName)), ''), NULLIF(LTRIM(RTRIM(@LastName)), '')),
            LastUpdatedUserID = @UserID,
            GoogleId = CASE WHEN @Provider = 'Google' THEN @ProviderId ELSE GoogleId END,
            FacebookId = CASE WHEN @Provider = 'Facebook' THEN @ProviderId ELSE FacebookId END,
            updatedAt = SYSDATETIMEOFFSET()
        WHERE id = @UserID;

        -- 8. Ăšj Email bekerĂĽlĂ©se az azonosĂ­tĂłk kĂ¶zĂ©
        IF NOT EXISTS (
            SELECT 1 FROM [EJ].[tblUserLoginIdentifier] 
            WHERE UserID = @UserID AND IdentifierValueNormalized = LOWER(@EmailAddress) AND IdentifierTypeID = 1 AND ActiveFlg = 1
        )
        BEGIN
            INSERT INTO [EJ].[tblUserLoginIdentifier] (UserID, IdentifierTypeID, IdentifierValueRaw, IdentifierValueNormalized, IsPrimary, IsVerified, ActiveFlg, LastUpdatedUserID)
            VALUES (@UserID, 1, @EmailAddress, LOWER(@EmailAddress), 0, 1, 1, @UserID);
        END

        COMMIT TRANSACTION;

        -- ResultSet 1
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- ResultSet 2 (User, SocialLogins, LoginIdentifiers)
        SELECT 
            'User' AS ResultName;
        SELECT id AS UserID, FirstName, LastName, EmailAddress, StatusID, createdAt 
        FROM [EJ].[tblUser] WHERE id = @UserID;

        SELECT 'SocialLogins' AS ResultName;
        SELECT 'Google' AS Provider, GoogleId AS ProviderId, EmailAddress, updatedAt AS LinkedAt 
        FROM [EJ].[tblUser] WHERE id = @UserID AND GoogleId IS NOT NULL
        UNION ALL
        SELECT 'Facebook' AS Provider, FacebookId AS ProviderId, EmailAddress, updatedAt AS LinkedAt 
        FROM [EJ].[tblUser] WHERE id = @UserID AND FacebookId IS NOT NULL
        UNION ALL
        SELECT 'Apple' AS Provider, AppleId AS ProviderId, EmailAddress, updatedAt AS LinkedAt 
        FROM [EJ].[tblUser] WHERE id = @UserID AND AppleId IS NOT NULL;

        SELECT 'LoginIdentifiers' AS ResultName;
        SELECT IdentifierTypeID, IdentifierValueRaw, IsPrimary, IsVerified
        FROM [EJ].[tblUserLoginIdentifier] WHERE UserID = @UserID AND ActiveFlg = 1;

    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END

