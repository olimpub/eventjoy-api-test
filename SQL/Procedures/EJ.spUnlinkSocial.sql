CREATE PROCEDURE [EJ].[spUnlinkSocial]
    @UserID BIGINT,
    @Provider NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = N'Fiók leválasztva.';

    BEGIN TRY
        BEGIN TRANSACTION;

        IF @Provider NOT IN ('Google', 'Facebook')
            THROW 50000, N'Ismeretlen belépési mód.', 1;

        DECLARE @CurrentGoogleId NVARCHAR(256), @CurrentFacebookId NVARCHAR(256), @CurrentAppleId NVARCHAR(256);
        SELECT @CurrentGoogleId = GoogleId, @CurrentFacebookId = FacebookId, @CurrentAppleId = AppleId
        FROM [EJ].[tblUser] WHERE id = @UserID;

        IF (@Provider = 'Google' AND @CurrentGoogleId IS NULL) OR (@Provider = 'Facebook' AND @CurrentFacebookId IS NULL)
            THROW 50000, N'Nincs csatolt fiók.', 1;

        -- Check last login path
        DECLARE @ActiveIdentifiers INT = 0;
        SELECT @ActiveIdentifiers = COUNT(*) FROM [EJ].[tblUserLoginIdentifier] WHERE UserID = @UserID AND ActiveFlg = 1;

        DECLARE @RemainingSocials INT = 0;
        IF @Provider = 'Google' AND @CurrentFacebookId IS NOT NULL SET @RemainingSocials = @RemainingSocials + 1;
        IF @Provider = 'Google' AND @CurrentAppleId IS NOT NULL SET @RemainingSocials = @RemainingSocials + 1;

        IF @Provider = 'Facebook' AND @CurrentGoogleId IS NOT NULL SET @RemainingSocials = @RemainingSocials + 1;
        IF @Provider = 'Facebook' AND @CurrentAppleId IS NOT NULL SET @RemainingSocials = @RemainingSocials + 1;

        IF @ActiveIdentifiers = 0 AND @RemainingSocials = 0
            THROW 50000, N'Legalább egy belépési módot hagyj meg (e-mail, telefon vagy másik fiók).', 1;

        -- Unlink
        UPDATE [EJ].[tblUser]
        SET GoogleId = CASE WHEN @Provider = 'Google' THEN NULL ELSE GoogleId END,
            FacebookId = CASE WHEN @Provider = 'Facebook' THEN NULL ELSE FacebookId END,
            updatedAt = SYSDATETIMEOFFSET()
        WHERE id = @UserID;

        COMMIT TRANSACTION;

        -- ResultSet 1
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- ResultSet 2 (User, SocialLogins, LoginIdentifiers)
        SELECT 'User' AS ResultName;
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
