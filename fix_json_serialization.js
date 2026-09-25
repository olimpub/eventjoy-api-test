const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

// Replace using Newtonsoft.Json;
content = content.replace(/using Newtonsoft\.Json;/, 'using System.Text.Json;');

// Replace OpSettings JSON parsing
content = content.replace(/JsonConvert\.DeserializeObject\(datasetRows\[0\]\[key\]!\.ToString\(\)!\)/g, 'JsonSerializer.Deserialize<JsonElement>(datasetRows[0][key]!.ToString()!)');

// Replace OpEventQuestions JSON parsing
const oldQuestionsParsing = `                                                    Newtonsoft.Json.Linq.JArray optionsArray = null;
                                                    Newtonsoft.Json.Linq.JArray correctsArray = null;

                                                    foreach (var key in new[] { "OptionsJson", "CorrectJson" })
                                                    {
                                                        if (row.ContainsKey(key) && row[key] != null)
                                                        {
                                                            var parsed = Newtonsoft.Json.Linq.JArray.Parse(row[key]!.ToString()!);
                                                            row[key.Replace("Json", "")] = parsed;
                                                            
                                                            if (key == "OptionsJson") optionsArray = parsed;
                                                            if (key == "CorrectJson") correctsArray = parsed;
                                                            
                                                            row.Remove(key);
                                                        }
                                                    }
                                                    
                                                    // Reconstruct flat fields (Answer1..8, IsCorrect1..8, Match1..8)
                                                    string typeCode = row.ContainsKey("TypeCode") && row["TypeCode"] != null ? row["TypeCode"].ToString() : "";
                                                    
                                                    if (typeCode == "freetext")
                                                    {
                                                        if (correctsArray != null && correctsArray.Count > 0)
                                                        {
                                                            row["Answer1"] = correctsArray[0]["TextValue"]?.ToString();
                                                        }
                                                    }
                                                    else
                                                    {
                                                        if (optionsArray != null)
                                                        {
                                                            foreach (Newtonsoft.Json.Linq.JObject opt in optionsArray)
                                                            {
                                                                if (opt["SortIndex"] == null) continue;
                                                                
                                                                int sortIndex = (int)opt["SortIndex"];
                                                                string listType = opt["ListType"]?.ToString() ?? "";
                                                                string val = opt["Value"]?.ToString() ?? "";
                                                                long optId = opt["id"] != null ? (long)opt["id"] : 0;
                                                                
                                                                if (listType == "options" || listType == "left")
                                                                {
                                                                    row["Answer" + sortIndex] = val;
                                                                    
                                                                    if (typeCode == "single" || typeCode == "multi")
                                                                    {
                                                                        bool isCorrect = false;
                                                                        if (correctsArray != null)
                                                                        {
                                                                            foreach (Newtonsoft.Json.Linq.JObject c in correctsArray)
                                                                            {
                                                                                if (c["OptionID"] != null && (long)c["OptionID"] == optId)
                                                                                {
                                                                                    isCorrect = true;
                                                                                    break;
                                                                                }
                                                                            }
                                                                        }
                                                                        row["IsCorrect" + sortIndex] = isCorrect;
                                                                    }
                                                                }
                                                                else if (listType == "right")
                                                                {
                                                                    row["Match" + sortIndex] = val;
                                                                }
                                                            }
                                                        }
                                                    }`;

const newQuestionsParsing = `                                                    JsonElement? optionsArray = null;
                                                    JsonElement? correctsArray = null;

                                                    foreach (var key in new[] { "OptionsJson", "CorrectJson" })
                                                    {
                                                        if (row.ContainsKey(key) && row[key] != null)
                                                        {
                                                            var parsed = JsonSerializer.Deserialize<JsonElement>(row[key]!.ToString()!);
                                                            row[key.Replace("Json", "")] = parsed;
                                                            
                                                            if (key == "OptionsJson") optionsArray = parsed;
                                                            if (key == "CorrectJson") correctsArray = parsed;
                                                            
                                                            row.Remove(key);
                                                        }
                                                    }
                                                    
                                                    // Reconstruct flat fields (Answer1..8, IsCorrect1..8, Match1..8)
                                                    string typeCode = row.ContainsKey("TypeCode") && row["TypeCode"] != null ? row["TypeCode"].ToString() : "";
                                                    
                                                    if (typeCode == "freetext")
                                                    {
                                                        if (correctsArray.HasValue && correctsArray.Value.ValueKind == JsonValueKind.Array && correctsArray.Value.GetArrayLength() > 0)
                                                        {
                                                            var first = correctsArray.Value[0];
                                                            if (first.TryGetProperty("TextValue", out var tv) && tv.ValueKind == JsonValueKind.String)
                                                            {
                                                                row["Answer1"] = tv.GetString();
                                                            }
                                                        }
                                                    }
                                                    else
                                                    {
                                                        if (optionsArray.HasValue && optionsArray.Value.ValueKind == JsonValueKind.Array)
                                                        {
                                                            foreach (var opt in optionsArray.Value.EnumerateArray())
                                                            {
                                                                if (!opt.TryGetProperty("SortIndex", out var si) || si.ValueKind != JsonValueKind.Number) continue;
                                                                
                                                                int sortIndex = si.GetInt32();
                                                                string listType = opt.TryGetProperty("ListType", out var lt) && lt.ValueKind == JsonValueKind.String ? lt.GetString() : "";
                                                                string val = opt.TryGetProperty("Value", out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : "";
                                                                long optId = opt.TryGetProperty("id", out var idProp) && idProp.ValueKind == JsonValueKind.Number ? idProp.GetInt64() : 0;
                                                                
                                                                if (listType == "options" || listType == "left")
                                                                {
                                                                    row["Answer" + sortIndex] = val;
                                                                    
                                                                    if (typeCode == "single" || typeCode == "multi")
                                                                    {
                                                                        bool isCorrect = false;
                                                                        if (correctsArray.HasValue && correctsArray.Value.ValueKind == JsonValueKind.Array)
                                                                        {
                                                                            foreach (var c in correctsArray.Value.EnumerateArray())
                                                                            {
                                                                                if (c.TryGetProperty("OptionID", out var cOptId) && cOptId.ValueKind == JsonValueKind.Number && cOptId.GetInt64() == optId)
                                                                                {
                                                                                    isCorrect = true;
                                                                                    break;
                                                                                }
                                                                            }
                                                                        }
                                                                        row["IsCorrect" + sortIndex] = isCorrect;
                                                                    }
                                                                }
                                                                else if (listType == "right")
                                                                {
                                                                    row["Match" + sortIndex] = val;
                                                                }
                                                            }
                                                        }
                                                    }`;

content = content.replace(oldQuestionsParsing, newQuestionsParsing);
fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
