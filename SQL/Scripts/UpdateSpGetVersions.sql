SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetVersions]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'

    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription

    SELECT 
        V.id AS VersionID, 
        V.VersionNumber, 
        V.ReleaseDate, 
        V.Summary, 
        V.ActiveFlg, 
        V.LastUpdatedUserID, 
        V.createdAt, 
        V.updatedAt,
        (
            SELECT 
                VI.id AS ItemID,
                VI.TicketID,
                VI.InternalReference,
                VI.ExternalReference,
                VI.Description,
                VI.ActiveFlg
            FROM [EJ].[tblAppVersionItem] VI
            WHERE VI.VersionID = V.id
            FOR JSON PATH
        ) AS Items_JSON
    FROM [EJ].[tblAppVersion] V
    ORDER BY V.ReleaseDate DESC;
END
GO
