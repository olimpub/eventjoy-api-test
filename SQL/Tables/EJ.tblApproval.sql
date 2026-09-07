SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblApproval](
	[ID] [bigint] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](150) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ApprovalType] [smallint] NOT NULL,
	[Description] [nvarchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[ID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblApproval_Name] UNIQUE NONCLUSTERED 
(
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblApproval] ADD  CONSTRAINT [DF_tblApproval_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblApproval] ADD  CONSTRAINT [DF_tblApproval_createdAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblApproval] ADD  CONSTRAINT [DF_tblApproval_updatedAt]  DEFAULT (CONVERT([datetimeoffset](0),sysutcdatetime())) FOR [updatedAt]
