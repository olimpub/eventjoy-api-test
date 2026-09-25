const fs = require('fs');
const path = 'C:\\Dev\\VsCode\\EventJoy.Api\\SQL\\Procedures\\EJ.spSaveEvent.sql';

let content = fs.readFileSync(path, 'utf8');

// Replace mangled characters with proper Hungarian characters
content = content.replace(/Ăˇ/g, 'á')
                 .replace(/Ă©/g, 'é')
                 .replace(/Ă­/g, 'í')
                 .replace(/Ăł/g, 'ó')
                 .replace(/Ă¶/g, 'ö')
                 .replace(/Ăş/g, 'ú')
                 .replace(/ĂĽ/g, 'ü')
                 .replace(/Ă‰/g, 'É')
                 .replace(/Ĺ‘/g, 'ő')
                 .replace(/Ĺ±/g, 'ű')
                 .replace(/Ă“/g, 'Ó')
                 .replace(/ĂŤ/g, 'ë')
                 .replace(/Ă /g, 'Á');

fs.writeFileSync(path, content, 'utf8');
console.log('Done fixing encoding for spSaveEvent.sql!');
