const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

content = content.replace(/\$\.Válasz(\d)/g, '$."Válasz$1"');
content = content.replace(/\$\.Pár(\d)/g, '$."Pár$1"');

fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
