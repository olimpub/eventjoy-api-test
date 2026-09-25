const fs = require('fs');
let content = fs.readFileSync('OlimpubDataEndpoints.cs', 'utf8');

const replacement = `
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spGetMasterData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            do
                            {
                                var rows = await ReadResultSetAsync(reader);
                                if (rows.Count > 0 && rows[0].ContainsKey("DatasetName") && rows[0].Count == 1)
                                {
                                    string datasetName = rows[0]["DatasetName"]?.ToString() ?? "Unknown";
                                    if (await reader.NextResultAsync())
                                    {
                                        var datasetRows = await ReadResultSetAsync(reader);
                                        responseDict[datasetName] = datasetRows;
                                    }
                                }
                            } while (await reader.NextResultAsync());
                        }
                    }
                }
`;

content = content.replace(/using\s*\(\s*var\s*conn\s*=\s*new\s*SqlConnection\(_connectionString\)\s*\)\s*\{.*?await\s*ReadResultSetAsync\(reader\);\s*\}\s*\}/s, replacement.trim());
fs.writeFileSync('OlimpubDataEndpoints.cs', content, 'utf8');
