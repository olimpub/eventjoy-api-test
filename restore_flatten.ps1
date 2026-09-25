$file = "C:\Dev\VsCode\EventJoy.Api\OlimpubDataEndpoints.cs"
$content = Get-Content $file -Raw

$method = @"
        private void FlattenQuestionOptions(Dictionary<string, object> row, JsonElement? optionsArray, JsonElement? correctsArray)
        {
            for (int i = 1; i <= 8; i++)
            {
                row[$"Answer{i}"] = null;
                row[$"Match{i}"] = null;
                row[$"IsCorrect{i}"] = false;
            }

            if (optionsArray.HasValue && optionsArray.Value.ValueKind == JsonValueKind.Array)
            {
                foreach (var opt in optionsArray.Value.EnumerateArray())
                {
                    if (opt.TryGetProperty("SortIndex", out var idxProp) && opt.TryGetProperty("ListType", out var listTypeProp) && opt.TryGetProperty("Value", out var valProp))
                    {
                        int idx = idxProp.GetInt32();
                        if (idx >= 1 && idx <= 8)
                        {
                            string type = listTypeProp.GetString() ?? "";
                            if (type == "left") row[$"Answer{idx}"] = valProp.GetString();
                            else if (type == "right") row[$"Match{idx}"] = valProp.GetString();
                        }
                    }
                }
            }

            if (correctsArray.HasValue && correctsArray.Value.ValueKind == JsonValueKind.Array)
            {
                foreach (var corr in correctsArray.Value.EnumerateArray())
                {
                    if (corr.TryGetProperty("SortIndex", out var idxProp))
                    {
                        int idx = idxProp.GetInt32();
                        if (idx >= 1 && idx <= 8)
                        {
                            row[$"IsCorrect{idx}"] = true;
                        }
                    }
                }
            }
        }
"@

$content = $content -replace "\s*\}\s*\}\s*$", "`n$method`n    }`n}"
Set-Content $file $content
