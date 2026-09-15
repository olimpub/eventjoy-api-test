SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'LOG') EXEC('CREATE SCHEMA [LOG]');
GO

IF OBJECT_ID('[LOG].[tblAuditTableDictionary]', 'U') IS NULL
CREATE TABLE [LOG].[tblAuditTableDictionary](
    [SchemaName] NVARCHAR(128) NOT NULL,
    [TableName] NVARCHAR(128) NOT NULL,
    [DisplayName] NVARCHAR(255) NOT NULL,
    [TriggerName] NVARCHAR(128) NOT NULL,
    PRIMARY KEY CLUSTERED ([SchemaName], [TableName])
) ON [PRIMARY]
GO

IF OBJECT_ID('[LOG].[tblAuditFieldDictionary]', 'U') IS NULL
CREATE TABLE [LOG].[tblAuditFieldDictionary](
    [SchemaName] NVARCHAR(128) NOT NULL,
    [TableName] NVARCHAR(128) NOT NULL,
    [ColumnName] NVARCHAR(128) NOT NULL,
    [DisplayName] NVARCHAR(255) NOT NULL,
    PRIMARY KEY CLUSTERED ([SchemaName], [TableName], [ColumnName])
) ON [PRIMARY]
GO

IF OBJECT_ID('[LOG].[tblDataChangeLog]', 'U') IS NULL
CREATE TABLE [LOG].[tblDataChangeLog](
    [LogID] [bigint] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [TableName] NVARCHAR(128) NOT NULL,
    [ActionType] NVARCHAR(10) NOT NULL,
    [OldData_JSON] NVARCHAR(MAX) NULL,
    [NewData_JSON] NVARCHAR(MAX) NULL,
    [UserID] [bigint] NULL,
    [CreatedAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset())
) ON [PRIMARY]
GO

IF NOT EXISTS (SELECT * FROM sys.indexes WHERE name = 'IX_tblDataChangeLog_CreatedAt' AND object_id = OBJECT_ID('[LOG].[tblDataChangeLog]'))
    CREATE NONCLUSTERED INDEX [IX_tblDataChangeLog_CreatedAt] ON [LOG].[tblDataChangeLog]([CreatedAt] DESC);
GO

IF OBJECT_ID('[EJ].[trg_tblEvent_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEvent_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEvent_DataChangeLog]
ON [EJ].[tblEvent]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEvent]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEvent')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEvent', 'tblEvent', '[EJ].[trg_tblEvent_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventInvitation_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventInvitation_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventInvitation_DataChangeLog]
ON [EJ].[tblEventInvitation]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventInvitation]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventInvitation')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventInvitation', 'tblEventInvitation', '[EJ].[trg_tblEventInvitation_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventLabel_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventLabel_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventLabel_DataChangeLog]
ON [EJ].[tblEventLabel]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventLabel]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventLabel')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventLabel', 'tblEventLabel', '[EJ].[trg_tblEventLabel_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventLocation_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventLocation_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventLocation_DataChangeLog]
ON [EJ].[tblEventLocation]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventLocation]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventLocation')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventLocation', 'tblEventLocation', '[EJ].[trg_tblEventLocation_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventProgram_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventProgram_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventProgram_DataChangeLog]
ON [EJ].[tblEventProgram]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventProgram]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventProgram')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventProgram', 'tblEventProgram', '[EJ].[trg_tblEventProgram_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventRole_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventRole_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventRole_DataChangeLog]
ON [EJ].[tblEventRole]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventRole]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventRole')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventRole', 'tblEventRole', '[EJ].[trg_tblEventRole_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventRoleTicket_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventRoleTicket_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventRoleTicket_DataChangeLog]
ON [EJ].[tblEventRoleTicket]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventRoleTicket]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventRoleTicket')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventRoleTicket', 'tblEventRoleTicket', '[EJ].[trg_tblEventRoleTicket_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventTicket_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventTicket_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventTicket_DataChangeLog]
ON [EJ].[tblEventTicket]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventTicket]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventTicket')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventTicket', 'tblEventTicket', '[EJ].[trg_tblEventTicket_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblEventUser_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblEventUser_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblEventUser_DataChangeLog]
ON [EJ].[tblEventUser]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblEventUser]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblEventUser')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblEventUser', 'tblEventUser', '[EJ].[trg_tblEventUser_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblOrganization_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblOrganization_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblOrganization_DataChangeLog]
ON [EJ].[tblOrganization]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblOrganization]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblOrganization')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblOrganization', 'tblOrganization', '[EJ].[trg_tblOrganization_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblOrganizationUser_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblOrganizationUser_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblOrganizationUser_DataChangeLog]
ON [EJ].[tblOrganizationUser]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblOrganizationUser]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblOrganizationUser')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblOrganizationUser', 'tblOrganizationUser', '[EJ].[trg_tblOrganizationUser_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblTicket_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblTicket_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblTicket_DataChangeLog]
ON [EJ].[tblTicket]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblTicket]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[TicketID] = d.[TicketID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblTicket')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblTicket', 'tblTicket', '[EJ].[trg_tblTicket_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblTicketComment_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblTicketComment_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblTicketComment_DataChangeLog]
ON [EJ].[tblTicketComment]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblTicketComment]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[CommentID] = d.[CommentID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblTicketComment')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblTicketComment', 'tblTicketComment', '[EJ].[trg_tblTicketComment_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblUser_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblUser_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblUser_DataChangeLog]
ON [EJ].[tblUser]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblUser]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblUser')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblUser', 'tblUser', '[EJ].[trg_tblUser_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblUserBillingAddress_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblUserBillingAddress_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblUserBillingAddress_DataChangeLog]
ON [EJ].[tblUserBillingAddress]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblUserBillingAddress]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblUserBillingAddress')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblUserBillingAddress', 'tblUserBillingAddress', '[EJ].[trg_tblUserBillingAddress_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblUserEventTypePreference_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblUserEventTypePreference_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblUserEventTypePreference_DataChangeLog]
ON [EJ].[tblUserEventTypePreference]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblUserEventTypePreference]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblUserEventTypePreference')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblUserEventTypePreference', 'tblUserEventTypePreference', '[EJ].[trg_tblUserEventTypePreference_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblUserLabelPreference_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblUserLabelPreference_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblUserLabelPreference_DataChangeLog]
ON [EJ].[tblUserLabelPreference]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblUserLabelPreference]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblUserLabelPreference')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblUserLabelPreference', 'tblUserLabelPreference', '[EJ].[trg_tblUserLabelPreference_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblUserLoginIdentifier_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblUserLoginIdentifier_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblUserLoginIdentifier_DataChangeLog]
ON [EJ].[tblUserLoginIdentifier]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblUserLoginIdentifier]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblUserLoginIdentifier')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblUserLoginIdentifier', 'tblUserLoginIdentifier', '[EJ].[trg_tblUserLoginIdentifier_DataChangeLog]');
GO

