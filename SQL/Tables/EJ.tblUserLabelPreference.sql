SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblUserLabelPreference](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[UserID] [bigint] NOT NULL,
	[LabelID] [bigint] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblUserLabelPreference] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblUserLabelPreference_User_Label] UNIQUE NONCLUSTERED 
(
	[UserID] ASC,
	[LabelID] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblUserLabelPreference] ADD  CONSTRAINT [DF_tblUserLabelPreference_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblUserLabelPreference] ADD  CONSTRAINT [DF_tblUserLabelPreference_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
