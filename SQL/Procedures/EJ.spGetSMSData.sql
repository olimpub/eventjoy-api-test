
-- ==============================================================================================
-- [EJ].[spGetInvitationByUid]
-- Felelősség: Esemény meghívó (EventUser) adatainak lekérdezése egyedi azonosító alapján.
-- ==============================================================================================
CREATE   PROCEDURE [EJ].[spGetSMSData]
    @ID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);

    BEGIN TRY
        -- Meghívó létezésének ellenőrzése
        IF EXISTS(SELECT 1 FROM [EJ].[tblSMSOutbox] WHERE id=@ID)
        BEGIN
            SET @ReturnValue = 1;
            SET @ReturnDescription = 'Success';
        END
        ELSE
        BEGIN
            SET @ReturnValue = -1;
            SET @ReturnDescription = 'Nincs ilyen request (ID)!';
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
            (3, 'SMSData');


            -- RS 2: ResultSet lista
            SELECT * FROM @Results;

            -- RS 3: email fejléc adatok (Sender, Recipient, Subject, TemplateID, ReplyTo)
                SELECT ob.ID AS SMSID,
                   ob.SenderType,
                   ob.SenderName,
                   ob.PhoneNo AS RecipientPhone,
                   ob.Message AS MessageContent
                FROM [EJ].[tblSMSOutbox] ob
                WHERE ob.id = @ID;

            -- azure bus-ra elküldve státusz
             UPDATE ob
             SET ob.StatusID = 1
             FROM [EJ].[tblSMSOutbox] ob
             WHERE ob.id = @ID;
          END
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        
        -- RS 1: Visszatérési állapot hiba esetén
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END

