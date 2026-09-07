SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [dbo].[tblEmailRequestParams](
	[id] [int] IDENTITY(1,1) NOT NULL,
	[RequestID] [int] NOT NULL,
	[ParamName] [varchar](100) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[ParamValue] [nvarchar](500) COLLATE SQL_Latin1_General_CP1_CI_AS NOT NULL,
	[createdAt] [datetimeoffset](7) NOT NULL
) ON [PRIMARY]

