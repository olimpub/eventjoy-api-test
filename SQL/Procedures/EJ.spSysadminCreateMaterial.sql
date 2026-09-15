SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminCreateMaterial]
    @FileName NVARCHAR(255),
    @BlobUrl NVARCHAR(1000),
    @ContentType NVARCHAR(100),
    @SizeInBytes BIGINT,
    @UploadedByUserID INT
AS
BEGIN
    SET NOCOUNT ON;
    
    INSERT INTO [EJ].[tblMaterial] (FileName, BlobUrl, ContentType, SizeInBytes, UploadedByUserID)
    VALUES (@FileName, @BlobUrl, @ContentType, @SizeInBytes, @UploadedByUserID);
    
    SELECT SCOPE_IDENTITY() AS MaterialID;
END
GO
