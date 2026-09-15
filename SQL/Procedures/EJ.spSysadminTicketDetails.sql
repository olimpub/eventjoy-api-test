SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetTicketDetails]
    @TicketID BIGINT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        t.*,
        u.EmailAddress AS ReporterEmail,
        u.FirstName AS ReporterFirstName,
        u.LastName AS ReporterLastName
    FROM [EJ].[tblTicket] t
    LEFT JOIN [EJ].[tblUser] u ON t.ReporterUserID = u.Id
    WHERE t.TicketID = @TicketID;

    SELECT 
        c.*,
        u.FirstName AS AuthorFirstName,
        u.LastName AS AuthorLastName,
        u.IsSysadmin AS AuthorIsSysadmin
    FROM [EJ].[tblTicketComment] c
    LEFT JOIN [EJ].[tblUser] u ON c.UserID = u.Id
    WHERE c.TicketID = @TicketID
    ORDER BY c.createdAt ASC;
END
GO

CREATE OR ALTER PROCEDURE [EJ].[spSysadminPostTicketComment]
    @TicketID BIGINT,
    @UserID BIGINT,
    @CommentText NVARCHAR(MAX)
AS
BEGIN
    SET NOCOUNT ON;
    BEGIN TRY
        INSERT INTO [EJ].[tblTicketComment] (TicketID, UserID, CommentText, IsSystemMessage, createdAt)
        VALUES (@TicketID, @UserID, @CommentText, 0, SYSDATETIMEOFFSET());
        
        UPDATE [EJ].[tblTicket] SET updatedAt = SYSDATETIMEOFFSET(), LastUpdatedUserID = @UserID WHERE TicketID = @TicketID;
        
        SELECT 1 AS ReturnValue, N'Komment sikeresen elküldve.' AS ReturnDescription;
    END TRY
    BEGIN CATCH
        SELECT -1 AS ReturnValue, ERROR_MESSAGE() AS ReturnDescription;
    END CATCH
END
GO

