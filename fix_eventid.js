const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

const declareEventId = `        DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET();
        DECLARE @EventID INT = JSON_VALUE(@Json, '$.EventID');

        IF @EventID IS NULL
        BEGIN
            THROW 50010, 'A JSON-ben nincs megadva az EventID, nem lehet a fordulót létrehozni!', 1;
        END`;

content = content.replace(/DECLARE @Now DATETIMEOFFSET = SYSDATETIMEOFFSET\(\);/, declareEventId);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
