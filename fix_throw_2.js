const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spChangeGame.sql', 'utf8');
content = content.replace(
    "THROW 50040, N'Ismeretlen Olimpub Action: ' + ISNULL(@Action, ''), 1;",
    "DECLARE @Err NVARCHAR(200) = N'Ismeretlen Olimpub Action: ' + ISNULL(@Action, ''); THROW 50040, @Err, 1;"
);
fs.writeFileSync('SQL\\Procedures\\OP.spChangeGame.sql', content, 'utf8');
