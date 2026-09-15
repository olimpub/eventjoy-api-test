SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblMaterial]') AND type in (N'U'))
BEGIN
CREATE TABLE [EJ].[tblMaterial] (
    MaterialID INT IDENTITY(1,1) PRIMARY KEY,
    FileName NVARCHAR(255) NOT NULL,
    BlobUrl NVARCHAR(1000) NOT NULL,
    ContentType NVARCHAR(100) NOT NULL,
    SizeInBytes BIGINT NOT NULL,
    UploadedByUserID INT NOT NULL,
    EventID INT NULL,
    CreatedAt DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET()
);

ALTER TABLE [EJ].[tblMaterial]  WITH CHECK ADD  CONSTRAINT [FK_tblMaterial_tblUser] FOREIGN KEY([UploadedByUserID])
REFERENCES [EJ].[tblUser] ([id]);

ALTER TABLE [EJ].[tblMaterial] CHECK CONSTRAINT [FK_tblMaterial_tblUser];
END
GO
