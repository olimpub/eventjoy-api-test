CREATE OR ALTER PROCEDURE [OP].[spGetPendingBonusProofs]
    @UserID BIGINT,
    @EventID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- Verify user is organizer (RoleTypeID = 1 or 2)
    IF NOT EXISTS (
        SELECT 1 
        FROM EJ.tblEventUser eu
        JOIN EJ.tblEventRole er ON eu.EventRoleID = er.id
        JOIN EJ.tblRole r ON er.RoleID = r.id
        WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND r.RoleTypeID IN (1, 2)
    )
    BEGIN
        SELECT -1 AS ReturnValue, N'Nincs megfelelő jogosultságod.' AS ReturnDescription;
        RETURN;
    END

    SELECT 1 AS ReturnValue, N'Sikeres' AS ReturnDescription;

    SELECT 
        bp.id AS ProofID,
        bp.EventUserID,
        p.NickName AS PlayerName,
        bp.Platform,
        bp.MediaUrl,
        bp.createdAt
    FROM [OP].[tblBonusProof] bp
    JOIN [PTA].[tblEventPlayer] p ON bp.EventUserID = p.EventUserID AND p.EventID = @EventID
    WHERE bp.EventID = @EventID AND bp.StatusID = 0
    ORDER BY bp.createdAt ASC;
END
GO
