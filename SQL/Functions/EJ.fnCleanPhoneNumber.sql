SET ANSI_NULLS ON
GO
SET QUOTED_IDENTIFIER ON
GO




CREATE   FUNCTION [EJ].[fnCleanPhoneNumber]
(
    @PhoneNumber NVARCHAR(50)
)
RETURNS NVARCHAR(50)
AS
BEGIN
    DECLARE @Cleaned NVARCHAR(50);
    
    -- Remove all spaces
    SET @Cleaned = REPLACE(@PhoneNumber, ' ', '');
    
    -- Remove leading '+' sign if it exists
    IF LEFT(@Cleaned, 1) = '+'
    BEGIN
        SET @Cleaned = STUFF(@Cleaned, 1, 1, '');
    END
    
    RETURN @Cleaned;
END

