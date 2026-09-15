SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO

-- Update spSysadminGetTicketDetails
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetTicketDetails]
    @TicketID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    -- Ticket data
    SELECT 
        T.TicketID,
        T.ReporterUserID,
        U.EmailAddress AS ReporterEmail,
        U.FirstName AS ReporterFirstName,
        U.LastName AS ReporterLastName,
        T.Title AS Subject,
        T.StatusID,
        T.TicketTypeID AS Category,
        T.TargetVersionID,
        V.VersionNumber AS TargetVersionNumber,
        T.createdAt,
        T.updatedAt
    FROM [EJ].[tblTicket] T
    INNER JOIN [EJ].[tblUser] U ON T.ReporterUserID = U.id
    LEFT JOIN [EJ].[tblAppVersion] V ON T.TargetVersionID = V.id
    WHERE T.TicketID = @TicketID;

    -- Comments
    SELECT 
        C.CommentID,
        C.TicketID,
        C.UserID,
        U.FirstName AS AuthorFirstName,
        U.LastName AS AuthorLastName,
        U.IsSysadmin AS AuthorIsSysadmin,
        C.CommentText,
        C.IsSystemMessage,
        C.createdAt
    FROM [EJ].[tblTicketComment] C
    INNER JOIN [EJ].[tblUser] U ON C.UserID = U.id
    WHERE C.TicketID = @TicketID
    ORDER BY C.createdAt ASC;
END
GO

-- Update spSysadminGetTickets
CREATE OR ALTER PROCEDURE [EJ].[spSysadminGetTickets]
    @StatusID INT = NULL,
    @Skip INT = 0,
    @Take INT = 50
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        T.TicketID,
        T.ReporterUserID,
        U.EmailAddress AS ReporterEmail,
        U.FirstName AS ReporterFirstName,
        U.LastName AS ReporterLastName,
        T.Title AS Subject,
        T.StatusID,
        T.TicketTypeID AS Category,
        T.TargetVersionID,
        V.VersionNumber AS TargetVersionNumber,
        T.createdAt,
        T.updatedAt
    FROM [EJ].[tblTicket] T
    INNER JOIN [EJ].[tblUser] U ON T.ReporterUserID = U.id
    LEFT JOIN [EJ].[tblAppVersion] V ON T.TargetVersionID = V.id
    WHERE (@StatusID IS NULL OR T.StatusID = @StatusID)
    ORDER BY T.updatedAt DESC
    OFFSET @Skip ROWS FETCH NEXT @Take ROWS ONLY;

    SELECT COUNT(*) AS TotalCount
    FROM [EJ].[tblTicket] T
    WHERE (@StatusID IS NULL OR T.StatusID = @StatusID);
END
GO

-- Update spSysadminUpdateTicketStatus
CREATE OR ALTER PROCEDURE [EJ].[spSysadminUpdateTicketStatus]
    @TicketID BIGINT,
    @StatusID INT,
    @UserID BIGINT,
    @TargetVersionID INT = NULL
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @ReturnValue INT = 1, @ReturnDescription VARCHAR(MAX) = 'Success'

    BEGIN TRY
        UPDATE [EJ].[tblTicket]
        SET 
            StatusID = @StatusID,
            TargetVersionID = @TargetVersionID,
            updatedAt = GETUTCDATE()
        WHERE TicketID = @TicketID;

        -- LĂ©trehozunk egy system ĂĽzenetet a stĂˇtusz vĂˇltozĂˇsrĂłl
        DECLARE @StatusStr VARCHAR(50);
        SET @StatusStr = CASE @StatusID WHEN 1 THEN 'Nyitott' WHEN 2 THEN 'Folyamatban' WHEN 3 THEN 'LezĂˇrva' ELSE CAST(@StatusID AS VARCHAR) END;
        
        DECLARE @VersionStr VARCHAR(50) = '';
        IF @TargetVersionID IS NOT NULL
        BEGIN
            SELECT @VersionStr = ' (CĂ©l verziĂł: ' + VersionNumber + ')' FROM [EJ].[tblAppVersion] WHERE id = @TargetVersionID;
        END

        DECLARE @Msg NVARCHAR(MAX) = 'A jegy stĂˇtusza mĂłdosĂ­tva lett: ' + @StatusStr + @VersionStr;
        
        INSERT INTO [EJ].[tblTicketComment] (TicketID, UserID, CommentText, IsSystemMessage, createdAt)
        VALUES (@TicketID, @UserID, @Msg, 1, GETUTCDATE());
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SELECT @ReturnDescription = ERROR_MESSAGE();
    END CATCH

    SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
END
GO
