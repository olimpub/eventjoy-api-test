CREATE OR ALTER PROCEDURE [OP].[spUploadBonusProof]
    @UserID BIGINT,
    @EventID BIGINT,
    @EventUserID BIGINT,
    @Platform NVARCHAR(50),
    @MediaUrl NVARCHAR(500)
AS
BEGIN
    SET NOCOUNT ON;

    -- Verify user belongs to the event
    IF NOT EXISTS (SELECT 1 FROM EJ.tblEventUser WHERE EventID = @EventID AND UserID = @UserID AND id = @EventUserID)
    BEGIN
        SELECT -1 AS ReturnValue, N'Nincs jogosultságod feltölteni ehhez a játékoshoz.' AS ReturnDescription;
        RETURN;
    END

    -- Insert proof
    INSERT INTO [OP].[tblBonusProof] (EventID, EventUserID, Platform, MediaUrl, StatusID, createdAt, updatedAt)
    VALUES (@EventID, @EventUserID, @Platform, @MediaUrl, 0, SYSDATETIMEOFFSET(), SYSDATETIMEOFFSET());

    SELECT 1 AS ReturnValue, N'Sikeres feltöltés' AS ReturnDescription;
END
GO
