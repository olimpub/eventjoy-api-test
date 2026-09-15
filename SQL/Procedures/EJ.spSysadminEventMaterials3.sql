SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
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
        em.MaterialTypeID,
        t.Name AS MaterialTypeName,
        t.Code AS MaterialTypeCode,
        em.IsActive,
        em.CreatedAt AS LinkedAt,
        m.FileName,
        m.BlobUrl,
        m.ContentType,
        m.SizeInBytes,
        LTRIM(RTRIM(ISNULL(u.LastName, '') + ' ' + ISNULL(u.FirstName, ''))) AS UploadedByName
    FROM [EJ].[tblEventMaterial] em
    INNER JOIN [EJ].[tblMaterialType] t ON em.MaterialTypeID = t.MaterialTypeID
    INNER JOIN [EJ].[tblMaterial] m ON em.MaterialID = m.MaterialID
    LEFT JOIN [EJ].[tblUser] u ON em.CreatedByUserID = u.Id
    WHERE em.EventID = @EventID
      AND (@IncludeInactive = 1 OR em.IsActive = 1)
    ORDER BY t.MaterialTypeID, em.CreatedAt DESC;

    -- Visszaadjuk a hozzájuk tartozó EventRole-okat is egy második resultsetben
    SELECT 
        emr.EventMaterialID,
        emr.EventRoleID,
        r.RoleName -- Javítva RoleName-re
    FROM [EJ].[tblEventMaterialRole] emr
    INNER JOIN [EJ].[tblEventMaterial] em ON emr.EventMaterialID = em.EventMaterialID
    INNER JOIN [EJ].[tblEventRole] er ON emr.EventRoleID = er.id
    INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
    WHERE em.EventID = @EventID
      AND (@IncludeInactive = 1 OR em.IsActive = 1);
END
GO
