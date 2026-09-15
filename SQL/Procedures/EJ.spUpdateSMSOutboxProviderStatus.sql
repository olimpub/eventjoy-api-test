SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE   PROCEDURE [EJ].[spUpdateSMSOutboxProviderStatus]
    @ProviderID VARCHAR(50),
    @ProviderStatusID SMALLINT, -- 1 Delivered, 2 Buffered, 3 Failed
    @DeliveredAt DATETIMEOFFSET(7) = NULL,
    @BufferedAt DATETIMEOFFSET(7) = NULL
 AS
 BEGIN
    SET NOCOUNT ON;
        DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);
        BEGIN TRY
            -- Meghívó létezésének ellenőrzése
            IF EXISTS(SELECT 1 FROM [EJ].[tblSMSOutbox] WHERE ProviderID=@ProviderID)
            BEGIN
                UPDATE ob
                SET ob.ProviderStatusID = @ProviderStatusID,
                    ob.deliveredAt = @DeliveredAt,
                    ob.bufferedAt = @BufferedAt
                FROM [EJ].[tblSMSOutbox] ob
                WHERE ob.ProviderID = @ProviderID;
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


