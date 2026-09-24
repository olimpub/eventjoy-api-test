CREATE OR ALTER PROCEDURE [EJ].[spGetPendingEmailsBulk]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);

    BEGIN TRY
        -- 1. Egy belső változótáblába kimentjük a zárolandó e-maileket
        DECLARE @PendingEmails TABLE (
            EmailID BIGINT,
            BatchID UNIQUEIDENTIFIER
        );

        -- Zárjuk a sorokat (UPDLOCK, READPAST), hogy ne legyen párhuzamos ütközés
        WITH cte AS (
            SELECT TOP 500 id, BatchID, StatusID
            FROM [EJ].[tblEmailOutbox] WITH (UPDLOCK, READPAST)
            WHERE StatusID = 0
            ORDER BY id ASC
        )
        UPDATE cte
        SET StatusID = 1 -- 1 = Feldolgozás alatt
        OUTPUT INSERTED.id, INSERTED.BatchID INTO @PendingEmails;

        IF EXISTS(SELECT 1 FROM @PendingEmails)
        BEGIN
            SET @ReturnValue = 1;
            SET @ReturnDescription = 'Success';
        END
        ELSE
        BEGIN
            SET @ReturnValue = -1;
            SET @ReturnDescription = 'No pending emails';
        END

        -- RS 1: Visszatérési állapot
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- Ha van függőben lévő e-mail
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

            -- RS 3: Email fejléc adatok
            SELECT ob.id AS EmailID,
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
            INNER JOIN @PendingEmails pe ON ob.id = pe.EmailID;

            -- RS 4: Email paraméterek
            SELECT ep.EmailID, ep.ParamName, ep.ParamValue
            FROM [EJ].[tblEmailOutboxParams] ep
            INNER JOIN @PendingEmails pe ON ep.EmailID = pe.EmailID;
        END

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        
        -- RS 1: Visszatérési állapot hiba esetén
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END
