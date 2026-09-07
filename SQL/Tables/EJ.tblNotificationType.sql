SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblNotificationType](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[Name] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblNotificationType] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblNotificationType_Name] UNIQUE NONCLUSTERED 
(
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblNotificationType] ADD  CONSTRAINT [DF_tblNotificationType_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblNotificationType] ADD  CONSTRAINT [DF_tblNotificationType_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
