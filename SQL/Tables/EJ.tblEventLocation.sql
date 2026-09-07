SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblEventLocation](
	[id] [bigint] IDENTITY(1,1) NOT NULL,
	[LocationName] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[Country] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ZipCode] [nvarchar](20) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[City] [nvarchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[AddressLine1] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[AddressLine2] [nvarchar](200) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[Latitude] [decimal](9, 6) NULL,
	[Longitude] [decimal](9, 6) NULL,
	[ActiveFlg] [bit] NOT NULL,
	[createdAt] [datetimeoffset](0) NOT NULL,
	[updatedAt] [datetimeoffset](0) NOT NULL,
 CONSTRAINT [PK_tblEventLocation] PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
SET ANSI_PADDING ON

GO
CREATE NONCLUSTERED INDEX [IX_tblEventLocation_City] ON [EJ].[tblEventLocation]
(
	[City] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, DROP_EXISTING = OFF, ONLINE = OFF) ON [PRIMARY]
GO
ALTER TABLE [EJ].[tblEventLocation] ADD  DEFAULT (N'Magyarország') FOR [Country]
GO
ALTER TABLE [EJ].[tblEventLocation] ADD  DEFAULT ((1)) FOR [ActiveFlg]
GO
ALTER TABLE [EJ].[tblEventLocation] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
GO
ALTER TABLE [EJ].[tblEventLocation] ADD  DEFAULT (sysdatetimeoffset()) FOR [updatedAt]
