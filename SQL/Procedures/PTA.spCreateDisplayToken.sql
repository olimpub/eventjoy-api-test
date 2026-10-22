CREATE OR ALTER PROCEDURE [PTA].[spCreateDisplayToken]
    @EventID INT,
    @UserID BIGINT,
    @Module NVARCHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @IsPTA BIT = 0;
    DECLARE @IsOP BIT = 0;

    SELECT
        @IsPTA = ISNULL(et.PTAFlg, 0),
        @IsOP = ISNULL(et.OPFlg, 0)
    FROM [EJ].[tblEvent] e
    JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id
    WHERE e.id = @EventID;

    IF @IsPTA = 0 AND @IsOP = 0
    BEGIN
        SELECT -1 AS ReturnValue, N'Nem PTA vagy Olimpub esemény.' AS ReturnDescription;
        RETURN;
    END

    IF @Module IS NULL OR LTRIM(RTRIM(@Module)) = ''
    BEGIN
        SET @Module = CASE WHEN @IsOP = 1 THEN 'op' ELSE 'pta' END;
    END
    ELSE
    BEGIN
        SET @Module = LOWER(LTRIM(RTRIM(@Module)));
    END

    -- Check if User is Organizer (RoleTypeID = 1), Contributor (RoleTypeID = 2), or QM (r.id = 7)
    IF NOT EXISTS (
        SELECT 1 FROM [EJ].[tblEventUser] eu
        JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id
        JOIN [EJ].[tblRole] r ON er.RoleID = r.id
        WHERE eu.EventID = @EventID AND eu.UserID = @UserID AND eu.ActiveFlg = 1 AND (r.RoleTypeID IN (1, 2) OR r.id = 7)
    )
    BEGIN
        SELECT -1 AS ReturnValue, N'Nincs jogosultságod.' AS ReturnDescription;
        RETURN;
    END

    DECLARE @Pin CHAR(4);
    DECLARE @Token NVARCHAR(80) = LOWER(REPLACE(NEWID(), '-', '')) + LOWER(REPLACE(NEWID(), '-', ''));

    DECLARE @Retry INT = 0;
    WHILE @Retry < 100
    BEGIN
        SET @Pin = CAST(CAST(ABS(CHECKSUM(NEWID())) % 8999 + 1000 AS INT) AS CHAR(4));

        IF NOT EXISTS (SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE EventID = @EventID AND Pin = @Pin AND ActiveFlg = 1)
            BREAK;

        SET @Retry = @Retry + 1;
    END

    UPDATE [PTA].[tblEventDisplayToken]
    SET ActiveFlg = 0
    WHERE EventID = @EventID AND Module = @Module AND ActiveFlg = 1;

    DECLARE @EndAtUtc DATETIMEOFFSET;
    SELECT @EndAtUtc = EndAtUtc FROM [EJ].[tblEvent] WHERE id = @EventID;

    DECLARE @Now DATETIMEOFFSET = SYSUTCDATETIME();
    DECLARE @ExpiresAtUtc DATETIMEOFFSET = DATEADD(hour, 12, @Now);

    IF @EndAtUtc IS NOT NULL AND DATEADD(hour, 4, @EndAtUtc) > @ExpiresAtUtc
    BEGIN
        SET @ExpiresAtUtc = DATEADD(hour, 4, @EndAtUtc);
    END

    INSERT INTO [PTA].[tblEventDisplayToken] (EventID, Module, Pin, Token, ExpiresAtUtc)
    VALUES (@EventID, @Module, @Pin, @Token, @ExpiresAtUtc);

    SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @EventID AS EventID, @Module AS Module, @Pin AS Pin, @Token AS Token, @ExpiresAtUtc AS ExpiresAtUtc;
END
GO
