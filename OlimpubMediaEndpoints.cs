using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Configuration;
using System.Linq;

namespace EventJoy.Api.Endpoints
{
    public class OlimpubMediaEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _sqlConnectionString;
        private readonly string _jwtSecret;
        private readonly string _storageConnectionString;

        public OlimpubMediaEndpoints(ILoggerFactory loggerFactory, IConfiguration configuration)
        {
            _logger = loggerFactory.CreateLogger<OlimpubMediaEndpoints>();
            _sqlConnectionString = configuration["SqlConnectionString"] ?? string.Empty;
            _jwtSecret = configuration["JwtSecret"] ?? string.Empty;
            _storageConnectionString = configuration["AzureWebJobsStorage"] ?? string.Empty;
        }

        [Function("GetMediaUploadUrl")]
        public async Task<HttpResponseData> GetUploadUrl([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/media/upload-url")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            if (!long.TryParse(query["eventId"], out long eventId)) return req.CreateResponse(HttpStatusCode.BadRequest);
            string? fileName = query["fileName"];
            string? kind = query["kind"];
            string? contentType = query["contentType"];
            if (!long.TryParse(query["sizeInBytes"], out long sizeInBytes)) sizeInBytes = 0;

            if (kind != "image" && kind != "audio")
            {
                var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen kind." });
                return badRes;
            }

            if (kind == "image")
            {
                if (contentType != "image/jpeg" && contentType != "image/png" && contentType != "image/webp")
                {
                    var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Csak jpeg, png, webp engedélyezett képeknél." });
                    return badRes;
                }
                if (sizeInBytes > 5 * 1024 * 1024)
                {
                    var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "A kép túl nagy (max 5 MB)." });
                    return badRes;
                }
            }
            else if (kind == "audio")
            {
                if (contentType != "audio/mpeg" && contentType != "audio/mp3")
                {
                    var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Csak MP3 tölthető fel hangnak." });
                    return badRes;
                }
                if (sizeInBytes > 20 * 1024 * 1024)
                {
                    var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "A hang túl nagy (max 20 MB)." });
                    return badRes;
                }
            }

            bool isOrg = await CheckRoleAsync(eventId, userId.Value, new[] { "organizer", "Owner", "host" });
            if (!isOrg)
            {
                var forbRes = req.CreateResponse(HttpStatusCode.Forbidden);
                await forbRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Nincs jogosultságod média feltöltésére." });
                return forbRes;
            }

            try
            {
                string ext = Path.GetExtension(fileName) ?? "";
                string mediaKey = Guid.NewGuid().ToString("N").Substring(0, 8) + "-" + (kind == "image" ? "img" : "aud") + ext;
                string blobName = $"{eventId}/{mediaKey}";
                
                BlobServiceClient blobServiceClient = new BlobServiceClient(_storageConnectionString);
                BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient("op-media");
                await containerClient.CreateIfNotExistsAsync();
                
                BlobClient blobClient = containerClient.GetBlobClient(blobName);
                
                BlobSasBuilder sasBuilder = new BlobSasBuilder()
                {
                    BlobContainerName = containerClient.Name,
                    BlobName = blobClient.Name,
                    Resource = "b",
                    StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
                    ExpiresOn = DateTimeOffset.UtcNow.AddMinutes(15)
                };
                sasBuilder.SetPermissions(BlobSasPermissions.Write);
                
                Uri sasUri = blobClient.GenerateSasUri(sasBuilder);
                
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new
                {
                    MediaKey = mediaKey,
                    SasUrl = sasUri.ToString(),
                    BlobUrl = blobClient.Uri.ToString()
                });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetUploadUrl error");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("RegisterMedia")]
        public async Task<HttpResponseData> RegisterMedia([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/media")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            string body = await new StreamReader(req.Body).ReadToEndAsync();
            var payload = System.Text.Json.JsonSerializer.Deserialize<RegisterMediaPayload>(body);
            if (payload == null || string.IsNullOrEmpty(payload.MediaKey)) return req.CreateResponse(HttpStatusCode.BadRequest);

            bool isOrg = await CheckRoleAsync(payload.EventID, userId.Value, new[] { "organizer", "Owner", "host" });
            if (!isOrg) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                using (var conn = new SqlConnection(_sqlConnectionString))
                {
                    await conn.OpenAsync();
                    
                    var cmd = new SqlCommand(@"
                        MERGE INTO [OP].[tblMedia] AS t
                        USING (SELECT @EventID AS EventID, @MediaKey AS MediaKey) AS s
                        ON (t.EventID = s.EventID AND t.MediaKey = s.MediaKey)
                        WHEN MATCHED THEN
                            UPDATE SET BlobUrl = @BlobUrl, ContentHash = @ContentHash, Mime = @Mime, SizeInBytes = @SizeInBytes, FileName = @FileName, ActiveFlg = 1, LastCreatedUserID = @UserID
                        WHEN NOT MATCHED THEN
                            INSERT (EventID, MediaKey, Kind, BlobUrl, ContentHash, Mime, SizeInBytes, FileName, ActiveFlg, LastCreatedUserID)
                            VALUES (@EventID, @MediaKey, @Kind, @BlobUrl, @ContentHash, @Mime, @SizeInBytes, @FileName, 1, @UserID);
                    ", conn);
                    cmd.Parameters.AddWithValue("@EventID", payload.EventID);
                    cmd.Parameters.AddWithValue("@MediaKey", payload.MediaKey);
                    cmd.Parameters.AddWithValue("@Kind", payload.Kind);
                    cmd.Parameters.AddWithValue("@BlobUrl", payload.BlobUrl);
                    cmd.Parameters.AddWithValue("@ContentHash", payload.ContentHash);
                    cmd.Parameters.AddWithValue("@Mime", payload.Mime);
                    cmd.Parameters.AddWithValue("@SizeInBytes", payload.SizeInBytes);
                    cmd.Parameters.AddWithValue("@FileName", string.IsNullOrEmpty(payload.FileName) ? payload.MediaKey : payload.FileName);
                    cmd.Parameters.AddWithValue("@UserID", userId.Value);
                    await cmd.ExecuteNonQueryAsync();

                    if (payload.QuestionID.HasValue && !string.IsNullOrEmpty(payload.Slot))
                    {
                        if ((payload.Kind == "audio" && payload.Slot == "image") || (payload.Kind == "image" && payload.Slot == "audio"))
                        {
                            var bad = req.CreateResponse(HttpStatusCode.BadRequest);
                            await bad.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Kind and Slot mismatch." });
                            return bad;
                        }

                        var statusCmd = new SqlCommand("SELECT StatusCode FROM [OP].[tblEventQuestion] WHERE EventID = @EventID AND QuestionID = @QID AND ActiveFlg = 1", conn);
                        statusCmd.Parameters.AddWithValue("@EventID", payload.EventID);
                        statusCmd.Parameters.AddWithValue("@QID", payload.QuestionID.Value);
                        var statusObj = await statusCmd.ExecuteScalarAsync();
                        if (statusObj != null && (statusObj.ToString() == "active" || statusObj.ToString() == "stopped"))
                        {
                            var bad = req.CreateResponse(HttpStatusCode.BadRequest);
                            await bad.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "A kérdés már lement vagy fut, nem szerkeszthető." });
                            return bad;
                        }

                        string col = payload.Slot == "image" ? "ImageKey" : "AudioKey";
                        var updCmd = new SqlCommand($"UPDATE [OP].[tblQuestion] SET {col} = @Key WHERE id = @QID", conn);
                        updCmd.Parameters.AddWithValue("@Key", payload.MediaKey);
                        updCmd.Parameters.AddWithValue("@QID", payload.QuestionID.Value);
                        await updCmd.ExecuteNonQueryAsync();
                    }
                }

                string readSasUrl = payload.BlobUrl;
                try {
                    BlobServiceClient blobServiceClient = new BlobServiceClient(_storageConnectionString);
                    BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient("op-media");
                    string blobName = $"{payload.EventID}/{payload.MediaKey}";
                    BlobClient blobClient = containerClient.GetBlobClient(blobName);
                    BlobSasBuilder sasBuilder = new BlobSasBuilder()
                    {
                        BlobContainerName = containerClient.Name,
                        BlobName = blobClient.Name,
                        Resource = "b",
                        StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
                        ExpiresOn = DateTimeOffset.UtcNow.AddHours(12)
                    };
                    sasBuilder.SetPermissions(BlobSasPermissions.Read);
                    readSasUrl = blobClient.GenerateSasUri(sasBuilder).ToString();
                } catch { }

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { ReturnValue = 1, MediaKey = payload.MediaKey, BlobUrl = readSasUrl, ContentHash = payload.ContentHash, Kind = payload.Kind });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "RegisterMedia error");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetMediaManifest")]
        public async Task<HttpResponseData> GetManifest([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/media/manifest/{eventId}")] HttpRequestData req, long eventId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            bool isOrg = await CheckRoleAsync(eventId, userId.Value, new[] { "organizer", "Owner", "host" });
            bool isQm = await CheckRoleAsync(eventId, userId.Value, new[] { "game_master" });
            if (!isOrg && !isQm) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                BlobServiceClient blobServiceClient = new BlobServiceClient(_storageConnectionString);
                BlobContainerClient containerClient = blobServiceClient.GetBlobContainerClient("op-media");
                
                var items = new List<object>();

                using (var conn = new SqlConnection(_sqlConnectionString))
                {
                    await conn.OpenAsync();
                    var cmd = new SqlCommand("SELECT MediaKey, Kind, FileName, Mime, SizeInBytes, ContentHash, BlobUrl FROM [OP].[tblMedia] WHERE EventID = @EventID AND ActiveFlg = 1", conn);
                    cmd.Parameters.AddWithValue("@EventID", eventId);
                    using (var reader = await cmd.ExecuteReaderAsync())
                    {
                        while (await reader.ReadAsync())
                        {
                            string mediaKey = reader.GetString(0);
                            string blobName = $"{eventId}/{mediaKey}";
                            
                            string readSasUrl = "";
                            try {
                                BlobClient blobClient = containerClient.GetBlobClient(blobName);
                                BlobSasBuilder sasBuilder = new BlobSasBuilder()
                                {
                                    BlobContainerName = containerClient.Name,
                                    BlobName = blobClient.Name,
                                    Resource = "b",
                                    StartsOn = DateTimeOffset.UtcNow.AddMinutes(-5),
                                    ExpiresOn = DateTimeOffset.UtcNow.AddHours(12)
                                };
                                sasBuilder.SetPermissions(BlobSasPermissions.Read);
                                readSasUrl = blobClient.GenerateSasUri(sasBuilder).ToString();
                            } catch { }

                            items.Add(new {
                                MediaKey = mediaKey,
                                Kind = reader.GetString(1),
                                FileName = reader.GetString(2),
                                Mime = reader.GetString(3),
                                SizeInBytes = reader.GetInt64(4),
                                ContentHash = reader.GetString(5),
                                BlobUrl = string.IsNullOrEmpty(readSasUrl) ? reader.GetString(6) : readSasUrl
                            });
                        }
                    }
                }

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { EventID = eventId, Items = items });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GetManifest error");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("DeleteMedia")]
        public async Task<HttpResponseData> DeleteMedia([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/media/delete")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            string body = await new StreamReader(req.Body).ReadToEndAsync();
            var payload = System.Text.Json.JsonSerializer.Deserialize<DeleteMediaPayload>(body);
            if (payload == null || string.IsNullOrEmpty(payload.MediaKey)) return req.CreateResponse(HttpStatusCode.BadRequest);

            bool isOrg = await CheckRoleAsync(payload.EventID, userId.Value, new[] { "organizer", "Owner", "host" });
            if (!isOrg) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                using (var conn = new SqlConnection(_sqlConnectionString))
                {
                    await conn.OpenAsync();
                    
                    var checkCmd = new SqlCommand("SELECT COUNT(*) FROM [OP].[tblQuestion] WHERE (ImageKey = @Key OR AudioKey = @Key) AND ActiveFlg = 1", conn);
                    checkCmd.Parameters.AddWithValue("@Key", payload.MediaKey);
                    object? scalarResult = await checkCmd.ExecuteScalarAsync();
                    int count = scalarResult != null && scalarResult != DBNull.Value ? Convert.ToInt32(scalarResult) : 0;
                    if (count > 0)
                    {
                        var bad = req.CreateResponse(HttpStatusCode.BadRequest);
                        await bad.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "A média kérdéshez van kötve." });
                        return bad;
                    }

                    var delCmd = new SqlCommand("UPDATE [OP].[tblMedia] SET ActiveFlg = 0, LastCreatedUserID = @UserID WHERE EventID = @EventID AND MediaKey = @Key", conn);
                    delCmd.Parameters.AddWithValue("@EventID", payload.EventID);
                    delCmd.Parameters.AddWithValue("@Key", payload.MediaKey);
                    delCmd.Parameters.AddWithValue("@UserID", userId.Value);
                    await delCmd.ExecuteNonQueryAsync();
                }

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { ReturnValue = 1 });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "DeleteMedia error");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        private async Task<bool> CheckRoleAsync(long eventId, int userId, string[] allowedRoles)
        {
            using (var conn = new SqlConnection(_sqlConnectionString))
            {
                await conn.OpenAsync();
                string rolesParam = string.Join(",", allowedRoles.Select(r => $"'{r}'"));
                var cmd = new SqlCommand($@"
                    SELECT COUNT(*) 
                    FROM [EJ].[tblEventUser] eu 
                    JOIN [EJ].[tblEventRole] er ON eu.EventRoleID = er.id 
                    JOIN [EJ].[tblRole] r ON er.RoleID = r.id 
                    WHERE eu.EventID = @EventID 
                      AND eu.UserID = @UserID 
                      AND r.Code IN ({rolesParam}) 
                      AND eu.ActiveFlg = 1", conn);
                cmd.Parameters.AddWithValue("@EventID", eventId);
                cmd.Parameters.AddWithValue("@UserID", userId);
                object? scalarResult = await cmd.ExecuteScalarAsync();
                return scalarResult != null && scalarResult != DBNull.Value && Convert.ToInt32(scalarResult) > 0;
            }
        }
    }

    public class RegisterMediaPayload
    {
        public long EventID { get; set; }
        public string MediaKey { get; set; } = "";
        public string Kind { get; set; } = "";
        public string BlobUrl { get; set; } = "";
        public string ContentHash { get; set; } = "";
        public string Mime { get; set; } = "";
        public long SizeInBytes { get; set; }
        public string FileName { get; set; } = "";
        public int? QuestionID { get; set; }
        public string? Slot { get; set; }
    }

    public class DeleteMediaPayload
    {
        public long EventID { get; set; }
        public string MediaKey { get; set; } = "";
    }
}

