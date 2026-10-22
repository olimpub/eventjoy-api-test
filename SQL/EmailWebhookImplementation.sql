CREATE OR ALTER PROCEDURE [EJ].[spUpdateEmailOutboxStatus]
	@UID UNIQUEIDENTIFIER,
	@MailerSendID VARCHAR(100),
	@StatusID SMALLINT  -- 1: Processing, 2: Sent To MailerSend, -1: Error
	AS
	BEGIN
		SET NOCOUNT ON;
		DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success';
		BEGIN TRY
			IF EXISTS(SELECT 1 FROM [EJ].[tblEmailOutbox] WHERE [BatchID] = @UID)
			BEGIN
				UPDATE [EJ].[tblEmailOutbox]
				SET StatusID = @StatusID,
					MailerSendID = @MailerSendID,
                    processedAt = GETUTCDATE()
				WHERE [BatchID] = @UID;
				SET @ReturnValue = 1;
				SET @ReturnDescription = 'Status updated successfully.';
			END
			ELSE
			BEGIN
				SET @ReturnValue = -1;
				SET @ReturnDescription = 'No record found with the given BatchID.';
			END
			SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
		END TRY
		BEGIN CATCH
			SET @ReturnValue = -1;
			SELECT @ReturnDescription = ERROR_MESSAGE();
			SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
		END CATCH
	END
GO

CREATE OR ALTER PROCEDURE [EJ].[spUpdateEmailOutboxProviderStatus](
    @MailerSendID VARCHAR(50),
    @EmailAddress NVARCHAR(300),
    @ProviderStatusID SMALLINT, -- 1: Delivered, 2: Bounced, 3: Opened, 4: Clicked 
    @ActionDate DATETIMEOFFSET(7) = NULL
)
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);
    DECLARE @TargetID INT;

    BEGIN TRY
        SELECT TOP 1 @TargetID = id
        FROM [EJ].[tblEmailOutbox]
        WHERE [MailerSendID] = @MailerSendID AND EmailAddress = @EmailAddress
        ORDER BY id DESC;

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
            SET @ReturnDescription = 'Nincs ilyen request (MailerSendID + Email)!';
        END
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END
GO
