SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF COL_LENGTH('[EJ].[tblMaterialType]', 'SortOrder') IS NULL
BEGIN
    ALTER TABLE [EJ].[tblMaterialType] ADD SortOrder INT NOT NULL DEFAULT 0;
END
GO
UPDATE [EJ].[tblMaterialType] SET SortOrder = MaterialTypeID;
GO
