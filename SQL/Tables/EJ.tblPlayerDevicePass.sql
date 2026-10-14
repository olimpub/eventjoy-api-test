SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

IF NOT EXISTS (SELECT * FROM sys.objects WHERE object_id = OBJECT_ID(N'[EJ].[tblPlayerDevicePass]') AND type in (N'U'))
BEGIN
    CREATE TABLE [EJ].[tblPlayerDevicePass](
        [id] [bigint] IDENTITY(1,1) NOT NULL,
        [EventID] [bigint] NOT NULL,
        [EventUserID] [bigint] NOT NULL,
        [PassToken] [nvarchar](128) NOT NULL,
        [DeviceId] [uniqueidentifier] NULL,
        [BoundAtUtc] [datetimeoffset](7) NULL,
        [ExpiresAtUtc] [datetimeoffset](7) NOT NULL,
        [ActiveFlg] [bit] NOT NULL CONSTRAINT [DF_tblPlayerDevicePass_ActiveFlg] DEFAULT ((1)),
        [CreatedByUserID] [bigint] NOT NULL,
        [createdAt] [datetimeoffset](7) NOT NULL CONSTRAINT [DF_tblPlayerDevicePass_createdAt] DEFAULT (sysdatetimeoffset()),
        [updatedAt] [datetimeoffset](7) NOT NULL CONSTRAINT [DF_tblPlayerDevicePass_updatedAt] DEFAULT (sysdatetimeoffset()),
        CONSTRAINT [PK_tblPlayerDevicePass] PRIMARY KEY CLUSTERED ([id] ASC)
    );

    CREATE UNIQUE NONCLUSTERED INDEX [UX_tblPlayerDevicePass_PassToken] ON [EJ].[tblPlayerDevicePass] ([PassToken]);
    CREATE NONCLUSTERED INDEX [IX_tblPlayerDevicePass_EventUser] ON [EJ].[tblPlayerDevicePass] ([EventID], [EventUserID], [ActiveFlg]);
END
GO
