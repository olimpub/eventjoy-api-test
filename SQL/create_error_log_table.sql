SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
IF OBJECT_ID('[LOG].[tblErrorLog]', 'U') IS NULL
CREATE TABLE [LOG].[tblErrorLog](
    [ErrorID] [bigint] IDENTITY(1,1) NOT NULL PRIMARY KEY CLUSTERED,
    [Source] NVARCHAR(50) NOT NULL,
    [Severity] NVARCHAR(20) NOT NULL,
    [UserID] [bigint] NULL,
    [UrlOrAction] NVARCHAR(255) NULL,
    [ErrorMessage] NVARCHAR(MAX) NOT NULL,
    [StackTrace] NVARCHAR(MAX) NULL,
    [ContextPayload_JSON] NVARCHAR(MAX) NULL,
    [ClientInfo_JSON] NVARCHAR(MAX) NULL,
    [CreatedAt] [datetimeoffset](0) NOT NULL DEFAULT (sysdatetimeoffset())
) ON [PRIMARY]
GO

