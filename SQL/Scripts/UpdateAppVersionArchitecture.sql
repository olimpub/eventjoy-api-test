SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF OBJECT_ID('[EJ].[spSysadminGetVersions]', 'P') IS NOT NULL DROP PROCEDURE [EJ].[spSysadminGetVersions];
    IF OBJECT_ID('[EJ].[spSysadminUpsertVersion]', 'P') IS NOT NULL DROP PROCEDURE [EJ].[spSysadminUpsertVersion];

    IF OBJECT_ID('[EJ].[tblAppVersionItem]', 'U') IS NOT NULL DROP TABLE [EJ].[tblAppVersionItem];
    IF OBJECT_ID('[EJ].[tblAppVersion]', 'U') IS NOT NULL DROP TABLE [EJ].[tblAppVersion];
    
    CREATE TABLE [EJ].[tblAppVersion](
        [id] [int] IDENTITY(1,1) NOT NULL,
        [VersionNumber] [nvarchar](50) NOT NULL,
        [ReleaseDate] [datetime] NOT NULL,
        [Summary] [nvarchar](max) NULL,
        [ActiveFlg] [bit] NOT NULL CONSTRAINT [DF_tblAppVersion_ActiveFlg] DEFAULT ((1)),
        [LastUpdatedUserID] [bigint] NULL,
        [createdAt] [datetime] NOT NULL CONSTRAINT [DF_tblAppVersion_createdAt] DEFAULT (getutcdate()),
        [updatedAt] [datetime] NOT NULL CONSTRAINT [DF_tblAppVersion_updatedAt] DEFAULT (getutcdate()),
        CONSTRAINT [PK_tblAppVersion] PRIMARY KEY CLUSTERED ([id] ASC)
    );
    
    CREATE TABLE [EJ].[tblAppVersionItem](
        [id] [int] IDENTITY(1,1) NOT NULL,
        [VersionID] [int] NOT NULL,
        [TicketID] [bigint] NULL,             
        [InternalReference] [nvarchar](100) NULL, 
        [ExternalReference] [nvarchar](255) NULL, 
        [Description] [nvarchar](max) NOT NULL,   
        [ActiveFlg] [bit] NOT NULL CONSTRAINT [DF_tblAppVersionItem_ActiveFlg] DEFAULT ((1)),
        [createdAt] [datetime] NOT NULL CONSTRAINT [DF_tblAppVersionItem_createdAt] DEFAULT (getutcdate()),
        [updatedAt] [datetime] NOT NULL CONSTRAINT [DF_tblAppVersionItem_updatedAt] DEFAULT (getutcdate()),
        CONSTRAINT [PK_tblAppVersionItem] PRIMARY KEY CLUSTERED ([id] ASC)
    );

    ALTER TABLE [EJ].[tblAppVersionItem] WITH CHECK ADD CONSTRAINT [FK_tblAppVersionItem_VersionID] FOREIGN KEY([VersionID])
    REFERENCES [EJ].[tblAppVersion] ([id]);

    ALTER TABLE [EJ].[tblAppVersionItem] WITH CHECK ADD CONSTRAINT [FK_tblAppVersionItem_TicketID] FOREIGN KEY([TicketID])
    REFERENCES [EJ].[tblTicket] ([TicketID]); -- JAVITVA

    -- Seed first version
    INSERT INTO [EJ].[tblAppVersion] (VersionNumber, ReleaseDate, Summary, LastUpdatedUserID)
    VALUES ('1.0.0', GETUTCDATE(), 'ElsĹ‘ nagy bĂ©ta kiadĂˇs', 1);

    DECLARE @NewVersionID INT = SCOPE_IDENTITY();

    INSERT INTO [EJ].[tblAppVersionItem] (VersionID, TicketID, InternalReference, ExternalReference, Description)
    VALUES 
    (@NewVersionID, NULL, 'TASK-100', NULL, 'EsemĂ©nyek lĂ©trehozĂˇsa Ă©s jegyeladĂˇsi rendszer implementĂˇlĂˇsa.'),
    (@NewVersionID, NULL, 'TASK-101', NULL, 'Sysadmin portĂˇl Ă©s audit logolĂˇs integrĂˇlĂˇsa.'),
    (@NewVersionID, NULL, 'TASK-102', NULL, 'PrivĂˇt esemĂ©nytĂ­pusok (EventTypeOwner) bevezetĂ©se.');

    COMMIT TRANSACTION;
    PRINT 'Sikeresen frissĂ­tve az architektĂşra: tblAppVersion Ă©s tblAppVersionItem.';
END TRY
BEGIN CATCH
    IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
    PRINT ERROR_MESSAGE();
END CATCH
GO

-- Create SP to get versions with their items as JSON
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetVersions]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'

    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription

    SELECT 
        V.id AS VersionID, 
        V.VersionNumber, 
        V.ReleaseDate, 
        V.Summary, 
        V.ActiveFlg, 
        V.LastUpdatedUserID, 
        V.createdAt, 
        V.updatedAt,
        (
            SELECT 
                VI.id AS ItemID,
                VI.TicketID,
                VI.InternalReference,
                VI.ExternalReference,
                VI.Description,
                VI.ActiveFlg
            FROM [EJ].[tblAppVersionItem] VI
            WHERE VI.VersionID = V.id AND VI.ActiveFlg = 1
            FOR JSON PATH
        ) AS Items_JSON
    FROM [EJ].[tblAppVersion] V
    ORDER BY V.ReleaseDate DESC;
END
GO
