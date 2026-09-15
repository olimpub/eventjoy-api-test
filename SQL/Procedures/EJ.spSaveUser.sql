SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE OR ALTER PROCEDURE [EJ].[spSaveUser]
    @UserID BIGINT,
    @FirstName NVARCHAR(150),
    @LastName NVARCHAR(150)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        UPDATE [EJ].[tblUser]
        SET 
            FirstName = CASE WHEN FirstName IS NULL OR TRIM(FirstName) = '' THEN @FirstName ELSE FirstName END,
            LastName = CASE WHEN LastName IS NULL OR TRIM(LastName) = '' THEN @LastName ELSE LastName END,
            LastUpdatedUserID = @UserID,
            updatedAt = SYSDATETIMEOFFSET()
        WHERE id = @UserID;
        
        SELECT 1 AS ReturnValue, N'Sikeres mentés.' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO
