SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [EJ].[spSysadminUpsertVersion]
    @VersionID INT = NULL,
    @VersionNumber NVARCHAR(50),
    @ReleaseDate DATETIME,
    @Summary NVARCHAR(MAX),
    @ActiveFlg BIT,
    @ItemsJSON NVARCHAR(MAX), -- JSON tĂ¶mb az itemekrĹ‘l
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX)

    BEGIN TRY
        BEGIN TRANSACTION;

        IF (@VersionID IS NULL OR @VersionID = 0)
        BEGIN
            INSERT INTO [EJ].[tblAppVersion] (VersionNumber, ReleaseDate, Summary, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@VersionNumber, @ReleaseDate, @Summary, @ActiveFlg, @UserID, GETUTCDATE(), GETUTCDATE());
            
            SET @VersionID = SCOPE_IDENTITY();
        END
        ELSE
        BEGIN
            UPDATE [EJ].[tblAppVersion]
            SET 
                VersionNumber = @VersionNumber,
                ReleaseDate = @ReleaseDate,
                Summary = @Summary,
                ActiveFlg = @ActiveFlg,
                LastUpdatedUserID = @UserID,
                updatedAt = GETUTCDATE()
            WHERE id = @VersionID;
        END

        -- Elemek szinkronizĂˇlĂˇsa (Ha az ItemsJSON nem NULL)
        IF (@ItemsJSON IS NOT NULL)
        BEGIN
            -- ElĹ‘szĂ¶r InaktivĂˇljuk az Ă¶sszes eddigi itemet (hogy leteszteljĂĽk a tĂ¶rlĂ©st)
            UPDATE [EJ].[tblAppVersionItem] SET ActiveFlg = 0 WHERE VersionID = @VersionID;

            -- OPENJSON-al frissĂ­tjĂĽk/beszĂşrjuk
            MERGE INTO [EJ].[tblAppVersionItem] AS Target
            USING (
                SELECT 
                    JSON_VALUE(value, '$.ItemID') AS ItemID,
                    JSON_VALUE(value, '$.TicketID') AS TicketID,
                    JSON_VALUE(value, '$.InternalReference') AS InternalReference,
                    JSON_VALUE(value, '$.ExternalReference') AS ExternalReference,
                    JSON_VALUE(value, '$.Description') AS Description,
                    ISNULL(JSON_VALUE(value, '$.ActiveFlg'), 1) AS ActiveFlg
                FROM OPENJSON(@ItemsJSON)
            ) AS Source
            ON Target.id = Source.ItemID AND Target.VersionID = @VersionID
            WHEN MATCHED THEN
                UPDATE SET 
                    Target.TicketID = Source.TicketID,
                    Target.InternalReference = Source.InternalReference,
                    Target.ExternalReference = Source.ExternalReference,
                    Target.Description = Source.Description,
                    Target.ActiveFlg = Source.ActiveFlg,
                    Target.updatedAt = GETUTCDATE()
            WHEN NOT MATCHED BY TARGET THEN
                INSERT (VersionID, TicketID, InternalReference, ExternalReference, Description, ActiveFlg, createdAt, updatedAt)
                VALUES (@VersionID, Source.TicketID, Source.InternalReference, Source.ExternalReference, Source.Description, Source.ActiveFlg, GETUTCDATE(), GETUTCDATE());
        END

        COMMIT TRANSACTION;
        SET @ReturnValue = 1;
        SET @ReturnDescription = 'Success';
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
    END CATCH

    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
END
GO
