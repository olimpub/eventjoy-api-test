CREATE PROCEDURE [EJ].[spGetEventUserDataSheet]
    @EventUserID BIGINT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReturnValue INT = 1;
    DECLARE @ReturnDescription NVARCHAR(MAX) = N'Success';

    BEGIN TRY
        DECLARE 
            @EventID BIGINT,
            @RequesterRoleName NVARCHAR(200),
            @RequesterRoleCode NVARCHAR(100),
            @DataSheetType SMALLINT;

        DECLARE @Results TABLE
        (
            ResultNo SMALLINT,
            ResultName NVARCHAR(100)
        );

        -- context
        SELECT
            @EventID = EU.EventID,
            @RequesterRoleName = R.RoleName,
            @RequesterRoleCode = R.Code,
            @DataSheetType=RT.id
        FROM [EJ].[tblEventUser] EU
        LEFT JOIN [EJ].[tblEventRole] ER ON ER.ID = EU.EventRoleID
        LEFT JOIN [EJ].[tblRole] R ON R.ID = ER.RoleID
        LEFT JOIN [EJ].[tblRoleType] RT ON RT.ID = R.RoleTypeID
        WHERE EU.ID = @EventUserID;

        -- RS1: Return status
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        -- RS2: Result list (this is what you asked)
        INSERT INTO @Results (ResultNo, ResultName)
        VALUES
            (1, N'ReturnStatus'),
            (2, N'ResultList'),
            (3, N'ScreenContext'),
            (4, N'Events'),
            (5, N'EventParticpants');

        SELECT * FROM @Results ORDER BY ResultNo;

        -- RS3: Screen context
        SELECT
            @EventUserID AS RequestEventUserID,
            @EventID AS EventID,
            @RequesterRoleCode AS RequesterRoleCode,
            @RequesterRoleName AS RequesterRoleName,
            @DataSheetType AS DataSheetType;
        
        -- RS4: Event Data
        SELECT *        
        FROM [EJ].[tblEvent]
        WHERE ID = @EventID;

        -- RS4: Organizer datasheet
        IF (@DataSheetType = 1)
        BEGIN
            SELECT *     
            FROM [EJ].[tblEventUser] eu
            WHERE eu.EventID = @EventID
                AND eu.ID <> @EventUserID
                AND eu.ActiveFlg = 1;
        END
         
       
    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SET @ReturnDescription = ERROR_MESSAGE();

        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END
GO
