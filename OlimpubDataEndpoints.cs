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

        public OlimpubDataEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<OlimpubDataEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
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

        [Function("GetOlimpubEvent")]
        public async Task<HttpResponseData> GetEvent([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/event/{id}")] HttpRequestData req, long id)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            bool isDisplay = false;

            if (userId == null)
            {
                if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues)) {
                    var token = headerValues.FirstOrDefault();
                    if (!string.IsNullOrEmpty(token)) {
                        using (var tokenConn = new SqlConnection(_connectionString)) {
                            await tokenConn.OpenAsync();
                            using (var tokenCmd = new SqlCommand("SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE Token = @Token AND EventID = @EventID AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", tokenConn)) {
                                tokenCmd.Parameters.AddWithValue("@Token", token);
                                tokenCmd.Parameters.AddWithValue("@EventID", id);
                                if (await tokenCmd.ExecuteScalarAsync() != null) {
                                    isDisplay = true;
                                }
                            }
                        }
                    }
                }

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
                                if (rows.Count > 0)
                                {
                                    if (rows[0].ContainsKey("DatasetName") && rows[0].Count == 1)
                                    {
                                        string datasetName = rows[0]["DatasetName"]?.ToString() ?? "Unknown";
                                        if (await reader.NextResultAsync())
                                        {
                                            var datasetRows = await ReadResultSetAsync(reader);
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

                                                    string? imgKey = row.ContainsKey("ImageKey") ? row["ImageKey"]?.ToString() : null;
                                                    if (!string.IsNullOrEmpty(imgKey))
                                                    {
                                                        try {
                                                            BlobClient blobClient = containerClient.GetBlobClient($"{id}/{imgKey}");
                                                            BlobSasBuilder sasBuilder = new BlobSasBuilder() { BlobContainerName = containerClient.Name, BlobName = blobClient.Name, Resource = "b", StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5), ExpiresOn = DateTimeOffset.UtcNow.AddHours(12) };
                                                            sasBuilder.SetPermissions(BlobSasPermissions.Read);
                                                            row["ImageUrl"] = blobClient.GenerateSasUri(sasBuilder).ToString();
                                                        } catch { row["ImageUrl"] = null; }
                                                    }
                                                    else
                                                    {
                                                        row["ImageUrl"] = null;
                                                    }

                                                    string? audKey = row.ContainsKey("AudioKey") ? row["AudioKey"]?.ToString() : null;
                                                    if (!string.IsNullOrEmpty(audKey))
                                                    {
                                                        try {
                                                            BlobClient blobClient = containerClient.GetBlobClient($"{id}/{audKey}");
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
                                            else if (datasetName == "OpLive" && datasetRows.Count > 0)
                                            {
                                                responseDict[datasetName] = datasetRows[0];
                                            }
                                            else
                                            {
                                                responseDict[datasetName] = datasetRows;
                                            }
                                        }
                                    }
                                }
                            } while (await reader.NextResultAsync());
                        }
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
                if (req.Headers.TryGetValues("X-Pta-Display-Token", out var headerValues)) {
                    var token = headerValues.FirstOrDefault();
                    if (!string.IsNullOrEmpty(token)) {
                        using (var tokenConn = new SqlConnection(_connectionString)) {
                            await tokenConn.OpenAsync();
                            using (var tokenCmd = new SqlCommand("SELECT 1 FROM [PTA].[tblEventDisplayToken] WHERE Token = @Token AND EventID = @EventID AND ActiveFlg = 1 AND ExpiresAtUtc > SYSUTCDATETIME()", tokenConn)) {
                                tokenCmd.Parameters.AddWithValue("@Token", token);
                                tokenCmd.Parameters.AddWithValue("@EventID", id);
                                if (await tokenCmd.ExecuteScalarAsync() != null) {
                                    isDisplay = true;
                                }
                            }
                        }
                    }
                }

                if (!isDisplay)
                {
                    return req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                }
            }

            var queryDict = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            string board = queryDict["board"] ?? "main";

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
    }
}
