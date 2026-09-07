
CREATE   PROCEDURE [EJ].[spGetEmailData]
    @UID UNIQUEIDENTIFIER
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);

    BEGIN TRY
        -- Meghívó létezésének ellenőrzése
        IF EXISTS(SELECT 1 FROM [EJ].[tblEmailOutbox] WHERE [BatchID] = @UID)
        BEGIN
            SET @ReturnValue = 1;
            SET @ReturnDescription = 'Success';
        END
        ELSE
        BEGIN
            SET @ReturnValue = -1;
            SET @ReturnDescription = 'Nincs ilyen meghívó (UID)!';
        END

        -- RS 1: Visszatérési állapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- Ha sikeres a validáció, adjuk vissza az adatokat
        IF (@ReturnValue = 1)
        BEGIN
            DECLARE @Results TABLE(
                ResultNo SMALLINT,
                ResultName NVARCHAR(100)
            );

            INSERT INTO @Results (ResultNo, ResultName)
            VALUES
            (1, 'ReturnStatus'),
            (2, 'ResultList'),
            (3, 'EmailHeaders'),
            (4, 'EmailParams');


            -- RS 2: ResultSet lista
            SELECT * FROM @Results;

            -- RS 3: email fejléc adatok (Sender, Recipient, Subject, TemplateID, ReplyTo)
            SELECT ob.ID AS EmailID,
                   ob.BatchID,
                   et.SenderMail,
                   ob.EmailName AS RecipientName,
                   ob.EmailAddress AS RecipientEmail,
                   et.MsgSubject,
                   et.MailerSendID AS TemplateID,
                   et.ReplyToMail,
                   et.ReplyToName
            FROM [EJ].[tblEmailOutbox] ob
            INNER JOIN [EJ].[tblEmailTemplate] et ON ob.TemplateID = et.id
            WHERE ob.BatchID = @UID;

            -- RS 4: Email paraméterek
            SELECT ep.EmailID, ep.ParamName, ep.ParamValue
            FROM [EJ].[tblEmailOutboxParams] ep
            INNER JOIN [EJ].[tblEmailOutbox] ob ON ep.EmailID = ob.id
            WHERE ob.BatchID = @UID;

            --A státusz frissítése, hogy a meghívó lekérdezve lett
            UPDATE [EJ].[tblEmailOutbox]
            SET StatusID = 1 
            WHERE [BatchID] = @UID;

        END
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        
        -- RS 1: Visszatérési állapot hiba esetén
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END


