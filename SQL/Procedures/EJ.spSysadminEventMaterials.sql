SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminLinkMaterialToEvent]
    @EventID BIGINT,
    @MaterialID INT,
    @PublicName NVARCHAR(255),
    @MaterialRole NVARCHAR(50),
    @CreatedByUserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- Verziózás: ha ez pl. a RULES (Játékszabályzat), akkor a korábbiakat inaktívvá tesszük
    IF @MaterialRole IN ('RULES', 'TERMS')
    BEGIN
        UPDATE [EJ].[tblEventMaterial]
        SET IsActive = 0
        WHERE EventID = @EventID AND MaterialRole = @MaterialRole AND IsActive = 1;
    END

    INSERT INTO [EJ].[tblEventMaterial] (EventID, MaterialID, PublicName, MaterialRole, IsActive, CreatedByUserID)
    VALUES (@EventID, @MaterialID, @PublicName, @MaterialRole, 1, @CreatedByUserID);
    
    SELECT SCOPE_IDENTITY() AS EventMaterialID;
END
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetEventMaterials]
    @EventID BIGINT,
    @IncludeInactive BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        em.EventMaterialID,
        em.EventID,
        em.MaterialID,
        em.PublicName,
        em.MaterialRole,
        em.IsActive,
        em.CreatedAt AS LinkedAt,
        m.FileName,
        m.BlobUrl,
        m.ContentType,
        m.SizeInBytes,
        LTRIM(RTRIM(ISNULL(u.LastName, '') + ' ' + ISNULL(u.FirstName, ''))) AS UploadedByName
    FROM [EJ].[tblEventMaterial] em
    INNER JOIN [EJ].[tblMaterial] m ON em.MaterialID = m.MaterialID
    LEFT JOIN [EJ].[tblUser] u ON em.CreatedByUserID = u.Id
    WHERE em.EventID = @EventID
      AND (@IncludeInactive = 1 OR em.IsActive = 1)
    ORDER BY em.MaterialRole, em.CreatedAt DESC;
END
GO
