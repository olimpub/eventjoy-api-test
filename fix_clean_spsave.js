const fs = require('fs');
let code = fs.readFileSync('clean_spsavequestion.sql', 'utf16le'); // Adjust BOM
// Extract just the CREATE PROCEDURE part
let lines = code.split('\n');
let startIndex = 0;
for(let i=0; i<lines.length; i++) {
    if(lines[i].includes('CREATE   PROCEDURE') || lines[i].includes('CREATE PROCEDURE')) {
        startIndex = i;
        break;
    }
}
code = lines.slice(startIndex).join('\n');
code = code.replace(/CREATE\s+PROCEDURE/i, 'CREATE OR ALTER PROCEDURE');
code = `SET ANSI_NULLS ON;\nGO\nSET QUOTED_IDENTIFIER ON;\nGO\n` + code;

code = code.replace(
    /-- 2\. Update tblQuestion\s*UPDATE \[OP\]\.\[tblQuestion\]\s*SET Prompt = @NewPrompt,\s*TimeSec = @NewTimeSec,\s*LastCreatedUserID = @UserID\s*WHERE id = @QuestionID;/m,
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

fs.writeFileSync('update_spSaveQuestion.sql', code, 'utf8');
