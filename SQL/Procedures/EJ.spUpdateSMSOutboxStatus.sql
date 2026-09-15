SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

--Amikor megjön a válasz, hogy a BulkGate felküldése sikeres volt, akkor a státuszt 2-re állítjuk, és a providerID-t is beírjuk.
CREATE   PROCEDURE [EJ].[spUpdateSMSOutboxStatus]
    @ID INT,
    @ProviderID VARCHAR(50),
    @StatusID SMALLINT --2 Sent to BulkGate(HTTP 200), -- -2 Failed to send to BulkGate (HTTP 400)
 AS
BEGIN
    SET NOCOUNT ON;
        DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);
        BEGIN TRY
            -- Meghívó létezésének ellenőrzése
            IF EXISTS(SELECT 1 FROM [EJ].[tblSMSOutbox] WHERE id=@ID)
            BEGIN
                UPDATE ob
                SET ob.StatusID = @StatusID,
                    ob.ProviderID=@ProviderID,    
                    ob.processedAt = GETDATE()
                FROM [EJ].[tblSMSOutbox] ob
                WHERE ob.id = @ID;
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
        END TRY
        BEGIN CATCH
            SET @ReturnValue = -1;
            SELECT @ReturnDescription = ERROR_MESSAGE();
            
            -- RS 1: Visszatérési állapot hiba esetén
            SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
        END CATCH
    END


