const fs = require('fs');
let content = fs.readFileSync('OlimpubEndpoints.cs', 'utf8');

content = content.replace(/\[Function\("ImportOlimpubQuestions"\)\]\s*\[Function\("SaveOlimpubQuestion"\)\]/g, '[Function("SaveOlimpubQuestion")]');

fs.writeFileSync('OlimpubEndpoints.cs', content, 'utf8');
