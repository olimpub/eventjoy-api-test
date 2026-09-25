const fs = require('fs');
let files = ['SQL\\Procedures\\OP.spImportQuestions.sql', 'SQL\\Procedures\\OP.spSaveQuestion.sql'];

files.forEach(file => {
    let content = fs.readFileSync(file, 'utf8');

    // 1. LEFT OPTIONS
    content = content.replace(/CASE WHEN source\.TypeCode = 'match' THEN 'left' ELSE 'options' END/g, "CASE WHEN source.TypeCode IN ('match', 'category') THEN 'left' ELSE 'options' END");
    
    // 2. RIGHT OPTIONS (Match and Category)
    content = content.replace(/USING \(SELECT \* FROM #TempOptions WHERE TypeCode = 'match' AND MatchText IS NOT NULL\) AS source/g, "USING (SELECT * FROM #TempOptions WHERE TypeCode IN ('match', 'category') AND MatchText IS NOT NULL) AS source");

    // 3. CORRECT ANSWERS
    // In spImportQuestions and spSaveQuestion, the correct answers were:
    // WHERE TypeCode IN ('single', 'multi') AND IsCorrect = 1;
    // WHERE TypeCode = 'order';
    // WHERE TypeCode = 'match';
    content = content.replace(/WHERE TypeCode = 'match';/g, "WHERE TypeCode IN ('match', 'category');");

    fs.writeFileSync(file, content, 'utf8');
});
