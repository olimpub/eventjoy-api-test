SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSaveEventContent]
    @Json NVARCHAR(MAX),
    @UserID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);
    BEGIN TRY
        BEGIN TRANSACTION;

        DECLARE @EventID BIGINT = JSON_VALUE(@Json, '$.EventID');
        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();

        IF @EventID IS NULL
        BEGIN
            THROW 50000, N'EventID is required', 1;
        END

        SELECT 
            id,
            ProgramDateTime,
            ProgramName
        INTO #IncomingPrograms
        FROM OPENJSON(@Json, '$.Programs')
        WITH (
            id BIGINT '$.id',
            ProgramDateTime DATETIMEOFFSET(7) '$.ProgramDateTime',
            ProgramName NVARCHAR(255) '$.ProgramName'
        );

        UPDATE [EJ].[tblEventProgram]
        SET ActiveFlg = 0, LastUpdatedUserID = @UserID, updatedAt = @Now
        WHERE EventID = @EventID 
          AND id NOT IN (SELECT id FROM #IncomingPrograms WHERE id IS NOT NULL);

        MERGE INTO [EJ].[tblEventProgram] AS target
        USING #IncomingPrograms AS source
        ON target.id = source.id AND target.EventID = @EventID
        WHEN MATCHED THEN 
            UPDATE SET 
                ProgramDateTime = source.ProgramDateTime,
                ProgramName = source.ProgramName,
                ActiveFlg = 1,
                LastUpdatedUserID = @UserID,
                updatedAt = @Now
        WHEN NOT MATCHED THEN 
            INSERT (EventID, ProgramDateTime, ProgramName, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@EventID, source.ProgramDateTime, source.ProgramName, 1, @UserID, @Now, @Now);

        COMMIT TRANSACTION;
        SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventID;
    END CATCH
END
GO

