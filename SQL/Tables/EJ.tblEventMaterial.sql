SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- 1. Eltávolítjuk az EventID-t a Material táblából (mivel repository lesz)
IF COL_LENGTH('[EJ].[tblMaterial]', 'EventID') IS NOT NULL
BEGIN
    ALTER TABLE [EJ].[tblMaterial] DROP COLUMN EventID;
END
GO

-- 2. Létrehozzuk a tblEventMaterial kapcsolótáblát
IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblEventMaterial]') AND type in (N'U'))
BEGIN
    CREATE TABLE [EJ].[tblEventMaterial] (
        EventMaterialID INT IDENTITY(1,1) PRIMARY KEY,
        EventID BIGINT NOT NULL,
        MaterialID INT NOT NULL,
        PublicName NVARCHAR(255) NOT NULL,
        MaterialRole NVARCHAR(50) NOT NULL DEFAULT 'OTHER', -- Pl: 'RULES', 'TERMS', 'GALLERY', 'MAP'
        IsActive BIT NOT NULL DEFAULT 1, -- Verziózáshoz: az új aktív lesz, a régi inaktív
        CreatedAt DATETIME2 NOT NULL DEFAULT SYSDATETIMEOFFSET(),
        CreatedByUserID BIGINT NOT NULL,
        
        CONSTRAINT [FK_tblEventMaterial_Event] FOREIGN KEY([EventID]) REFERENCES [EJ].[tblEvent] ([id]),
        CONSTRAINT [FK_tblEventMaterial_Material] FOREIGN KEY([MaterialID]) REFERENCES [EJ].[tblMaterial] ([MaterialID])
    );
END
GO
