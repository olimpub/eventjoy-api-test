SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO

-- Add LastUpdatedUserID where missing
IF COL_LENGTH('EJ.tblEventLocation', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblEventLocation] ADD [LastUpdatedUserID] BIGINT NULL;

IF COL_LENGTH('EJ.tblTicket', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblTicket] ADD [LastUpdatedUserID] BIGINT NULL;

IF COL_LENGTH('EJ.tblUserBillingAddress', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblUserBillingAddress] ADD [LastUpdatedUserID] BIGINT NULL;

IF COL_LENGTH('EJ.tblUserLoginIdentifier', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblUserLoginIdentifier] ADD [LastUpdatedUserID] BIGINT NULL;

IF COL_LENGTH('EJ.tblUserSettings', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblUserSettings] ADD [LastUpdatedUserID] BIGINT NULL;


-- Add LastUpdatedUserID and updatedAt where both are missing
IF COL_LENGTH('EJ.tblTicketComment', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblTicketComment] ADD [LastUpdatedUserID] BIGINT NULL;
IF COL_LENGTH('EJ.tblTicketComment', 'updatedAt') IS NULL
    ALTER TABLE [EJ].[tblTicketComment] ADD [updatedAt] DATETIMEOFFSET(0) NOT NULL DEFAULT SYSUTCDATETIME();

IF COL_LENGTH('EJ.tblUserEventTypePreference', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblUserEventTypePreference] ADD [LastUpdatedUserID] BIGINT NULL;
IF COL_LENGTH('EJ.tblUserEventTypePreference', 'updatedAt') IS NULL
    ALTER TABLE [EJ].[tblUserEventTypePreference] ADD [updatedAt] DATETIMEOFFSET(0) NOT NULL DEFAULT SYSUTCDATETIME();

IF COL_LENGTH('EJ.tblUserLabelPreference', 'LastUpdatedUserID') IS NULL
    ALTER TABLE [EJ].[tblUserLabelPreference] ADD [LastUpdatedUserID] BIGINT NULL;
IF COL_LENGTH('EJ.tblUserLabelPreference', 'updatedAt') IS NULL
    ALTER TABLE [EJ].[tblUserLabelPreference] ADD [updatedAt] DATETIMEOFFSET(0) NOT NULL DEFAULT SYSUTCDATETIME();
GO
