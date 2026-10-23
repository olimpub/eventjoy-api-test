using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using System.Collections.Generic;
using System.Linq;

namespace EventJoy.Api
{
    public class OlimpubDataEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        private readonly string _storageConnectionString = Environment.GetEnvironmentVariable("AzureWebJobsStorage") ?? string.Empty;
        private readonly BlobContainerClient? _opMediaContainer;

        public OlimpubDataEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<OlimpubDataEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            if (!string.IsNullOrWhiteSpace(_storageConnectionString))
            {
                try
                {
                    _opMediaContainer = new BlobServiceClient(_storageConnectionString).GetBlobContainerClient("op-media");
                }
                catch { }
            }
        }

        private async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(SqlDataReader reader)
        {
            var list = new List<Dictionary<string, object?>>();
            while (await reader.ReadAsync())
            {
                var dict = new Dictionary<string, object?>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    var val = reader.GetValue(i);
                    dict.Add(reader.GetName(i), val == DBNull.Value ? null : val);
                }
                list.Add(dict);
            }
            return list;
        }

        private async Task<bool> ValidateDisplayTokenAsync(HttpRequestData req, long eventId)
        {
            string? displayToken = null;
            if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues))
            {
                displayToken = headerValues.FirstOrDefault();
            }
            else if (req.Headers.TryGetValues("Authorization", out var authValues))
            {
                var authHeader = authValues.FirstOrDefault();
                if (!string.IsNullOrEmpty(authHeader) && authHeader.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase))
                {
                    displayToken = authHeader.Substring("Bearer ".Length).Trim();
                }
            }

            if (string.IsNullOrEmpty(displayToken)) return false;

            using (var tokenConn = new SqlConnection(_connectionString))
            {
                await tokenConn.OpenAsync();
                using (var tokenCmd = new SqlCommand("SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE Token = @Token AND EventID = @EventID AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", tokenConn))
                {
                    tokenCmd.Parameters.AddWithValue("@Token", displayToken);
                    tokenCmd.Parameters.AddWithValue("@EventID", eventId);
                    return await tokenCmd.ExecuteScalarAsync() != null;
                }
            }
        }

        [Function("GetOlimpubEvent")]
        public async Task<HttpResponseData> GetEvent([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/event/{id}")] HttpRequestData req, long id)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            bool isDisplay = false;

            if (userId == null)
            {
                isDisplay = await ValidateDisplayTokenAsync(req, id);

                if (!isDisplay)
                {
                    var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                    await unauthRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen vagy lejárt bejelentkezési token!" });
                    return unauthRes;
                }
            }

            try
            {
                var responseDict = new Dictionary<string, object?>();
                var rawDatasets = new List<(string Name, List<Dictionary<string, object?>> Rows)>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spGetEventData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", id);
                        cmd.Parameters.AddWithValue("@UserID", userId.HasValue ? (object)userId.Value : DBNull.Value);
                        cmd.Parameters.AddWithValue("@IsDisplay", isDisplay ? 1 : 0);

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
                                        rawDatasets.Add((datasetName, datasetRows));
                                    }
                                }
                            } while (await reader.NextResultAsync());
                        }
                    }
                }

                string blobBasePrefix = _opMediaContainer != null
                    ? $"{_opMediaContainer.Uri}/{id}/"
                    : $"https://eventjoyteststorage.blob.core.windows.net/op-media/{id}/";

                foreach (var (datasetName, datasetRows) in rawDatasets)
                {
                    // Handle JSON columns in OpSettings and OpEventQuestions
                    if (datasetName == "OpSettings" && datasetRows.Count > 0)
                    {
                        foreach (var key in new[] { "TopicIdsJson", "ExtraGameIdsJson" })
                        {
                            if (datasetRows[0].ContainsKey(key) && datasetRows[0][key] != null)
                            {
                                datasetRows[0][key.Replace("Json", "")] = JsonSerializer.Deserialize<JsonElement>(datasetRows[0][key]!.ToString()!);
                                datasetRows[0].Remove(key);
                            }
                        }
                        responseDict[datasetName] = datasetRows[0];
                    }
                    else if (datasetName == "OpEventQuestions" || datasetName == "OpExtraCatalog" || datasetName == "OpExtraPool")
                    {
                        foreach (var row in datasetRows)
                        {
                            JsonElement? optionsArray = null;
                            JsonElement? correctsArray = null;

                            foreach (var key in new[] { "OptionsJson", "CorrectJson" })
                            {
                                if (row.ContainsKey(key))
                                {
                                    if (row[key] != null)
                                    {
                                        var parsed = JsonSerializer.Deserialize<JsonElement>(row[key]!.ToString()!);
                                        row[key.Replace("Json", "")] = parsed;
                                        if (key == "OptionsJson") optionsArray = parsed;
                                        if (key == "CorrectJson") correctsArray = parsed;
                                    }
                                    row.Remove(key);
                                }
                            }

                            FlattenQuestionOptions(row, optionsArray, correctsArray);

                            string? imgKey = row.ContainsKey("ImageKey") ? row["ImageKey"]?.ToString() : null;
                            if (!string.IsNullOrEmpty(imgKey))
                            {
                                row["ImageUrl"] = imgKey.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                                    ? imgKey
                                    : blobBasePrefix + imgKey;
                            }
                            else
                            {
                                row["ImageUrl"] = row.ContainsKey("MediaUrl") ? row["MediaUrl"] : null;
                            }

                            string? audKey = row.ContainsKey("AudioKey") ? row["AudioKey"]?.ToString() : null;
                            if (!string.IsNullOrEmpty(audKey))
                            {
                                row["AudioUrl"] = audKey.StartsWith("http", StringComparison.OrdinalIgnoreCase)
                                    ? audKey
                                    : blobBasePrefix + audKey;
                            }
                            else
                            {
                                row["AudioUrl"] = null;
                            }
                        }
                        responseDict[datasetName] = datasetRows;
                    }
                    else if (datasetName == "OpLive" && datasetRows.Count > 0)
                    {
                        var liveRow = datasetRows[0];
                        foreach (var jsonKey in new[] { "AnswersJson", "MatchesJson", "CategoriesJson", "MosaicOutTeamIdsJson" })
                        {
                            if (liveRow.ContainsKey(jsonKey))
                            {
                                var rawVal = liveRow[jsonKey]?.ToString();
                                if (!string.IsNullOrWhiteSpace(rawVal))
                                {
                                    liveRow[jsonKey.Replace("Json", "")] = JsonSerializer.Deserialize<JsonElement>(rawVal);
                                }
                                else
                                {
                                    liveRow[jsonKey.Replace("Json", "")] = Array.Empty<string>();
                                }
                                liveRow.Remove(jsonKey);
                            }
                        }

                        if (liveRow.ContainsKey("ScreenJson"))
                        {
                            var screenJsonStr = liveRow["ScreenJson"]?.ToString();
                            liveRow.Remove("ScreenJson");
                            if (!string.IsNullOrWhiteSpace(screenJsonStr))
                            {
                                try
                                {
                                    var screenElem = JsonSerializer.Deserialize<JsonElement>(screenJsonStr);
                                    liveRow["ScreenPayload"] = screenElem;
                                    if (screenElem.ValueKind == JsonValueKind.Object)
                                    {
                                        foreach (var prop in new[] { "Teams", "Topics", "Kind", "Board", "RoundID", "RoundId", "ExtraGameId", "WinnerRoundID", "WinnerTitle" })
                                        {
                                            if (screenElem.TryGetProperty(prop, out var propVal) && !liveRow.ContainsKey(prop))
                                            {
                                                liveRow[prop] = propVal.Clone();
                                            }
                                        }
                                    }
                                }
                                catch { }
                            }
                        }

                        responseDict[datasetName] = liveRow;
                    }
                    else if (datasetName == "DisplayCast" && datasetRows.Count > 0)
                    {
                        var row = datasetRows[0];
                        if (row.ContainsKey("PayloadJson") && row["PayloadJson"] != null)
                        {
                            row["Payload"] = System.Text.Json.JsonSerializer.Deserialize<System.Text.Json.JsonElement>(row["PayloadJson"]!.ToString()!);
                            row.Remove("PayloadJson");
                        }
                        responseDict[datasetName] = row;
                    }
                    else
                    {
                        responseDict[datasetName] = datasetRows;
                    }
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(responseDict);
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetOlimpubEvent error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { Error = "Belső szerverhiba." });
                return errRes;
            }
        }

        [Function("GetOlimpubLeaderboard")]
        public async Task<HttpResponseData> GetLeaderboard([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/leaderboard/{id}")] HttpRequestData req, long id)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            bool isDisplay = false;

            if (userId == null)
            {
                isDisplay = await ValidateDisplayTokenAsync(req, id);

                if (!isDisplay)
                {
                    return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                }
            }

            var queryDict = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            
            // Handle duplicate query params gracefully by taking the first one
            string rawBoard = queryDict["board"] ?? queryDict["Board"] ?? "main";
            string board = rawBoard.Split(',')[0].Trim();

            string? rawExtra = queryDict["ExtraGameId"] ?? queryDict["extraGameId"] ?? queryDict["extragameid"];
            string? extraGameId = string.IsNullOrEmpty(rawExtra) ? null : rawExtra.Split(',')[0].Trim();
            
            string? rawRound = queryDict["RoundId"] ?? queryDict["roundId"] ?? queryDict["roundid"] ?? queryDict["RoundID"];
            int? roundId = null;
            if (!string.IsNullOrEmpty(rawRound) && int.TryParse(rawRound.Split(',')[0].Trim(), out int parsedRoundId))
            {
                roundId = parsedRoundId;
            }

            try
            {
                var rows = new List<Dictionary<string, object?>>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spGetLeaderboard]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", id);
                        cmd.Parameters.AddWithValue("@Board", board);
                        cmd.Parameters.AddWithValue("@UserID", userId.HasValue ? (object)userId.Value : DBNull.Value);
                        if (!string.IsNullOrEmpty(extraGameId))
                        {
                            cmd.Parameters.AddWithValue("@ExtraGameId", extraGameId);
                        }
                        if (roundId.HasValue)
                        {
                            cmd.Parameters.AddWithValue("@RoundID", roundId.Value);
                        }

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            rows = await ReadResultSetAsync(reader);
                        }
                    }
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    Board = board,
                    Rows = rows
                });
                return response;
            }
            catch (SqlException ex) when (ex.Number == 50050)
            {
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.Forbidden);
                await errRes.WriteAsJsonAsync(new { Error = ex.Message });
                return errRes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetOlimpubLeaderboard error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { Error = "Belső szerverhiba." });
                return errRes;
            }
        }

        [Function("GetOlimpubQuestions")]
        public async Task<HttpResponseData> GetQuestions([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/questions/{id}")] HttpRequestData req, long id)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);

            try
            {
                var rows = new List<Dictionary<string, object?>>();
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spGetRepositoryQuestions]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", id);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            rows = await ReadResultSetAsync(reader);
                            
                            BlobServiceClient blobServiceClient = new BlobServiceClient(_storageConnectionString);
                            BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient("op-media");
                            
                            foreach (var row in rows)
                            {
                                string? imgKey = row.ContainsKey("ImageKey") ? row["ImageKey"]?.ToString() : null;
                                if (!string.IsNullOrEmpty(imgKey))
                                {
                                    BlobClient blobClient = containerClient.GetBlobClient($"{id}/{imgKey}");
                                    row["ImageUrl"] = blobClient.Uri.ToString();
                                }
                                else
                                {
                                    row["ImageUrl"] = null;
                                }

                                string? audKey = row.ContainsKey("AudioKey") ? row["AudioKey"]?.ToString() : null;
                                if (!string.IsNullOrEmpty(audKey))
                                {
                                    BlobClient blobClient = containerClient.GetBlobClient($"{id}/{audKey}");
                                    row["AudioUrl"] = blobClient.Uri.ToString();
                                }
                                else
                                {
                                    row["AudioUrl"] = null;
                                }
                            }
                        }
                    }
                }
                var res = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await res.WriteAsJsonAsync(rows);
                return res;
            }
            catch (SqlException ex) when (ex.Number == 50060)
            {
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.Forbidden);
                await errRes.WriteAsJsonAsync(new { Error = ex.Message });
                return errRes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetOlimpubQuestions error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetOlimpubMasterData")]
        public async Task<HttpResponseData> GetMasterData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/master")] HttpRequestData req)
        {
            // Ezt hívja meg a wizard, JWT kell
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);

            try
            {
                var responseDict = new Dictionary<string, object?>();

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
                                          if (datasetName == "OpKabalas")
                                          {
                                              foreach (var row in datasetRows)
                                              {
                                                  if (row.ContainsKey("AssetsJson") && row["AssetsJson"] != null)
                                                  {
                                                      string jsonStr = row["AssetsJson"]?.ToString() ?? "[]";
                                                      row["Assets"] = JsonSerializer.Deserialize<JsonElement>(jsonStr);
                                                      row.Remove("AssetsJson");
                                                  }
                                                  else
                                                  {
                                                      row["Assets"] = new List<object>();
                                                  }
                                              }
                                          }
                                          responseDict[datasetName] = datasetRows;
                                    }
                                }
                            } while (await reader.NextResultAsync());
                        }
                    }
                }

                var res = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await res.WriteAsJsonAsync(responseDict);
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetOlimpubMasterData error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }

        private void FlattenQuestionOptions(Dictionary<string, object?> row, JsonElement? optionsArray, JsonElement? correctsArray)
        {
            bool hasCorrects = correctsArray.HasValue && correctsArray.Value.ValueKind == JsonValueKind.Array;
            string typeCode = (row.ContainsKey("TypeCode") ? row["TypeCode"]?.ToString() : null)?.Trim().ToLowerInvariant() ?? "single";

            for (int i = 1; i <= 8; i++)
            {
                row[$"Answer{i}"] = null;
                row[$"Match{i}"] = null;
                row[$"IsCorrect{i}"] = false;
            }

            var answersList = new List<string>();
            var matchesList = new List<string>();
            var categoriesList = new List<string>();
            var optionIdToSlot = new Dictionary<int, int>();

            if (optionsArray.HasValue && optionsArray.Value.ValueKind == JsonValueKind.Array)
            {
                foreach (var opt in optionsArray.Value.EnumerateArray())
                {
                    if (opt.TryGetProperty("SortIndex", out var idxProp) && opt.TryGetProperty("ListType", out var listTypeProp) && opt.TryGetProperty("Value", out var valProp))
                    {
                        int idx = idxProp.GetInt32();
                        string type = listTypeProp.GetString() ?? "";
                        string val = valProp.GetString() ?? "";

                        if (opt.TryGetProperty("id", out var idProp) && idProp.TryGetInt32(out int optId))
                        {
                            if (type == "left" || type == "options")
                            {
                                optionIdToSlot[optId] = idx;
                            }
                        }

                        if (idx >= 1 && idx <= 8)
                        {
                            if (type == "left" || type == "options")
                            {
                                row[$"Answer{idx}"] = val;
                                answersList.Add(val);
                            }
                            else if (type == "right")
                            {
                                row[$"Match{idx}"] = val;
                                matchesList.Add(val);
                                if (typeCode == "category" && !string.IsNullOrWhiteSpace(val) && !categoriesList.Contains(val))
                                {
                                    categoriesList.Add(val);
                                }
                            }
                        }
                    }
                }
            }

            if (hasCorrects)
            {
                foreach (var corr in correctsArray!.Value.EnumerateArray())
                {
                    if ((typeCode == "freetext" || typeCode == "no_options") && corr.TryGetProperty("TextValue", out var tvProp) && tvProp.ValueKind == JsonValueKind.String)
                    {
                        string? tv = tvProp.GetString();
                        if (!string.IsNullOrWhiteSpace(tv))
                        {
                            row["Answer1"] = tv;
                            if (answersList.Count == 0) answersList.Add(tv);
                        }
                    }

                    if (corr.TryGetProperty("SortIndex", out var idxProp) && idxProp.ValueKind == JsonValueKind.Number && idxProp.TryGetInt32(out int idx))
                    {
                        if (idx >= 1 && idx <= 8)
                        {
                            row[$"IsCorrect{idx}"] = true;
                        }
                    }
                    else if (corr.TryGetProperty("OptionID", out var optIdProp) && optIdProp.ValueKind == JsonValueKind.Number && optIdProp.TryGetInt32(out int optId))
                    {
                        if (optionIdToSlot.TryGetValue(optId, out int slotIdx) && slotIdx >= 1 && slotIdx <= 8)
                        {
                            row[$"IsCorrect{slotIdx}"] = true;
                        }
                    }
                }
            }

            row["Answers"] = answersList;
            row["Matches"] = matchesList;
            row["Categories"] = categoriesList;
        }
    }
}
