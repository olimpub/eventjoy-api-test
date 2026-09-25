const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

content = content.replace(/opt\["SortIndex"\]\.Value<int>\(\)/g, '(int)opt["SortIndex"]');
content = content.replace(/opt\["id"\]\?\.Value<long>\(\) \?\? 0/g, 'opt["id"] != null ? (long)opt["id"] : 0');
content = content.replace(/c\["OptionID"\]\.Value<long>\(\) == optId/g, '(long)c["OptionID"] == optId');

fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
