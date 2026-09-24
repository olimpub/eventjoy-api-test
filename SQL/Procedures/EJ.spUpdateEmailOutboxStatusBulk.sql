CREATE OR ALTER PROCEDURE [EJ].[spUpdateEmailOutboxStatusBulk]
    @EmailIDsJSON NVARCHAR(MAX),
    @MailerSendID NVARCHAR(255),
    @StatusID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);

    BEGIN TRY
        UPDATE [EJ].[tblEmailOutbox]
        SET StatusID = @StatusID,
            MailerSendID = @MailerSendID,
            processedAt = GETUTCDATE()
        WHERE id IN (
            SELECT value FROM OPENJSON(@EmailIDsJSON)
        );

        SET @ReturnValue = 1;
        SET @ReturnDescription = 'Success';
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
    END CATCH
    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
END
