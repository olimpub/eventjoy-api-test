SET QUOTED_IDENTIFIER ON;
SET ANSI_NULLS ON;
GO


CREATE PROCEDURE [EJ].[spGetMasterData]
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ReturnValue INT, @ReturnDescription NVARCHAR(MAX);

    BEGIN TRY
        SET @ReturnValue = 1;
        SET @ReturnDescription = N'Success';

        DECLARE @Results TABLE
        (
            ResultNo SMALLINT,
            ResultName NVARCHAR(100)
        );

        -- RS1: Return status
        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;

        INSERT INTO @Results (ResultNo, ResultName)
        VALUES
            (1,  N'ReturnStatus'),
            (2,  N'ResultList'),
            (3,  N'EventTypes'),
            (4,  N'EventTypeGroups'),
            (5,  N'NotificationTypes'),
            (6,  N'RoleTypes'),
            (7,  N'Roles'),
            (8,  N'LoginIdentifierTypes'),
            (9,  N'UserStatuses'),
            (10, N'ChatThreadTypes'),
            (11, N'EventStatuses'),
            (12, N'EventUserStatuses'),
            (13, N'DataVersion'),
            (14, N'Organizations'),
            (15, N'OrganizationTypes'),
            (16, N'OrganizationUserTypes'),
            (17, N'EventFlows'),
            (18, N'EventFlowStatuses'),
            (19, N'EventFlowStatusRoles'),
            (20, N'EventUserFlowTemplates'),
            (21, N'EventUserFlowTemplateSteps'),
            (22, N'PtaGameTypes'),
            (23, N'PtaGameTypeRounds'),
            (24, N'PtaPairModes'),
            (25, N'PtaEventRoundStatuses'),
            (26, N'PtaExtraPrizes'),
            (27, N'PtaChampionships');

        -- RS2
        SELECT * FROM @Results ORDER BY ResultNo;

        -- RS3
        SELECT * FROM [EJ].[tblEventType] WHERE ActiveFlg = 1;

        -- RS4
        SELECT * FROM [EJ].[tblEventTypeGroup] WHERE ActiveFlg = 1;

        -- RS5
        SELECT * FROM [EJ].[tblNotificationType] WHERE ActiveFlg = 1;

        -- RS6
        SELECT * FROM [EJ].[tblRoleType] WHERE ActiveFlg = 1;

        -- RS7
        SELECT * FROM [EJ].[tblRole] WHERE ActiveFlg = 1;

        -- RS8
        SELECT * FROM [EJ].[tblLoginIdentifierType] WHERE ActiveFlg = 1;

        -- RS9
        SELECT * FROM [EJ].[tblUserStatus];

        -- RS10
        SELECT * FROM [EJ].[tblChatThreadType] WHERE ActiveFlg = 1;

        -- RS11
        SELECT * FROM [EJ].[tblEventStatus] WHERE ActiveFlg = 1;

        -- RS12
        SELECT * FROM [EJ].[tblEventUserStatus] WHERE ActiveFlg = 1;

        -- RS13
        SELECT * FROM [EJ].[tblDataVersion] WHERE ActiveFlg = 1;

        -- RS14
        SELECT * FROM [EJ].[tblOrganization] WHERE ActiveFlg = 1;

        -- RS15
        SELECT * FROM [EJ].[tblOrganizationType] WHERE ActiveFlg = 1;

        -- RS16
        SELECT * FROM [EJ].[tblOrganizationUserType] WHERE ActiveFlg = 1;

        -- RS17
        SELECT * FROM [EJ].[tblEventFlow] WHERE ActiveFlg = 1;

        -- RS18
        SELECT * FROM [EJ].[tblEventFlowStatus] WHERE ActiveFlg = 1;

        -- RS19
        SELECT * FROM [EJ].[tblEventFlowStatusRole] WHERE ActiveFlg = 1;

        -- RS20
        SELECT * FROM [EJ].[tblEventUserFlowTemplate] WHERE ActiveFlg = 1;

        -- RS21
        SELECT * FROM [EJ].[tblEventUserFlowTemplateStep] WHERE ActiveFlg = 1;

        -- RS22
        SELECT * FROM [PTA].[tblGameType] WHERE ActiveFlg = 1;

        -- RS23
        SELECT * FROM [PTA].[tblGameTypeRounds] WHERE ActiveFlg = 1;

        -- RS24
        SELECT * FROM [PTA].[tblPairMode] WHERE ActiveFlg = 1;

        -- RS25
        SELECT * FROM [PTA].[tblEventRoundStatus] WHERE ActiveFlg = 1;

        -- RS26
        SELECT * FROM [PTA].[tblExtraPrize] WHERE ActiveFlg = 1;

        -- RS27
        SELECT * FROM [PTA].[tblChampionships] WHERE ActiveFlg = 1;

    END TRY
    BEGIN CATCH
        SET @ReturnValue = -1;
        SET @ReturnDescription = ERROR_MESSAGE();

        SELECT @ReturnValue AS ReturnValue, @ReturnDescription AS ReturnDescription;
    END CATCH
END


