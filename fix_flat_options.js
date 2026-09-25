const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

const replacement = `                                            else if (datasetName == "OpEventQuestions")
                                            {
                                                foreach (var row in datasetRows)
                                                {
                                                    Newtonsoft.Json.Linq.JArray optionsArray = null;
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
                                                                
                                                                int sortIndex = opt["SortIndex"].Value<int>();
                                                                string listType = opt["ListType"]?.ToString() ?? "";
                                                                string val = opt["Value"]?.ToString() ?? "";
                                                                long optId = opt["id"]?.Value<long>() ?? 0;
                                                                
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
                                                                                if (c["OptionID"] != null && c["OptionID"].Value<long>() == optId)
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
                                                    }
                                                }
                                                responseDict[datasetName] = datasetRows;
                                            }`;

content = content.replace(/else if \(datasetName == "OpEventQuestions"\)[\s\S]*?responseDict\[datasetName\] = datasetRows;\s*}/, replacement);
fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
