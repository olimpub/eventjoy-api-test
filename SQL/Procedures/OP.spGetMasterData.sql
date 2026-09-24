SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

CREATE OR ALTER PROCEDURE [OP].[spGetMasterData]
AS
BEGIN
    SET NOCOUNT ON;

    SELECT 'OpKabalas' AS DatasetName;
    SELECT id, Name, ImageUrl, ActiveFlg FROM [OP].[tblKabala] WHERE ActiveFlg = 1;

    SELECT 'OpTopics' AS DatasetName;
    SELECT id, Name, ActiveFlg FROM [OP].[tblTopic] WHERE ActiveFlg = 1;

END
GO
