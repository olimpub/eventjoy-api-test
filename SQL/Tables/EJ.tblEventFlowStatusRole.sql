SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventFlowStatusRole](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[EventFlowStatusID] [bigint] NOT NULL,
	[RoleID] [bigint] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
CREATE NONCLUSTERED INDEX [IX_tblEventFlowStatusRole_Role_Active] ON [EJ].[tblEventFlowStatusRole]
(
	[RoleID] ASC,
	[ActiveFlg] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_tblEventFlowStatusRole_Status_Active] ON [EJ].[tblEventFlowStatusRole]
(
	[EventFlowStatusID] ASC,
	[ActiveFlg] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblEventFlowStatusRole] ADD  CONSTRAINT [DF_tblEventFlowStatusRole_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventFlowStatusRole] ADD  CONSTRAINT [DF_tblEventFlowStatusRole_createdAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventFlowStatusRole] ADD  CONSTRAINT [DF_tblEventFlowStatusRole_updatedAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [updatedAt]
