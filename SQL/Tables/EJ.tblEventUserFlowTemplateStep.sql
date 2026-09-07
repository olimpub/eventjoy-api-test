SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventUserFlowTemplateStep](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[TemplateID] [bigint] NOT NULL,
	[StepID] [int] NOT NULL,
	[FromEventUserStatusID] [bigint] NULL,
	[ToEventUserStatusID] [bigint] NOT NULL,
	[CanUndoFlg] [bit] NOT NULL,
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
CREATE NONCLUSTERED INDEX [IX_tblEventUserFlowTemplateStep_Template_From] ON [EJ].[tblEventUserFlowTemplateStep]
(
	[TemplateID] ASC,
	[FromEventUserStatusID] ASC,
	[ActiveFlg] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
CREATE UNIQUE NONCLUSTERED INDEX [UX_tblEventUserFlowTemplateStep_Unique] ON [EJ].[tblEventUserFlowTemplateStep]
(
	[TemplateID] ASC,
	[StepID] ASC,
	[FromEventUserStatusID] ASC,
	[ToEventUserStatusID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblEventUserFlowTemplateStep] ADD  CONSTRAINT [DF_tblEventUserFlowTemplateStep_CanUndoFlg]  DEFAULT ((0)) FOR [CanUndoFlg]
GO
ALTER TABLE [EJ].[tblEventUserFlowTemplateStep] ADD  CONSTRAINT [DF_tblEventUserFlowTemplateStep_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventUserFlowTemplateStep] ADD  CONSTRAINT [DF_tblEventUserFlowTemplateStep_createdAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventUserFlowTemplateStep] ADD  CONSTRAINT [DF_tblEventUserFlowTemplateStep_updatedAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [updatedAt]
