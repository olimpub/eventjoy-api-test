SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TABLE [PTA].[tblEventSpecialPrize] (
    [EventSpecialPrizeID] INT IDENTITY(1,1) NOT NULL PRIMARY KEY,
    [EventID] INT NOT NULL,
    [PrizeKind] NVARCHAR(16) NOT NULL,
    [PrizeName] NVARCHAR(150) NOT NULL,
    [WinnerEventPlayerID] INT NULL,
    [LastUpdatedUserID] BIGINT NULL,
    [createdAt] DATETIMEOFFSET(0) NOT NULL CONSTRAINT [DF_tblEventSpecialPrize_createdAt] DEFAULT (SYSDATETIMEOFFSET()),
    [updatedAt] DATETIMEOFFSET(0) NOT NULL CONSTRAINT [DF_tblEventSpecialPrize_updatedAt] DEFAULT (SYSDATETIMEOFFSET()),
    CONSTRAINT [UQ_tblEventSpecialPrize_Event_Kind] UNIQUE ([EventID], [PrizeKind]),
    CONSTRAINT [CK_tblEventSpecialPrize_Kind] CHECK ([PrizeKind] IN (N'surprise', N'weighted'))
);
GO
