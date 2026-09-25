SET QUOTED_IDENTIFIER ON;
GO
-- 1. Create OP.tblMedia
IF NOT EXISTS (SELECT 1 FROM sys.tables WHERE object_id = OBJECT_ID('[OP].[tblMedia]'))
BEGIN
    CREATE TABLE [OP].[tblMedia] (
        [id] INT IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
        [EventID] BIGINT NOT NULL,
        [MediaKey] NVARCHAR(200) NOT NULL,
        [Kind] NVARCHAR(20) NOT NULL,
        [BlobUrl] NVARCHAR(1000) NOT NULL,
        [ContentHash] NVARCHAR(64) NOT NULL,
        [Mime] NVARCHAR(100) NOT NULL,
        [SizeInBytes] BIGINT NOT NULL,
        [FileName] NVARCHAR(255) NOT NULL,
        [ActiveFlg] BIT NOT NULL DEFAULT 1,
        [CreatedAtUtc] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        [UpdatedAtUtc] DATETIMEOFFSET NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        [LastCreatedUserID] INT NULL
    );

    CREATE UNIQUE NONCLUSTERED INDEX [IX_tblMedia_EventID_MediaKey] ON [OP].[tblMedia] ([EventID], [MediaKey]) WHERE [ActiveFlg] = 1;
END
GO

CREATE OR ALTER TRIGGER [OP].[trg_Media_Update]
ON [OP].[tblMedia] AFTER UPDATE AS
BEGIN
    SET NOCOUNT ON;
    IF NOT UPDATE(UpdatedAtUtc)
        UPDATE t SET UpdatedAtUtc = SYSDATETIMEOFFSET() FROM [OP].[tblMedia] t INNER JOIN inserted i ON t.id = i.id;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblQuestion]') AND name = 'ImageKey')
BEGIN
    ALTER TABLE [OP].[tblQuestion] ADD [ImageKey] NVARCHAR(200) NULL;
END
GO

IF NOT EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('[OP].[tblQuestion]') AND name = 'AudioKey')
BEGIN
    ALTER TABLE [OP].[tblQuestion] ADD [AudioKey] NVARCHAR(200) NULL;
END
GO
