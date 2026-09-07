SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblOrganizationType](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[Code] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Name] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[LastUpdatedUserID] [bigint] NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblOrganizationType_Code] UNIQUE NONCLUSTERED 
(
	[Code] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblOrganizationType_Name] UNIQUE NONCLUSTERED 
(
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblOrganizationType] ADD  CONSTRAINT [DF_tblOrganizationType_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblOrganizationType] ADD  CONSTRAINT [DF_tblOrganizationType_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblOrganizationType] ADD  CONSTRAINT [DF_tblOrganizationType_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
