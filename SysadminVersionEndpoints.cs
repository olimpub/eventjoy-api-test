using System;
using System.Collections.Generic;
using System.Net;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;

namespace EventJoy.Api
{
    public class SysadminVersionEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public SysadminVersionEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SysadminVersionEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") ?? throw new InvalidOperationException("SqlConnectionString is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        }

        [Function("SysadminGetVersions")]
        public async Task<HttpResponseData> GetVersions([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/versions")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                var versions = new List<Dictionary<string, object>>();
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminGetVersions]", conn) { CommandType = System.Data.CommandType.StoredProcedure })
                    {
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var dict = new Dictionary<string, object>();
                                    for (int i = 0; i < reader.FieldCount; i++)
                                    {
                                        var val = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                        // Parse JSON items if any
                                        if (reader.GetName(i) == "Items_JSON" && val != null)
                                        {
                                            dict.Add("Items", JsonDocument.Parse(val.ToString()).RootElement);
                                        }
                                        else
                                        {
                                            dict.Add(reader.GetName(i), val);
                                        }
                                    }
                                    versions.Add(dict);
                                }
                            }
                        }
                    }
                }

                var response = req.CreateResponse(HttpStatusCode.OK);
                var opts = new JsonSerializerOptions { Encoder = System.Text.Encodings.Web.JavaScriptEncoder.UnsafeRelaxedJsonEscaping }; response.Headers.Add("Content-Type", "application/json; charset=utf-8"); await response.WriteStringAsync(JsonSerializer.Serialize(new { Data = versions }, opts));
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting versions.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("SysadminUpsertVersion")]
        public async Task<HttpResponseData> UpsertVersion([HttpTrigger(AuthorizationLevel.Anonymous, "post", "put", Route = "sysadmin/versions")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);
            
            int? adminUserId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (adminUserId == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            try
            {
                var body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                var doc = JsonDocument.Parse(body).RootElement;
                
                int versionId = doc.TryGetProperty("VersionID", out var vid) && vid.ValueKind == JsonValueKind.Number ? vid.GetInt32() : 0;
                string versionNumber = doc.GetProperty("VersionNumber").GetString();
                DateTime releaseDate = doc.GetProperty("ReleaseDate").GetDateTime();
                string summary = doc.TryGetProperty("Summary", out var sm) ? sm.GetString() : null;
                bool activeFlg = doc.TryGetProperty("ActiveFlg", out var act) ? act.GetBoolean() : true;
                
                string itemsJson = null;
                if (doc.TryGetProperty("Items", out var itemsElement) && itemsElement.ValueKind == JsonValueKind.Array)
                {
                    itemsJson = itemsElement.GetRawText();
                }

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminUpsertVersion]", conn) { CommandType = System.Data.CommandType.StoredProcedure })
                    {
                        cmd.Parameters.AddWithValue("@VersionID", versionId);
                        cmd.Parameters.AddWithValue("@VersionNumber", versionNumber);
                        cmd.Parameters.AddWithValue("@ReleaseDate", releaseDate);
                        cmd.Parameters.AddWithValue("@Summary", string.IsNullOrEmpty(summary) ? DBNull.Value : summary);
                        cmd.Parameters.AddWithValue("@ActiveFlg", activeFlg);
                        cmd.Parameters.AddWithValue("@ItemsJSON", string.IsNullOrEmpty(itemsJson) ? DBNull.Value : itemsJson);
                        cmd.Parameters.AddWithValue("@UserID", adminUserId.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int retVal = reader.GetInt32(0);
                                if (retVal == 1) return req.CreateResponse(HttpStatusCode.OK);
                                else 
                                {
                                    var badRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                    await badRes.WriteStringAsync(reader.GetString(1));
                                    return badRes;
                                }
                            }
                        }
                    }
                }
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error upserting version.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}


