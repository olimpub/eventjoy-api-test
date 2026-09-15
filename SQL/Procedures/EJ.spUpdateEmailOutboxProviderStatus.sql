SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE   PROCEDURE [EJ].[spUpdateEmailOutboxProviderStatus](
    @MailerSendID VARCHAR(50),
    @EmailAddress VARCHAR(100),
    @ProviderStatusID SMALLINT, -- 1, Delivered: 2, Bounced, 3-Opened, 4-Clicked 
    @ActionDate DATETIMEOFFSET(7) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);

    BEGIN TRY
        -- Meghívó létezésének ellenőrzése
        IF EXISTS(SELECT 1 FROM [EJ].[tblEmailOutbox] WHERE [MailerSendID] = @MailerSendID AND EmailAddress=@EmailAddress)
        BEGIN
            UPDATE ob
            SET ob.MailersendStatusID = @ProviderStatusID,
                ob.deliveredAt = CASE WHEN @ProviderStatusID = 1 THEN @ActionDate ELSE ob.deliveredAt END,
                ob.openedAt = CASE WHEN @ProviderStatusID = 3 THEN @ActionDate ELSE ob.openedAt END,
                ob.clickedAt = CASE WHEN @ProviderStatusID = 4 THEN @ActionDate ELSE ob.clickedAt END
            FROM [EJ].[tblEmailOutbox] ob
            WHERE ob.[MailerSendID] = @MailerSendID AND ob.EmailAddress=@EmailAddress;

            SET @ReturnValue = 1;
            SET @ReturnDescription = 'Success';
        END
        ELSE
        BEGIN
            SET @ReturnValue = -1;
            SET @ReturnDescription = 'Nincs ilyen request (UID)!';
        END

        -- RS 1: Visszatérési állapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        
        -- RS 1: Visszatérési állapot hiba esetén
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END


