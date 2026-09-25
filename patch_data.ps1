$file = "C:\Dev\VsCode\EventJoy.Api\OlimpubDataEndpoints.cs"
$content = Get-Content $file -Raw

$content = $content -replace 'private readonly string _jwtSecret = .*?;', "`$0`n        private readonly string _storageConnectionString = Environment.GetEnvironmentVariable(`"AzureWebJobsStorage`") ?? string.Empty;"

$replacement = @"
                                            else if (datasetName == "OpEventQuestions")
                                            {
                                                BlobServiceClient blobServiceClient = new BlobServiceClient(_storageConnectionString);
                                                BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient("op-media");
                                                foreach (var row in datasetRows)
                                                {
                                                    JsonElement? optionsArray = null;
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
                                                    
                                                    FlattenQuestionOptions(row, optionsArray, correctsArray);

                                                    if (row.ContainsKey("ImageKey") && row["ImageKey"] != null && !string.IsNullOrEmpty(row["ImageKey"].ToString()))
                                                    {
                                                        try {
                                                            string imgKey = row["ImageKey"].ToString();
                                                            BlobClient blobClient = containerClient.GetBlobClient($"{@"{id}"}/{imgKey}");
                                                            BlobSasBuilder sasBuilder = new BlobSasBuilder() { BlobContainerName = containerClient.Name, BlobName = blobClient.Name, Resource = "b", StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5), ExpiresOn = DateTimeOffset.UtcNow.AddHours(12) };
                                                            sasBuilder.SetPermissions(BlobSasPermissions.Read);
                                                            row["ImageUrl"] = blobClient.GenerateSasUri(sasBuilder).ToString();
                                                        } catch { row["ImageUrl"] = null; }
                                                    }
                                                    else
                                                    {
                                                        row["ImageUrl"] = null;
                                                    }

                                                    if (row.ContainsKey("AudioKey") && row["AudioKey"] != null && !string.IsNullOrEmpty(row["AudioKey"].ToString()))
                                                    {
                                                        try {
                                                            string audKey = row["AudioKey"].ToString();
                                                            BlobClient blobClient = containerClient.GetBlobClient($"{@"{id}"}/{audKey}");
                                                            BlobSasBuilder sasBuilder = new BlobSasBuilder() { BlobContainerName = containerClient.Name, BlobName = blobClient.Name, Resource = "b", StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5), ExpiresOn = DateTimeOffset.UtcNow.AddHours(12) };
                                                            sasBuilder.SetPermissions(BlobSasPermissions.Read);
                                                            row["AudioUrl"] = blobClient.GenerateSasUri(sasBuilder).ToString();
                                                        } catch { row["AudioUrl"] = null; }
                                                    }
                                                    else
                                                    {
                                                        row["AudioUrl"] = null;
                                                    }
                                                }
                                                responseDict[datasetName] = datasetRows;
                                            }
"@

$content = $content -replace '(?s)else if \(datasetName == "OpEventQuestions"\).*?responseDict\[datasetName\] = datasetRows;[\r\n\s]+}', $replacement

Set-Content $file $content
