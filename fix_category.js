const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spSaveQuestion.sql', 'utf8');
content = content.replace(/WHERE TypeCode IN \('single', 'multi', 'category'\) AND IsCorrect = 1;/g, "WHERE TypeCode IN ('single', 'multi') AND IsCorrect = 1;");
fs.writeFileSync('SQL\\Procedures\\OP.spSaveQuestion.sql', content, 'utf8');
