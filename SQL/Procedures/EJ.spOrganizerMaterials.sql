SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spOrganizerCreateEventMaterial]
    @EventID BIGINT,
    @UserID BIGINT,
    @FileName NVARCHAR(255),
    @BlobUrl NVARCHAR(1000),
    @ContentType NVARCHAR(100),
    @SizeInBytes BIGINT,
    @PublicName NVARCHAR(255),
    @MaterialTypeID INT,
    @EventRoleIDsJSON NVARCHAR(MAX) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    -- 1. JogosultsĂˇg ellenĹ‘rzĂ©s (SzervezĹ‘ / Owner)
    -- FeltĂ©telezzĂĽk, hogy a RoleID = 1 a SzervezĹ‘
    IF NOT EXISTS (
        SELECT 1 
        FROM [EJ].[tblEventUser] eu 
        INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id 
        WHERE eu.UserID = @UserID AND er.EventID = @EventID AND er.RoleID = 1 AND eu.ActiveFlg = 1
    )
    BEGIN
        SELECT -1 AS ReturnValue, N'Unauthorized: Nem szervezĹ‘je az esemĂ©nynek.' AS ReturnDescription, NULL AS EventMaterialID, NULL AS MaterialID;
        RETURN;
    END

    IF @PublicName IS NULL OR LTRIM(RTRIM(@PublicName)) = ''
        SET @PublicName = @FileName;

    DECLARE @NewMaterialID INT;
    DECLARE @NewEventMaterialID INT;

    BEGIN TRY
        BEGIN TRANSACTION;

        -- 2. Material beszĂşrĂˇsa
        INSERT INTO [EJ].[tblMaterial] (FileName, BlobUrl, ContentType, SizeInBytes, UploadedByUserID)
        VALUES (@FileName, @BlobUrl, @ContentType, @SizeInBytes, @UserID);
        
        SET @NewMaterialID = SCOPE_IDENTITY();

        -- 3. JĂˇtĂ©kszabĂˇlyzat Ă©s RĂ©szvĂ©teli feltĂ©telek inaktivĂˇlĂˇsa (Ha 1 = RULES, 2 = TERMS)
        IF @MaterialTypeID IN (1, 2)
        BEGIN
            UPDATE [EJ].[tblEventMaterial]
            SET IsActive = 0
            WHERE EventID = @EventID AND MaterialTypeID = @MaterialTypeID AND IsActive = 1;
        END

        -- 4. EventMaterial beszĂşrĂˇsa
        INSERT INTO [EJ].[tblEventMaterial] (EventID, MaterialID, PublicName, MaterialTypeID, IsActive, CreatedByUserID)
        VALUES (@EventID, @NewMaterialID, @PublicName, @MaterialTypeID, 1, @UserID);
        
        SET @NewEventMaterialID = SCOPE_IDENTITY();

        -- 5. EventRole-ok beszĂşrĂˇsa
        IF @EventRoleIDsJSON IS NOT NULL AND @EventRoleIDsJSON <> '[]'
        BEGIN
            INSERT INTO [EJ].[tblEventMaterialRole] (EventMaterialID, EventRoleID)
            SELECT @NewEventMaterialID, CAST(value AS BIGINT)
            FROM OPENJSON(@EventRoleIDsJSON);
        END

        COMMIT TRANSACTION;
        SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @NewEventMaterialID AS EventMaterialID, @NewMaterialID AS MaterialID;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription, NULL AS EventMaterialID, NULL AS MaterialID;
    END CATCH
END
GO
CREATE OR ALTER PROCEDURE [EJ].[spOrganizerGetEventMaterials]
    @EventID BIGINT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    -- JogosultsĂˇg ellenĹ‘rzĂ©s
    IF NOT EXISTS (
        SELECT 1 
        FROM [EJ].[tblEventUser] eu 
        INNER JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id 
        WHERE eu.UserID = @UserID AND er.EventID = @EventID AND er.RoleID = 1 AND eu.ActiveFlg = 1
    )
    BEGIN
        SELECT -1 AS ReturnValue, N'Unauthorized: Nem szervezĹ‘je az esemĂ©nynek.' AS ReturnDescription;
        RETURN;
    END
    
    SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription;

    SELECT 
        em.EventMaterialID,
        em.MaterialID,
        em.PublicName,
        m.FileName,
        m.ContentType,
        m.SizeInBytes,
        em.MaterialTypeID,
        t.Name AS MaterialTypeName,
        t.Code AS MaterialTypeCode,
        em.IsActive,
        m.BlobUrl,
        em.CreatedAt
    FROM [EJ].[tblEventMaterial] em
    INNER JOIN [EJ].[tblMaterialType] t ON em.MaterialTypeID = t.MaterialTypeID
    INNER JOIN [EJ].[tblMaterial] m ON em.MaterialID = m.MaterialID
    WHERE em.EventID = @EventID
    ORDER BY em.CreatedAt DESC;

    SELECT 
        emr.EventMaterialID,
        emr.EventRoleID,
        r.RoleName
    FROM [EJ].[tblEventMaterialRole] emr
    INNER JOIN [EJ].[tblEventMaterial] em ON emr.EventMaterialID = em.EventMaterialID
    INNER JOIN [EJ].[tblEventRole] er ON emr.EventRoleID = er.id
    INNER JOIN [EJ].[tblRole] r ON er.RoleID = r.id
    WHERE em.EventID = @EventID;
END
GO
