SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblAppVersion]') AND type in (N'U'))
    BEGIN
        CREATE TABLE [EJ].[tblAppVersion](
            [id] [int] IDENTITY(1,1) NOT NULL,
            [VersionNumber] [nvarchar](50) NOT NULL,
            [ReleaseDate] [datetime] NOT NULL,
            [TicketReference] [nvarchar](100) NULL,
            [Description] [nvarchar](max) NOT NULL,
            [ActiveFlg] [bit] NOT NULL CONSTRAINT [DF_tblAppVersion_ActiveFlg]  DEFAULT ((1)),
            [LastUpdatedUserID] [bigint] NULL,
            [createdAt] [datetime] NOT NULL CONSTRAINT [DF_tblAppVersion_createdAt]  DEFAULT (getutcdate()),
            [updatedAt] [datetime] NOT NULL CONSTRAINT [DF_tblAppVersion_updatedAt]  DEFAULT (getutcdate()),
         CONSTRAINT [PK_tblAppVersion] PRIMARY KEY CLUSTERED 
        (
            [id] ASC
        ))
    END

    -- Seed first version
    IF NOT EXISTS (SELECT 1 FROM [EJ].[tblAppVersion])
    BEGIN
        INSERT INTO [EJ].[tblAppVersion] (VersionNumber, ReleaseDate, TicketReference, Description, LastUpdatedUserID)
        VALUES ('1.0.0', GETUTCDATE(), 'REL-001', 'Initial Release - Beta version features including ticketing, error logging, sysadmin portal, and private event types.', 1)
    END

    COMMIT TRANSACTION;
    PRINT 'Sikeresen lĂ©trehozva a tblAppVersion tĂˇbla Ă©s az elsĹ‘ verziĂł.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT ERROR_MESSAGE();
END CATCH
GO

-- Create SP to get versions for Sysadmin
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetVersions]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'

    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription

    SELECT 
        id AS VersionID, 
        VersionNumber, 
        ReleaseDate, 
        TicketReference, 
        Description, 
        ActiveFlg, 
        LastUpdatedUserID, 
        createdAt, 
        updatedAt
    FROM [EJ].[tblAppVersion]
    ORDER BY ReleaseDate DESC;
END
GO

-- Create SP to insert/update a version for Sysadmin
CREATE OR ALTER PROCEDURE [EJ].[spSysadminUpsertVersion]
    @VersionID INT = NULL,
    @VersionNumber NVARCHAR(50),
    @ReleaseDate DATETIME,
    @TicketReference NVARCHAR(100),
    @Description NVARCHAR(MAX),
    @ActiveFlg BIT,
    @UserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT, @ReturnDescription VARCHAR(MAX)

    BEGIN TRY
        IF (@VersionID IS NULL OR @VersionID = 0)
        BEGIN
            INSERT INTO [EJ].[tblAppVersion] (VersionNumber, ReleaseDate, TicketReference, Description, ActiveFlg, LastUpdatedUserID, createdAt, updatedAt)
            VALUES (@VersionNumber, @ReleaseDate, @TicketReference, @Description, @ActiveFlg, @UserID, GETUTCDATE(), GETUTCDATE())
        END
        ELSE
        BEGIN
            UPDATE [EJ].[tblAppVersion]
            SET 
                VersionNumber = @VersionNumber,
                ReleaseDate = @ReleaseDate,
                TicketReference = @TicketReference,
                Description = @Description,
                ActiveFlg = @ActiveFlg,
                LastUpdatedUserID = @UserID,
                updatedAt = GETUTCDATE()
            WHERE id = @VersionID
        END

        SET @ReturnValue = 1
        SET @ReturnDescription = 'Success'
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1
        SELECT @ReturnDescription = ERROR_MESSAGE()
    END CATCH

    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription
END
GO

-- Add Versioning to GetUserData so the App knows the latest version (optional, but good for UI)
-- Actually, the user says: "ami automatikusan hozzaadná a verziószámot, ehhez az elemhez." (adds version number to this element).
-- Let's just modify spGetMasterData to return the latest version info.
CREATE OR ALTER PROCEDURE [EJ].[spGetAppVersion]
AS
BEGIN
    SET NOCOUNT ON;
    SELECT TOP 1 
        id AS VersionID, 
        VersionNumber, 
        ReleaseDate, 
        TicketReference, 
        Description
    FROM [EJ].[tblAppVersion]
    WHERE ActiveFlg = 1
    ORDER BY ReleaseDate DESC;
END
GO
