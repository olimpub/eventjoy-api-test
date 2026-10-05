CREATE OR ALTER PROCEDURE [OP].[spReviewBonusProof]
    @UserID BIGINT,
    @EventID BIGINT,
    @ProofID BIGINT,
    @Approved BIT
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

    DECLARE @StatusID SMALLINT = CASE WHEN @Approved = 1 THEN 1 ELSE 2 END;
    DECLARE @EventUserID BIGINT;
    DECLARE @Platform NVARCHAR(50);
    
    SELECT 
        @EventUserID = EventUserID,
        @Platform = Platform
    FROM [OP].[tblBonusProof] 
    WHERE id = @ProofID AND EventID = @EventID AND StatusID = 0;

    IF @EventUserID IS NULL
    BEGIN
        SELECT -1 AS ReturnValue, N'A bizonyíték nem található vagy már elbírálták.' AS ReturnDescription;
        RETURN;
    END

    UPDATE [OP].[tblBonusProof]
    SET 
        StatusID = @StatusID,
        ReviewerUserID = @UserID,
        ReviewDate = SYSDATETIMEOFFSET(),
        updatedAt = SYSDATETIMEOFFSET()
    WHERE id = @ProofID;

    -- If approved, grant points directly via AdjustTeam logic
    IF @Approved = 1
    BEGIN
        DECLARE @PenaltyTypeID INT;
        SELECT @PenaltyTypeID = id FROM OP.tblPenaltyType WHERE Code = 'social_bonus';

        -- Get player TeamID (if they have one) or default to NULL
        DECLARE @TeamID INT;
        SELECT TOP 1 @TeamID = TeamID 
        FROM [OP].[tblEventUserTeam] 
        WHERE EventUserID = @EventUserID AND EventID = @EventID AND ActiveFlg = 1;

        -- Add 5 points for Social Bonus
        INSERT INTO [OP].[tblPenalty] (EventID, TeamID, Points, PenaltyTypeID, EventUserID, CreatedAtUtc, LastCreatedUserID, ActiveFlg, UpdatedAtUtc)
        VALUES (
            @EventID, 
            @TeamID, 
            5, -- 5 Points
            @PenaltyTypeID,
            @EventUserID,
            GETUTCDATE(),
            @UserID,
            1,
            GETUTCDATE()
        );
    END

    SELECT 1 AS ReturnValue, N'Sikeres elbírálás' AS ReturnDescription;
END
GO
