SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [EJ].[spGetAppVersions]
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
        (
            SELECT 
                VI.id AS ItemID,
                VI.Description,
                VI.ExternalReference
            FROM [EJ].[tblAppVersionItem] VI
            WHERE VI.VersionID = V.id AND VI.ActiveFlg = 1
            ORDER BY VI.id ASC
            FOR JSON PATH
        ) AS Items_JSON
    FROM [EJ].[tblAppVersion] V
    WHERE V.ActiveFlg = 1
    ORDER BY V.ReleaseDate DESC, V.id DESC;
END
GO
