const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');
content = content.replace(
    "THROW 50020, N'Ismeretlen kérdéstípus kód(ok): ' + @MissingTypes, 1;",
    "DECLARE @ErrMsg NVARCHAR(2048) = N'Ismeretlen kérdéstípus kód(ok): ' + ISNULL(@MissingTypes, 'ismeretlen'); THROW 50020, @ErrMsg, 1;"
);
fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
