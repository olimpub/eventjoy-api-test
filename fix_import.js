const fs = require('fs');
let content = fs.readFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', 'utf8');

// The OPENJSON WITH block
let newOpenJson = `FROM OPENJSON(@Json, '$.Questions')
        WITH (
            RowIndex INT '$.SortIndex', 
            TopicName NVARCHAR(120) '$.Topic', 
            TypeCode NVARCHAR(16) '$.TypeCode', 
            Prompt NVARCHAR(MAX) '$.Prompt', 
            TimeSec INT '$.TimeSec', 
            MediaUrl NVARCHAR(1000) '$.MediaUrl',
            
            Answer1 NVARCHAR(500) '$.Answer1', IsCorrect1 BIT '$.IsCorrect1', Match1 NVARCHAR(500) '$.Match1',
            Answer2 NVARCHAR(500) '$.Answer2', IsCorrect2 BIT '$.IsCorrect2', Match2 NVARCHAR(500) '$.Match2',
            Answer3 NVARCHAR(500) '$.Answer3', IsCorrect3 BIT '$.IsCorrect3', Match3 NVARCHAR(500) '$.Match3',
            Answer4 NVARCHAR(500) '$.Answer4', IsCorrect4 BIT '$.IsCorrect4', Match4 NVARCHAR(500) '$.Match4',
            Answer5 NVARCHAR(500) '$.Answer5', IsCorrect5 BIT '$.IsCorrect5', Match5 NVARCHAR(500) '$.Match5',
            Answer6 NVARCHAR(500) '$.Answer6', IsCorrect6 BIT '$.IsCorrect6', Match6 NVARCHAR(500) '$.Match6',
            Answer7 NVARCHAR(500) '$.Answer7', IsCorrect7 BIT '$.IsCorrect7', Match7 NVARCHAR(500) '$.Match7',
            Answer8 NVARCHAR(500) '$.Answer8', IsCorrect8 BIT '$.IsCorrect8', Match8 NVARCHAR(500) '$.Match8',
            
            Helyes NVARCHAR(500) '$.Helyes',
            Helyes1 BIT '$.Helyes1', Valasz1 NVARCHAR(500) '$.Válasz1', Par1 NVARCHAR(500) '$.Pár1',
            Helyes2 BIT '$.Helyes2', Valasz2 NVARCHAR(500) '$.Válasz2', Par2 NVARCHAR(500) '$.Pár2',
            Helyes3 BIT '$.Helyes3', Valasz3 NVARCHAR(500) '$.Válasz3', Par3 NVARCHAR(500) '$.Pár3',
            Helyes4 BIT '$.Helyes4', Valasz4 NVARCHAR(500) '$.Válasz4', Par4 NVARCHAR(500) '$.Pár4',
            Helyes5 BIT '$.Helyes5', Valasz5 NVARCHAR(500) '$.Válasz5', Par5 NVARCHAR(500) '$.Pár5',
            Helyes6 BIT '$.Helyes6', Valasz6 NVARCHAR(500) '$.Válasz6', Par6 NVARCHAR(500) '$.Pár6',
            Helyes7 BIT '$.Helyes7', Valasz7 NVARCHAR(500) '$.Válasz7', Par7 NVARCHAR(500) '$.Pár7',
            Helyes8 BIT '$.Helyes8', Valasz8 NVARCHAR(500) '$.Válasz8', Par8 NVARCHAR(500) '$.Pár8'
        );`;

content = content.replace(/FROM OPENJSON\(@Json, '\$\.Questions'\)[\s\S]*?\);/, newOpenJson);

// The SELECT into #IncomingQuestions
let newSelect = `SELECT 
            RowIndex, LTRIM(RTRIM(TopicName)), LOWER(LTRIM(RTRIM(TypeCode))), Prompt, TimeSec, MediaUrl,
            COALESCE(Answer1, Valasz1, Helyes), ISNULL(COALESCE(IsCorrect1, Helyes1), 0), COALESCE(Match1, Par1),
            COALESCE(Answer2, Valasz2), ISNULL(COALESCE(IsCorrect2, Helyes2), 0), COALESCE(Match2, Par2),
            COALESCE(Answer3, Valasz3), ISNULL(COALESCE(IsCorrect3, Helyes3), 0), COALESCE(Match3, Par3),
            COALESCE(Answer4, Valasz4), ISNULL(COALESCE(IsCorrect4, Helyes4), 0), COALESCE(Match4, Par4),
            COALESCE(Answer5, Valasz5), ISNULL(COALESCE(IsCorrect5, Helyes5), 0), COALESCE(Match5, Par5),
            COALESCE(Answer6, Valasz6), ISNULL(COALESCE(IsCorrect6, Helyes6), 0), COALESCE(Match6, Par6),
            COALESCE(Answer7, Valasz7), ISNULL(COALESCE(IsCorrect7, Helyes7), 0), COALESCE(Match7, Par7),
            COALESCE(Answer8, Valasz8), ISNULL(COALESCE(IsCorrect8, Helyes8), 0), COALESCE(Match8, Par8)`;

content = content.replace(/SELECT[\s\S]*?Answer8, ISNULL\(IsCorrect8, 0\), Match8/, newSelect);

fs.writeFileSync('SQL\\Procedures\\OP.spImportQuestions.sql', content, 'utf8');
