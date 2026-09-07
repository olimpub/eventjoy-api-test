SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventFlowStatus](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[EventFlowID] [bigint] NOT NULL,
	[StepID] [int] NOT NULL,
	[FromStatusID] [bigint] NULL,
	[ToStatusID] [bigint] NOT NULL,
	[CanUndoFlg] [bit] NOT NULL,
	[CanCloseFlg] [bit] NOT NULL,
	[ApprovalID] [bigint] NULL,
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
CREATE NONCLUSTERED INDEX [IX_tblEventFlowStatus_Flow_From] ON [EJ].[tblEventFlowStatus]
(
	[EventFlowID] ASC,
	[FromStatusID] ASC,
	[ActiveFlg] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE NONCLUSTERED INDEX [IX_tblEventFlowStatus_Flow_To] ON [EJ].[tblEventFlowStatus]
(
	[EventFlowID] ASC,
	[ToStatusID] ASC,
	[ActiveFlg] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblEventFlowStatus_FlowStepFromTo] ON [EJ].[tblEventFlowStatus]
(
	[EventFlowID] ASC,
	[StepID] ASC,
	[FromStatusID] ASC,
	[ToStatusID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblEventFlowStatus] ADD  CONSTRAINT [DF_tblEventFlowStatus_CanUndoFlg]  DEFAULT ((0)) FOR [CanUndoFlg]
GO
ALTER TABLE [EJ].[tblEventFlowStatus] ADD  CONSTRAINT [DF_tblEventFlowStatus_CanCloseFlg]  DEFAULT ((0)) FOR [CanCloseFlg]
GO
ALTER TABLE [EJ].[tblEventFlowStatus] ADD  CONSTRAINT [DF_tblEventFlowStatus_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventFlowStatus] ADD  CONSTRAINT [DF_tblEventFlowStatus_createdAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventFlowStatus] ADD  CONSTRAINT [DF_tblEventFlowStatus_updatedAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [updatedAt]
