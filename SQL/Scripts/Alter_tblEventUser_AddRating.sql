ALTER TABLE [EJ].[tblEventUser]
ADD [Rating] TINYINT NULL,
    [RatingComment] NVARCHAR(2000) NULL;
GO

ALTER TABLE [EJ].[tblEventUser]
ADD CONSTRAINT [CK_tblEventUser_Rating]
CHECK ([Rating] IS NULL OR ([Rating] BETWEEN 1 AND 5));
GO
