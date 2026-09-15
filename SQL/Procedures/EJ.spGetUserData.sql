SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO



-- ==============================================================================================
-- [EJ].[spGetUserData]
-- FelelĹ‘ssĂ©g: Csak a felhasznĂˇlĂł sajĂˇt profilja, beĂˇllĂ­tĂˇsai, preferenciĂˇi, Ă©rtesĂ­tĂ©sei Ă©s chatjei.
-- ==============================================================================================

CREATE OR ALTER PROCEDURE [EJ].[spGetUserData]
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX)

    BEGIN TRY
        IF EXISTS(SELECT 1 FROM [EJ].[tblUser] WHERE id = @UserID AND StatusID NOT IN (3, 4))
        BEGIN
            SET @ReturnValue = 1
            SET @ReturnDescription = 'Success'
        END
        ELSE
        BEGIN
            SET @ReturnValue = -1
            SET @ReturnDescription = 'Nincs ilyen felhasznĂˇlĂł vagy inaktĂ­v profil!'
        END

        -- RS 1: VisszatĂ©rĂ©si Ăˇllapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
        

        IF (@ReturnValue = 1)
        BEGIN
            DECLARE  @Results TABLE(
                ResultNo SMALLINT,
                ResultName NVARCHAR(100)
                )

            INSERT INTO @Results (ResultNo, ResultName)
            VALUES
            (1, 'ReturnStatus'),
            (2, 'ResultList'),
            (3, 'User'),
            (4, 'Notifications'),
            (5, 'ChatThreads'),
            (6, 'EventTypePreferences'),
            (7, 'LabelPreferences'),
            (8, 'Settings'),
            (9, 'LoginIdentifiers'),
            (10, 'BillingAddress'),
            (11, 'MasterDataVersion'),
            (12, 'UserOrganizations'),
            (13, 'SocialLogins');

            --RS 2: ResultSet lista
            SELECT * FROM @Results;

            -- RS 2: tblUser (Alapadatok)
            SELECT id AS UserID, FirstName, LastName, IsSysadmin, EmailAddress, StatusID, createdAt
            FROM [EJ].[tblUser] WHERE id = @UserID;

            -- RS 3: tblNotification (Ă‰rtesĂ­tĂ©sek)
            SELECT TOP 20 id AS NotificationID, NotificationTypeID, Title, MessageBody, ActionUrl, EventID, createdAt, IsRead
            FROM [EJ].[tblNotification] WHERE UserID = @UserID AND ActiveFlg = 1 ORDER BY createdAt DESC;

            -- RS 4: tblChatThreadUser (Chat SzĂˇlak Ă©s UtolsĂł olvasott ĂĽzenet ID-k)
            -- SĂ‰MAMĂ“DOSĂŤTĂS KĂ–VETELMĂ‰NY: Az SQL subquery elkerĂĽlĂ©se vĂ©gett a Kliens (Vue/Pinia) 
            -- szĂˇmolja ki a lokĂˇlis memĂłriĂˇban az olvasatlan ĂĽzeneteket. A szerver csak a LastReadMessageID-t adja Ăˇt FYI jelleggel.
            SELECT ChatThreadID, LastReadMessageID
            FROM [EJ].[tblChatThreadUser] 
            WHERE UserID = @UserID;

            -- RS 5: tblUserEventTypePreference
            SELECT EventTypeID FROM [EJ].[tblUserEventTypePreference] WHERE UserID = @UserID AND ActiveFlg = 1;

            -- RS 6: tblUserLabelPreference
            SELECT LabelID FROM [EJ].[tblUserLabelPreference] WHERE UserID = @UserID AND ActiveFlg = 1;

            -- RS 7: tblUserSettings
            SELECT NotifyNewMessage, NotifyUpcomingEvent, NotifyCommunityNews, NotifyPaymentReminder, AllowEmailNotifications
            FROM [EJ].[tblUserSettings] WHERE UserID = @UserID AND ActiveFlg = 1;

            -- RS 8: tblUserLoginIdentifier
            SELECT IdentifierTypeID, IdentifierValueRaw, IsPrimary, IsVerified
            FROM [EJ].[tblUserLoginIdentifier] WHERE UserID = @UserID AND ActiveFlg = 1;

            -- RS 9: tblUserBillingAddress (SzĂˇmlĂˇzĂˇsi CĂ­m)
            -- (FeltĂ©telezve a szokĂˇsos mezĹ‘ket, csak a teljes tĂˇblĂˇt lekĂ©rjĂĽk a userhez)
            SELECT * FROM [EJ].[tblUserBillingAddress] WHERE UserID = @UserID AND ActiveFlg = 1;

            -- RS 10: tblDataVersion (Max)
            SELECT ISNULL(MAX(VersionNo), 0) AS MasterDataVersion FROM [EJ].[tblDataVersion] WHERE ActiveFlg = 1;

            --RS 11: tblUserOrganization (A felhasznĂˇlĂłhoz tartozĂł szervezetek)
            SELECT UO.id, UO.OrganizationID, UO.IsPrimary, UO.OrganizationUserTypeID
            FROM [EJ].[tblOrganizationUser] UO
            WHERE UO.UserID = @UserID AND UO.ActiveFlg = 1;

            -- RS 12: SocialLogins
            SELECT 
                'Google' AS Provider, 
                GoogleId AS ProviderId, 
                EmailAddress, 
                updatedAt AS LinkedAt 
            FROM [EJ].[tblUser] 
            WHERE id = @UserID AND GoogleId IS NOT NULL
            UNION ALL
            SELECT 
                'Facebook' AS Provider, 
                FacebookId AS ProviderId, 
                EmailAddress, 
                updatedAt AS LinkedAt 
            FROM [EJ].[tblUser] 
            WHERE id = @UserID AND FacebookId IS NOT NULL
            UNION ALL
            SELECT 
                'Apple' AS Provider, 
                AppleId AS ProviderId, 
                EmailAddress, 
                updatedAt AS LinkedAt 
            FROM [EJ].[tblUser] 
            WHERE id = @UserID AND AppleId IS NOT NULL;
        END
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1
        SELECT @ReturnDescription = ERROR_MESSAGE()
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
    END CATCH
END


