SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spUpdateEmailOutboxProviderStatus](
    @MailerSendID VARCHAR(50),
    @EmailAddress NVARCHAR(300),
    @ProviderStatusID SMALLINT, -- 1, Delivered: 2, Bounced, 3-Opened, 4-Clicked 
    @ActionDate DATETIMEOFFSET(7) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);
    DECLARE @TargetID INT;

    BEGIN TRY
        -- 1. Pontos egyezés keresése (MailerSendID + EmailAddress)
        SELECT TOP 1 @TargetID = id
        FROM [EJ].[tblEmailOutbox]
        WHERE [MailerSendID] = @MailerSendID AND EmailAddress = @EmailAddress
        ORDER BY id DESC;

        -- 2. Ha nem található (pl. bulk küldésnél a bulk_email_id került mentésre az egyedi message_id helyett),
        --    akkor a címzett legutóbbi kiküldött (StatusID = 2) rekordját frissítjük
        IF @TargetID IS NULL
        BEGIN
            SELECT TOP 1 @TargetID = id
            FROM [EJ].[tblEmailOutbox]
            WHERE EmailAddress = @EmailAddress AND StatusID = 2
            ORDER BY id DESC;
        END

        IF @TargetID IS NOT NULL
        BEGIN
            UPDATE ob
            SET ob.MailerSendID = @MailerSendID,
                ob.MailersendStatusID = @ProviderStatusID,
                ob.deliveredAt = CASE WHEN @ProviderStatusID = 1 THEN @ActionDate ELSE ob.deliveredAt END,
                ob.openedAt = CASE WHEN @ProviderStatusID = 3 THEN @ActionDate ELSE ob.openedAt END,
                ob.clickedAt = CASE WHEN @ProviderStatusID = 4 THEN @ActionDate ELSE ob.clickedAt END
            FROM [EJ].[tblEmailOutbox] ob
            WHERE ob.id = @TargetID;

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


