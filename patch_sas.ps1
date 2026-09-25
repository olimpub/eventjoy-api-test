$filePath = "EventEndpoints.cs"
$content = Get-Content $filePath -Raw

# 1. Add usings
if ($content -notmatch "using Azure\.Storage\.Blobs;") {
    $content = $content -replace "using System;", "using System;`nusing Azure.Storage.Blobs;`nusing Azure.Storage.Sas;"
}

# 2. Modify ReadResultSetAsync
$oldMethod = @"
        private async Task<List<Dictionary<string, object\?>>> ReadResultSetAsync\(SqlDataReader reader\)
        \{
            var list = new List<Dictionary<string, object\?>>\(\);
            while \(await reader.ReadAsync\(\)\)
            \{
                var row = new Dictionary<string, object\?>\(\);
                for \(int i = 0; i < reader.FieldCount; i\+\+\)
                \{
                    row\[reader.GetName\(i\)\] = reader.IsDBNull\(i\) \? null : reader.GetValue\(i\);
                \}
                list.Add\(row\);
            \}
            return list;
        \}
"@

$newMethod = @"
        private async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(SqlDataReader reader)
        {
            var list = new List<Dictionary<string, object?>>();
            
            string storageConnString = Environment.GetEnvironmentVariable("AzureWebJobsStorage") ?? Environment.GetEnvironmentVariable("StorageConnectionString") ?? "";
            BlobContainerClient? containerClient = null;
            if (!string.IsNullOrEmpty(storageConnString))
            {
                var blobServiceClient = new BlobServiceClient(storageConnString);
                containerClient = blobServiceClient.GetBlobContainerClient("materials");
            }

            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object?>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    string colName = reader.GetName(i);
                    var val = reader.IsDBNull(i) ? null : reader.GetValue(i);
                    
                    if (colName.Equals("AzurePhotoUrl", StringComparison.OrdinalIgnoreCase) && val is string url && !string.IsNullOrEmpty(url))
                    {
                        if (containerClient != null)
                        {
                            try
                            {
                                Uri uri = new Uri(url);
                                string blobName = uri.AbsolutePath.Substring(uri.AbsolutePath.IndexOf("/materials/") + 11);
                                BlobClient blobClient = containerClient.GetBlobClient(blobName);
                                BlobSasBuilder sasBuilder = new BlobSasBuilder()
                                {
                                    BlobContainerName = containerClient.Name,
                                    BlobName = blobClient.Name,
                                    Resource = "b",
                                    StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
                                    ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(15)
                                };
                                sasBuilder.SetPermissions(BlobSasPermissions.Read);
                                val = blobClient.GenerateSasUri(sasBuilder).ToString();
                            }
                            catch (Exception ex)
                            {
                                _logger.LogWarning($"Could not generate SAS for AzurePhotoUrl: {ex.Message}");
                            }
                        }
                    }

                    row[colName] = val;
                }
                list.Add(row);
            }
            return list;
        }
"@

$content = $content -replace $oldMethod, $newMethod

# 3. Modify SignalR Push in PostEvent (around line 730)
$oldSignalRPush = @"
                                        if \(!string.IsNullOrEmpty\(targetGroup\) && !string.IsNullOrEmpty\(eventName\) && !string.IsNullOrEmpty\(payloadJson\)\)
                                        \{
                                            var sbPayload = new \{ TargetGroup = targetGroup, EventName = eventName, PayloadJson = System.Text.Json.JsonSerializer.Deserialize<object>\(payloadJson\) \};
                                            var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage\(System.Text.Json.JsonSerializer.Serialize\(sbPayload\)\)
                                            \{
                                                MessageId = Guid.NewGuid\(\).ToString\(\)
                                            \};
                                            sbMessage.ApplicationProperties\["channel"\] = "signalr";
                                            messages.Add\(sbMessage\);
                                        \}
"@

$newSignalRPush = @"
                                        if (!string.IsNullOrEmpty(targetGroup) && !string.IsNullOrEmpty(eventName) && !string.IsNullOrEmpty(payloadJson))
                                        {
                                            if (eventName == "Pta.PatchDesk")
                                            {
                                                try
                                                {
                                                    var jsonObj = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(payloadJson);
                                                    if (jsonObj != null && jsonObj.TryGetValue("Payload", out var payloadObj) && payloadObj is System.Text.Json.JsonElement payloadElem && payloadElem.ValueKind == System.Text.Json.JsonValueKind.Object)
                                                    {
                                                        var innerPayload = System.Text.Json.JsonSerializer.Deserialize<Dictionary<string, object>>(payloadElem.GetRawText());
                                                        if (innerPayload != null && innerPayload.ContainsKey("AzurePhotoUrl") && innerPayload["AzurePhotoUrl"] != null)
                                                        {
                                                            string? url = innerPayload["AzurePhotoUrl"]?.ToString();
                                                            if (!string.IsNullOrEmpty(url))
                                                            {
                                                                string storageConnString = Environment.GetEnvironmentVariable("AzureWebJobsStorage") ?? Environment.GetEnvironmentVariable("StorageConnectionString") ?? "";
                                                                if (!string.IsNullOrEmpty(storageConnString))
                                                                {
                                                                    var containerClient = new BlobServiceClient(storageConnString).GetBlobContainerClient("materials");
                                                                    Uri uri = new Uri(url);
                                                                    string blobName = uri.AbsolutePath.Substring(uri.AbsolutePath.IndexOf("/materials/") + 11);
                                                                    BlobClient blobClient = containerClient.GetBlobClient(blobName);
                                                                    BlobSasBuilder sasBuilder = new BlobSasBuilder()
                                                                    {
                                                                        BlobContainerName = containerClient.Name,
                                                                        BlobName = blobClient.Name,
                                                                        Resource = "b",
                                                                        StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
                                                                        ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(15)
                                                                    };
                                                                    sasBuilder.SetPermissions(BlobSasPermissions.Read);
                                                                    innerPayload["AzurePhotoUrl"] = blobClient.GenerateSasUri(sasBuilder).ToString();
                                                                    jsonObj["Payload"] = innerPayload;
                                                                    payloadJson = System.Text.Json.JsonSerializer.Serialize(jsonObj);
                                                                }
                                                            }
                                                        }
                                                    }
                                                }
                                                catch (Exception ex)
                                                {
                                                    _logger.LogWarning($"Failed to inject SAS into PatchDesk SignalR payload: {ex.Message}");
                                                }
                                            }

                                            var sbPayload = new { TargetGroup = targetGroup, EventName = eventName, PayloadJson = System.Text.Json.JsonSerializer.Deserialize<object>(payloadJson) };
                                            var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage(System.Text.Json.JsonSerializer.Serialize(sbPayload))
                                            {
                                                MessageId = Guid.NewGuid().ToString()
                                            };
                                            sbMessage.ApplicationProperties["channel"] = "signalr";
                                            messages.Add(sbMessage);
                                        }
"@

$content = $content -replace $oldSignalRPush, $newSignalRPush

Set-Content $filePath $content
Write-Host "Patched EventEndpoints.cs"
