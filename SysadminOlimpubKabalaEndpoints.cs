using System;
using System.Collections.Generic;
using System.Net;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Azure.Storage.Blobs;
using Azure.Storage.Sas;

namespace EventJoy.Api
{
    public class SysadminOlimpubKabalaEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _storageConnectionString;
        private readonly string _jwtSecret;

        public SysadminOlimpubKabalaEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SysadminOlimpubKabalaEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") ?? throw new InvalidOperationException("SqlConnectionString is missing.");
            _storageConnectionString = Environment.GetEnvironmentVariable("StorageConnectionString") ?? throw new InvalidOperationException("StorageConnectionString is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        }

        [Function("SysadminGetKabalas")]
        public async Task<HttpResponseData> GetKabalas([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/olimpub/kabalas")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                var kabalas = new List<Dictionary<string, object?>>();
                var assetsByKabala = new Dictionary<int, List<Dictionary<string, object?>>>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spAdminListKabala]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            // 1. Result Set: Kabalas
                            while (await reader.ReadAsync())
                            {
                                int id = reader.GetInt32(0);
                                var kabala = new Dictionary<string, object?>
                                {
                                    { "id", id },
                                    { "Name", reader.GetString(1) },
                                    { "ActiveFlg", reader.GetBoolean(2) },
                                    { "TeamCount", reader.GetInt32(3) },
                                    { "Assets", new List<Dictionary<string, object?>>() }
                                };
                                kabalas.Add(kabala);
                                assetsByKabala[id] = (List<Dictionary<string, object?>>)kabala["Assets"]!;
                            }

                            // 2. Result Set: Assets
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    int kabalaId = reader.GetInt32(1);
                                    if (assetsByKabala.TryGetValue(kabalaId, out var assetsList))
                                    {
                                        assetsList.Add(new Dictionary<string, object?>
                                        {
                                            { "id", reader.GetInt32(0) },
                                            { "Slot", reader.GetString(2) },
                                            { "Kind", reader.GetString(3) },
                                            { "BlobUrl", reader.GetString(4) },
                                            { "Mime", reader.IsDBNull(5) ? null : reader.GetString(5) },
                                            { "SizeInBytes", reader.IsDBNull(6) ? null : reader.GetInt32(6) }
                                        });
                                    }
                                }
                            }
                        }
                    }
                }

                var response = req.CreateResponse(HttpStatusCode.OK);
                var opts = new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping };
                response.Headers.Add("Content-Type", "application/json; charset=utf-8");
                await response.WriteStringAsync(JsonSerializer.Serialize(new { ReturnValue = 1, Data = kabalas }, opts));
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting kabalas.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("SysadminGetKabalaUploadUrl")]
        public async Task<HttpResponseData> GetUploadUrl([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/olimpub/kabalas/upload-url")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            string? slot = query["slot"];
            string? fileName = query["fileName"];
            string? contentType = query["contentType"];
            if (!long.TryParse(query["sizeInBytes"], out long sizeInBytes)) sizeInBytes = 0;

            if (slot != "profile" && slot != "full")
            {
                var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Ismeretlen slot." });
                return badRes;
            }

            if (contentType != "image/jpeg" && contentType != "image/png" && contentType != "image/webp")
            {
                var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Csak jpeg, png, webp engedélyezett kabalákhoz." });
                return badRes;
            }

            if (sizeInBytes < 1 || sizeInBytes > 5 * 1024 * 1024)
            {
                var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "A kép mérete érvénytelen (max 5 MB)." });
                return badRes;
            }

            try
            {
                string ext = contentType == "image/jpeg" ? ".jpg" : (contentType == "image/png" ? ".png" : ".webp");
                string mediaKey = Guid.NewGuid().ToString("N").Substring(0, 8) + ext;
                string blobName = $"kabala/{slot}/{mediaKey}";
                
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
                
                // Get absolute Uri WITHOUT the SAS token for BlobUrl
                string blobUrl = blobClient.Uri.AbsoluteUri;

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new
                {
                    ReturnValue = 1,
                    MediaKey = mediaKey,
                    SasUrl = sasUri.ToString(),
                    BlobUrl = blobUrl
                });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error generating SAS for kabala.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("SysadminSaveKabala")]
        public async Task<HttpResponseData> SaveKabala([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "sysadmin/olimpub/kabalas")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                
                // Note: The SQL SP checks the blob url length, and prefix
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spAdminSaveKabala]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int retVal = reader.GetInt32(0);
                                string retDesc = reader.IsDBNull(1) ? "" : reader.GetString(1);
                                int? id = reader.IsDBNull(2) ? null : reader.GetInt32(2);

                                if (retVal == 1)
                                {
                                    var res = req.CreateResponse(HttpStatusCode.OK);
                                    await res.WriteAsJsonAsync(new { ReturnValue = 1, id = id });
                                    return res;
                                }
                                else
                                {
                                    // SP returns -1 on error
                                    // Based on spec, it might be 400 or 404
                                    var status = retDesc.Contains("nem található") ? HttpStatusCode.NotFound : HttpStatusCode.BadRequest;
                                    var badRes = req.CreateResponse(status);
                                    await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = retDesc });
                                    return badRes;
                                }
                            }
                        }
                    }
                }

                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "SQL Error saving kabala.");
                var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                await badRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = ex.Message });
                return badRes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error saving kabala.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
