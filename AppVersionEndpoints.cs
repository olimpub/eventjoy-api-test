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
    public class AppVersionEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public AppVersionEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<AppVersionEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") ?? throw new InvalidOperationException("SqlConnectionString is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        }

        [Function("GetAppVersions")]
        public async Task<HttpResponseData> GetAppVersions([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "app/versions")] HttpRequestData req)
        {
            // Note: Spec says any valid user JWT is required
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null) return req.CreateResponse(HttpStatusCode.Unauthorized);

            try
            {
                var versions = new List<Dictionary<string, object?>>();
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spGetAppVersions]", conn) { CommandType = System.Data.CommandType.StoredProcedure })
                    {
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var dict = new Dictionary<string, object?>();
                                    for (int i = 0; i < reader.FieldCount; i++)
                                    {
                                        var val = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                        if (reader.GetName(i) == "Items_JSON")
                                        {
                                            dict.Add("Items", val != null ? JsonDocument.Parse(val.ToString() ?? "[]").RootElement : JsonDocument.Parse("[]").RootElement);
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
                _logger.LogError(ex, "Error getting public app versions.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}


