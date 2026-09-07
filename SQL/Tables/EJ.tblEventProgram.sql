CREATE TABLE [EJ].[tblEventProgram] (
    [id] [bigint] IDENTITY(1,1) NOT NULL,
    [EventID] [bigint] NOT NULL,
    [ProgramDateTime] [datetimeoffset](7) NOT NULL,
    [ProgramName] [nvarchar](255) NOT NULL,
    [ActiveFlg] [bit] NOT NULL CONSTRAINT [DF_tblEventProgram_ActiveFlg] DEFAULT ((1)),
    [LastUpdatedUserID] [bigint] NULL,
    [createdAt] [datetimeoffset](7) NOT NULL CONSTRAINT [DF_tblEventProgram_createdAt] DEFAULT (sysdatetimeoffset()),
    [updatedAt] [datetimeoffset](7) NOT NULL CONSTRAINT [DF_tblEventProgram_updatedAt] DEFAULT (sysdatetimeoffset()),
    CONSTRAINT [PK_tblEventProgram] PRIMARY KEY CLUSTERED ([id] ASC)
) ON [PRIMARY];
GO
