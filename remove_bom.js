const fs = require('fs');
let code = fs.readFileSync('update_spSaveQuestion.sql', 'utf8');
code = code.replace(/^\uFEFF/, '');
fs.writeFileSync('update_spSaveQuestion.sql', code, 'ascii');
