SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [EJ].[tblRefreshToken](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[UserId] [int] NOT NULL,
	[TokenHash] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[DeviceId] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[DeviceName] [nvarchar](256) COLLATE SQL_Latin1_General_CP1_CI_AS NULL,
	[ExpiresAt] [datetimeoffset](7) NOT NULL,
	[createdAt] [datetimeoffset](7) NOT NULL,
	[RevokedAt] [datetimeoffset](7) NULL,
PRIMARY KEY CLUSTERED 
(
	[id] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY],
UNIQUE NONCLUSTERED 
(
	[TokenHash] ASC
)WITH (STATISTICS_NORECOMPUTE = OFF, IGNORE_DUP_KEY = OFF) ON [PRIMARY]
) ON [PRIMARY]

GO
ALTER TABLE [EJ].[tblRefreshToken] ADD  DEFAULT (sysdatetimeoffset()) FOR [createdAt]
