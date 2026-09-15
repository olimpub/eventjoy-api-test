SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblMaterialType]') AND type in (N'U'))
BEGIN
    CREATE TABLE [EJ].[tblMaterialType] (
        MaterialTypeID INT IDENTITY(1,1) PRIMARY KEY,
        Name NVARCHAR(255) NOT NULL,
        Code NVARCHAR(50) NOT NULL UNIQUE
    );
    INSERT INTO [EJ].[tblMaterialType] (Name, Code) VALUES 
        ('Játékszabályzat', 'RULES'), 
        ('Részvételi feltételek', 'TERMS'), 
        ('Galéria kép', 'GALLERY'), 
        ('Térkép', 'MAP'), 
        ('Egyéb dokumentum', 'OTHER');
END
GO

IF COL_LENGTH('[EJ].[tblEventMaterial]', 'MaterialRole') IS NOT NULL
BEGIN
    ALTER TABLE [EJ].[tblEventMaterial] DROP COLUMN MaterialRole;
END

IF COL_LENGTH('[EJ].[tblEventMaterial]', 'MaterialTypeID') IS NULL
BEGIN
    ALTER TABLE [EJ].[tblEventMaterial] ADD MaterialTypeID INT NOT NULL DEFAULT 5;
    ALTER TABLE [EJ].[tblEventMaterial] ADD CONSTRAINT [FK_tblEventMaterial_MaterialType] FOREIGN KEY ([MaterialTypeID]) REFERENCES [EJ].[tblMaterialType] ([MaterialTypeID]);
END
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblEventMaterialRole]') AND type in (N'U'))
BEGIN
    CREATE TABLE [EJ].[tblEventMaterialRole] (
        EventMaterialRoleID INT IDENTITY(1,1) PRIMARY KEY,
        EventMaterialID INT NOT NULL,
        EventRoleID BIGINT NOT NULL,
        
        CONSTRAINT [FK_tblEventMaterialRole_EventMaterial] FOREIGN KEY ([EventMaterialID]) REFERENCES [EJ].[tblEventMaterial] ([EventMaterialID]),
        CONSTRAINT [FK_tblEventMaterialRole_EventRole] FOREIGN KEY ([EventRoleID]) REFERENCES [EJ].[tblEventRole] ([id])
    );
END
GO
