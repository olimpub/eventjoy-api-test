--Amikor megjön a válasz, hogy a MailerSend felküldése sikeres volt, akkor a státuszt 2-re állítjuk, és a MailerSendID-t is beírjuk.
CREATE   PROCEDURE [EJ].[spUpdateMailOutboxStatus]
	@UID UNIQUEIDENTIFIER,
	@MailerSendID VARCHAR(100),
	@StatusID SMALLINT  -- 1, AzureBus: 2, Sent To MailerSend:  -1, Error
	AS
	BEGIN
		SET NOCOUNT ON;
		DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success';
		BEGIN TRY
			-- Ellenőrizzük, hogy létezik-e a rekord az adott ID-vel
			IF EXISTS(SELECT 1 FROM [EJ].[tblEmailOutbox] WHERE [BatchID] = @UID)
			BEGIN
				-- Frissítjük a státuszt és a MailerSendID-t
				UPDATE [EJ].[tblEmailOutbox]
				SET StatusID = @StatusID,
					MailerSendID = @MailerSendID
				WHERE [BatchID] = @UID;
				SET @ReturnValue = 1;
				SET @ReturnDescription = 'Status updated successfully.';
			END
			ELSE
			BEGIN
				SET @ReturnValue = -1;
				SET @ReturnDescription = 'No record found with the given ID.';
			END
			-- RS 1: Visszatérési állapot
			SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
		END TRY
		BEGIN CATCH
			SET @ReturnValue = -1;
			SELECT @ReturnDescription = ERROR_MESSAGE();
			SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
		END CATCH
	END
