SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblLoginIdentifierType](
	[id] [int] NOT NULL,
	[Code] [nvarchar](30) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Name] [nvarchar](50) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblLoginIdentifierType] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblLoginIdentifierType_Code] UNIQUE NONCLUSTERED 
(
	[Code] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
 CONSTRAINT [UQ_tblLoginIdentifierType_Name] UNIQUE NONCLUSTERED 
(
	[Name] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblLoginIdentifierType] ADD  CONSTRAINT [DF_tblLoginIdentifierType_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblLoginIdentifierType] ADD  CONSTRAINT [DF_tblLoginIdentifierType_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