IF OBJECT_ID('[EJ].[trg_tblUserSettings_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [EJ].[trg_tblUserSettings_DataChangeLog];
GO
CREATE TRIGGER [EJ].[trg_tblUserSettings_DataChangeLog]
ON [EJ].[tblUserSettings]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[EJ].[tblUserSettings]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='EJ' AND TableName='tblUserSettings')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('EJ', 'tblUserSettings', 'tblUserSettings', '[EJ].[trg_tblUserSettings_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblChampionships_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblChampionships_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblChampionships_DataChangeLog]
ON [PTA].[tblChampionships]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblChampionships]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[ChampionshipID] = d.[ChampionshipID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblChampionships')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblChampionships', 'tblChampionships', '[PTA].[trg_tblChampionships_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventDesk_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventDesk_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventDesk_DataChangeLog]
ON [PTA].[tblEventDesk]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventDesk]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[EventDeskID] = d.[EventDeskID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventDesk')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventDesk', 'tblEventDesk', '[PTA].[trg_tblEventDesk_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventPlayer_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventPlayer_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventPlayer_DataChangeLog]
ON [PTA].[tblEventPlayer]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventPlayer]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[EventPlayerID] = d.[EventPlayerID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventPlayer')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventPlayer', 'tblEventPlayer', '[PTA].[trg_tblEventPlayer_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventPrize_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventPrize_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventPrize_DataChangeLog]
ON [PTA].[tblEventPrize]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventPrize]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[id] = d.[id];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventPrize')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventPrize', 'tblEventPrize', '[PTA].[trg_tblEventPrize_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventRound_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventRound_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventRound_DataChangeLog]
ON [PTA].[tblEventRound]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventRound]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[EventRoundID] = d.[EventRoundID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventRound')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventRound', 'tblEventRound', '[PTA].[trg_tblEventRound_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventRoundDesk_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventRoundDesk_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventRoundDesk_DataChangeLog]
ON [PTA].[tblEventRoundDesk]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventRoundDesk]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[EventRoundDeskID] = d.[EventRoundDeskID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventRoundDesk')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventRoundDesk', 'tblEventRoundDesk', '[PTA].[trg_tblEventRoundDesk_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventRoundStatus_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventRoundStatus_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventRoundStatus_DataChangeLog]
ON [PTA].[tblEventRoundStatus]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventRoundStatus]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[EventRoundStatusID] = d.[EventRoundStatusID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventRoundStatus')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventRoundStatus', 'tblEventRoundStatus', '[PTA].[trg_tblEventRoundStatus_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblEventSettings_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblEventSettings_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblEventSettings_DataChangeLog]
ON [PTA].[tblEventSettings]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventSettings]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[EventID] = d.[EventID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblEventSettings')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblEventSettings', 'tblEventSettings', '[PTA].[trg_tblEventSettings_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblExtraPrize_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblExtraPrize_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblExtraPrize_DataChangeLog]
ON [PTA].[tblExtraPrize]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblExtraPrize]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[PrizeID] = d.[PrizeID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblExtraPrize')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblExtraPrize', 'tblExtraPrize', '[PTA].[trg_tblExtraPrize_DataChangeLog]');
GO

IF OBJECT_ID('[PTA].[trg_tblGameSchedule_DataChangeLog]', 'TR') IS NOT NULL DROP TRIGGER [PTA].[trg_tblGameSchedule_DataChangeLog];
GO
CREATE TRIGGER [PTA].[trg_tblGameSchedule_DataChangeLog]
ON [PTA].[tblGameSchedule]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblGameSchedule]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.[GameScheduleID] = d.[GameScheduleID];
END
GO

IF NOT EXISTS(SELECT 1 FROM [LOG].[tblAuditTableDictionary] WHERE SchemaName='PTA' AND TableName='tblGameSchedule')
    INSERT INTO [LOG].[tblAuditTableDictionary] (SchemaName, TableName, DisplayName, TriggerName) VALUES ('PTA', 'tblGameSchedule', 'tblGameSchedule', '[PTA].[trg_tblGameSchedule_DataChangeLog]');
GO


