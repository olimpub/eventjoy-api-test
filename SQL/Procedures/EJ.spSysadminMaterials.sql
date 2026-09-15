SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminCreateMaterial]
    @FileName NVARCHAR(255),
    @BlobUrl NVARCHAR(1000),
    @ContentType NVARCHAR(100),
    @SizeInBytes BIGINT,
    @UploadedByUserID INT,
    @EventID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO [EJ].[tblMaterial] (FileName, BlobUrl, ContentType, SizeInBytes, UploadedByUserID, EventID)
    VALUES (@FileName, @BlobUrl, @ContentType, @SizeInBytes, @UploadedByUserID, @EventID);
    
    SELECT SCOPE_IDENTITY() AS MaterialID;
END
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetMaterials]
    @EventID INT = NULL,
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT m.*, LTRIM(RTRIM(ISNULL(u.LastName, '') + ' ' + ISNULL(u.FirstName, ''))) AS UploadedByName
    FROM [EJ].[tblMaterial] m
    LEFT JOIN [EJ].[tblUser] u ON m.UploadedByUserID = u.Id
    WHERE (@EventID IS NULL OR m.EventID = @EventID)
    ORDER BY m.CreatedAt DESC
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) 
    FROM [EJ].[tblMaterial] 
    WHERE (@EventID IS NULL OR EventID = @EventID);
END
GO
