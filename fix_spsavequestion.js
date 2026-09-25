const fs = require('fs');
let sql = fs.readFileSync('OP.spSaveQuestion.sql', 'utf16le'); // Adjust BOM

// Fix BOM and trailing weirdness
let cleanSql = sql;
let lines = cleanSql.split('\n');
let startIndex = 0;
for(let i=0; i<lines.length; i++) {
    if(lines[i].includes('CREATE   PROCEDURE') || lines[i].includes('CREATE PROCEDURE')) {
        startIndex = i;
        break;
    }
}
cleanSql = lines.slice(startIndex).join('\n');
cleanSql = cleanSql.replace(/CREATE\s+PROCEDURE/g, 'CREATE OR ALTER PROCEDURE');
cleanSql = `SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n` + cleanSql;

// Insert variable declarations
cleanSql = cleanSql.replace(
    /DECLARE @QuestionID INT = JSON_VALUE\(@Json, '\$\.QuestionID'\);/,
    "DECLARE @QuestionID INT = JSON_VALUE(@Json, '$.QuestionID');\n        DECLARE @ImageKey NVARCHAR(200) = JSON_VALUE(@Json, '$.ImageKey');\n        DECLARE @AudioKey NVARCHAR(200) = JSON_VALUE(@Json, '$.AudioKey');"
);

// Insert into tblQuestion update
cleanSql = cleanSql.replace(
    /SET Prompt = @NewPrompt,[\s\n]*TimeSec = @NewTimeSec,[\s\n]*LastCreatedUserID = @UserID/,
    "SET Prompt = @NewPrompt,\n            TimeSec = @NewTimeSec,\n            LastCreatedUserID = @UserID,\n            ImageKey = ISNULL(@ImageKey, ImageKey),\n            AudioKey = ISNULL(@AudioKey, AudioKey)"
);

// If the JSON explicitly sent null, we need to allow resetting to NULL if we detect the property exists.
// Wait! The spec says:
// - Kulcs hiányzik → ne nyúlj a slothoz.
// - `null` → levétel (a `OP.Media` sor marad, csak a kötés esik).
// JSON_VALUE returns NULL if the property is missing OR if it is explicit null!
// So we must use JSON_QUERY or check with JSON_PATH to differentiate missing vs explicit null.
// Or we can use `OPENJSON` to detect explicit properties.

// Better to let C# or OPENJSON handle it. But wait, `JSON_VALUE` is fine if we parse it carefully, or we can use:
// `IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'ImageKey')`
// `UPDATE ... SET ImageKey = JSON_VALUE(@Json, '$.ImageKey')`
cleanSql = cleanSql.replace(
    /-- 2\. Update tblQuestion[\s\n]*UPDATE \[OP\]\.\[tblQuestion\][\s\n]*SET Prompt = @NewPrompt,[\s\n]*TimeSec = @NewTimeSec,[\s\n]*LastCreatedUserID = @UserID[\s\n]*WHERE id = @QuestionID;/,
    `-- 2. Update tblQuestion
        UPDATE [OP].[tblQuestion]
        SET Prompt = @NewPrompt,
            TimeSec = @NewTimeSec,
            LastCreatedUserID = @UserID
        WHERE id = @QuestionID;
        
        IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'ImageKey')
        BEGIN
            UPDATE [OP].[tblQuestion] SET ImageKey = JSON_VALUE(@Json, '$.ImageKey') WHERE id = @QuestionID;
        END

        IF EXISTS (SELECT 1 FROM OPENJSON(@Json) WHERE [key] = 'AudioKey')
        BEGIN
            UPDATE [OP].[tblQuestion] SET AudioKey = JSON_VALUE(@Json, '$.AudioKey') WHERE id = @QuestionID;
        END
`
);

fs.writeFileSync('update_spSaveQuestion.sql', cleanSql, 'utf8');
