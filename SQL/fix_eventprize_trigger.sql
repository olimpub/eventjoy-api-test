SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO
CREATE TRIGGER [PTA].[trg_tblEventPrize_DataChangeLog]
ON [PTA].[tblEventPrize]
AFTER INSERT, UPDATE, DELETE
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Action NVARCHAR(10);
    IF EXISTS (SELECT * FROM inserted) AND EXISTS (SELECT * FROM deleted) SET @Action = 'UPDATE';
    ELSE IF EXISTS (SELECT * FROM inserted) SET @Action = 'INSERT';
    ELSE IF EXISTS (SELECT * FROM deleted) SET @Action = 'DELETE';
    ELSE RETURN;

    INSERT INTO [LOG].[tblDataChangeLog] (TableName, ActionType, OldData_JSON, NewData_JSON, UserID, CreatedAt)
    SELECT '[PTA].[tblEventPrize]', @Action,
    (SELECT d.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    (SELECT i.* FOR JSON PATH, WITHOUT_ARRAY_WRAPPER),
    ISNULL(i.LastUpdatedUserID, d.LastUpdatedUserID),
    SYSUTCDATETIME()
    FROM inserted i FULL OUTER JOIN deleted d ON i.EventID = d.EventID AND i.PrizeID = d.PrizeID;
END
GO

