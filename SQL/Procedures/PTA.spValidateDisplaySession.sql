CREATE OR ALTER PROCEDURE [PTA].[spValidateDisplaySession]
    @EventID INT = NULL,
    @EventUID UNIQUEIDENTIFIER = NULL,
    @Pin CHAR(4),
    @Module NVARCHAR(16) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ActualEventID INT = @EventID;

    IF @ActualEventID IS NULL AND @EventUID IS NOT NULL
    BEGIN
        SELECT @ActualEventID = id FROM [EJ].[tblEvent] WHERE EventUID = @EventUID AND ActiveFlg = 1;
    END

    IF @ActualEventID IS NULL
    BEGIN
        SELECT -1 AS ReturnValue, N'Érvénytelen vagy lejárt PIN.' AS ReturnDescription;
        RETURN;
    END

    DECLARE @Now DATETIMEOFFSET = SYSUTCDATETIME();
    DECLARE @NowUtc DATETIME2 = SYSUTCDATETIME();
    DECLARE @MasterToken NVARCHAR(80);
    DECLARE @ExpiresAtUtc DATETIMEOFFSET;
    DECLARE @FoundModule NVARCHAR(16);

    IF @Module IS NOT NULL AND LTRIM(RTRIM(@Module)) != ''
    BEGIN
        SET @Module = LOWER(LTRIM(RTRIM(@Module)));
    END
    ELSE
    BEGIN
        SET @Module = NULL;
    END

    SELECT TOP 1
        @MasterToken = Token,
        @ExpiresAtUtc = ExpiresAtUtc,
        @FoundModule = Module
    FROM [PTA].[tblEventDisplayToken]
    WHERE EventID = @ActualEventID
      AND Pin = @Pin
      AND ActiveFlg = 1
      AND ExpiresAtUtc > @Now
      AND (@Module IS NULL OR Module = @Module)
    ORDER BY id DESC;

    -- Fallback: ha a token másik modullal lett létrehozva ugyanarra az eseményre és PIN-re
    IF @MasterToken IS NULL
    BEGIN
        SELECT TOP 1
            @MasterToken = Token,
            @ExpiresAtUtc = ExpiresAtUtc,
            @FoundModule = Module
        FROM [PTA].[tblEventDisplayToken]
        WHERE EventID = @ActualEventID
          AND Pin = @Pin
          AND ActiveFlg = 1
          AND ExpiresAtUtc > @Now
        ORDER BY id DESC;
    END

    IF @MasterToken IS NULL
    BEGIN
        SELECT -1 AS ReturnValue, N'Érvénytelen vagy lejárt PIN.' AS ReturnDescription;
        RETURN;
    END

    DECLARE @ResolvedModule NVARCHAR(16) = ISNULL(@FoundModule, ISNULL(@Module, 'pta'));
    DECLARE @SessionToken NVARCHAR(80) = LOWER(REPLACE(NEWID(), '-', '')) + LOWER(REPLACE(NEWID(), '-', ''));

    INSERT INTO [PTA].[tblEventDisplayToken] (EventID, Module, Pin, Token, ExpiresAtUtc, ActiveFlg, TokenActiveFlg, ConnectedAtUtc, LastSeenUtc)
    VALUES (@ActualEventID, @ResolvedModule, @Pin, @SessionToken, @ExpiresAtUtc, 1, 1, @NowUtc, @NowUtc);

    DECLARE @DisplayID INT = SCOPE_IDENTITY();

    UPDATE [PTA].[tblEventDisplayToken]
    SET Label = N'Kijelző ' + CAST(@DisplayID AS NVARCHAR(20))
    WHERE id = @DisplayID AND Label IS NULL;

    SELECT 1 AS ReturnValue, N'OK' AS ReturnDescription, @DisplayID AS DisplayID, @ActualEventID AS EventID, @ResolvedModule AS Module, @SessionToken AS Token, @ExpiresAtUtc AS ExpiresAtUtc;
END
GO
