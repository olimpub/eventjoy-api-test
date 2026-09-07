SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblDataVersion](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[MasterDataKey] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[VersionNo] [int] NOT NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblMasterDataVersion] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblDataVersion] ADD  CONSTRAINT [DF_tblMasterDataVersion_ActiveFlg]  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblDataVersion] ADD  CONSTRAINT [DF_tblMasterDataVersion_createdAt]  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblDataVersion] ADD  CONSTRAINT [DF_tblMasterDataVersion_updatedAt]  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
