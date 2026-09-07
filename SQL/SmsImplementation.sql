DROP TABLE IF EXISTS [EJ].[tblSMSOutbox]

CREATE TABLE [EJ].[tblSMSOutbox](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[SenderType] [varchar](20) NULL,
	[SenderName] [varchar](15) NOT NULL,
	[RefID] [int] NULL,
	[UserID] [int] NOT NULL,
	[PhoneNo] [varchar](30) NULL,
	[Message] [nvarchar](500) NOT NULL,
	[createdAt] [datetimeoffset](7) NOT NULL,
	[ProviderID] [varchar](50) NULL,
	[StatusID] [smallint] NULL, -- 0:Pending: 1, AzureBus: 2, Sent To BulkGate
	[processedAt] [datetimeoffset](7) NULL,
	[ProviderStatusID] [smallint] NULL, -- 1: Delivered, 2: Buffered, 3: Failed
	[deliveredAt] [datetimeoffset](7) NULL,
	[bufferedAt] [datetimeoffset](7) NULL	
) ON [PRIMARY]
GO

SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [EJ].[spGetSMSData]
    @ID INT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);

    BEGIN TRY
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

        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        IF (@ReturnValue = 1)
        BEGIN
            DECLARE @Results TABLE(ResultNo SMALLINT, ResultName NVARCHAR(100));
            INSERT INTO @Results (ResultNo, ResultName) VALUES (1, 'ReturnStatus'), (2, 'ResultList'), (3, 'SMSData');
            SELECT * FROM @Results;

            SELECT ob.ID AS SMSID,
                   ob.SenderType,
                   ob.SenderName,
                   ob.PhoneNo AS RecipientPhone,
                   ob.Message AS MessageContent
            FROM [EJ].[tblSMSOutbox] ob
            WHERE ob.id = @ID;

             UPDATE ob
             SET ob.StatusID = 1
             FROM [EJ].[tblSMSOutbox] ob
             WHERE ob.id = @ID;
          END
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE [EJ].[spUpdateSMSOutboxStatus]
    @ID INT,
    @ProviderID VARCHAR(50),
    @StatusID SMALLINT
 AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);
    BEGIN TRY
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
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END
GO

CREATE OR ALTER PROCEDURE [EJ].[spUpdateSMSOutboxProviderStatus]
    @ProviderID VARCHAR(50),
    @ProviderStatusID SMALLINT,
    @DeliveredAt DATETIMEOFFSET(7) = NULL,
    @BufferedAt DATETIMEOFFSET(7) = NULL
 AS
 BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX);
    BEGIN TRY
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
            SET @ReturnDescription = 'Nincs ilyen request (ProviderID)!';
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

CREATE OR ALTER FUNCTION [EJ].[fnCleanPhoneNumber]
(
    @PhoneNumber NVARCHAR(50)
)
RETURNS NVARCHAR(50)
AS
BEGIN
    DECLARE @Cleaned NVARCHAR(50);
    SET @Cleaned = REPLACE(@PhoneNumber, ' ', '');
    IF LEFT(@Cleaned, 1) = '+'
    BEGIN
        SET @Cleaned = STUFF(@Cleaned, 1, 1, '');
    END
    RETURN @Cleaned;
END
GO
