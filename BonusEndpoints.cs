using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;
using System.Net;
using System.Text.Json;
using System;
using System.Collections.Generic;
using System.Threading.Tasks;

namespace EventJoy.Api
{
    public class BonusEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public BonusEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<BonusEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") ?? throw new InvalidOperationException("Missing SqlConnectionString");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? throw new InvalidOperationException("Missing JwtSecret");
        }

        [Function("UploadBonusProof")]
        public async Task<HttpResponseData> UploadBonusProof([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/bonus/upload")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen vagy lejárt bejelentkezési token!" });
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                var dto = JsonSerializer.Deserialize<JsonElement>(requestBody);

                long eventId = dto.GetProperty("EventID").GetInt64();
                long eventUserId = dto.GetProperty("EventUserID").GetInt64();
                string platform = dto.GetProperty("Platform").GetString()!;
                string mediaUrl = dto.GetProperty("MediaUrl").GetString()!;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spUploadBonusProof]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@EventID", eventId);
                        cmd.Parameters.AddWithValue("@EventUserID", eventUserId);
                        cmd.Parameters.AddWithValue("@Platform", platform);
                        cmd.Parameters.AddWithValue("@MediaUrl", mediaUrl);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                string returnDesc = reader["ReturnDescription"]?.ToString() ?? "";
                                
                                var response = req.CreateResponse(returnValue == 1 ? HttpStatusCode.OK : HttpStatusCode.BadRequest);
                                await response.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDesc });
                                return response;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error uploading bonus proof");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = $"Error: {ex.Message}" });
                return errorRes;
            }
            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }

        [Function("GetPendingBonusProofs")]
        public async Task<HttpResponseData> GetPendingBonusProofs([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/bonus/pending/{eventId}")] HttpRequestData req, long eventId)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen vagy lejárt bejelentkezési token!" });
                return unauthRes;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spGetPendingBonusProofs]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@EventID", eventId);

                        var proofs = new List<object>();

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            // read first result set (status)
                            if (await reader.ReadAsync())
                            {
                                int returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                if (returnValue != 1)
                                {
                                    var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                    await errRes.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = reader["ReturnDescription"]?.ToString() });
                                    return errRes;
                                }
                            }

                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    proofs.Add(new
                                    {
                                        ProofID = reader["ProofID"],
                                        EventUserID = reader["EventUserID"],
                                        PlayerName = reader["PlayerName"]?.ToString(),
                                        Platform = reader["Platform"]?.ToString(),
                                        MediaUrl = reader["MediaUrl"]?.ToString(),
                                        CreatedAt = reader["createdAt"]
                                    });
                                }
                            }
                        }

                        var okRes = req.CreateResponse(HttpStatusCode.OK);
                        await okRes.WriteAsJsonAsync(new { ReturnValue = 1, Data = proofs });
                        return okRes;
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error getting pending bonus proofs");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = $"Error: {ex.Message}" });
                return errorRes;
            }
        }

        [Function("ReviewBonusProof")]
        public async Task<HttpResponseData> ReviewBonusProof([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/bonus/review")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen vagy lejárt bejelentkezési token!" });
                return unauthRes;
            }

            try
            {
                string requestBody = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
                var dto = JsonSerializer.Deserialize<JsonElement>(requestBody);

                long eventId = dto.GetProperty("EventID").GetInt64();
                long proofId = dto.GetProperty("ProofID").GetInt64();
                bool approved = dto.GetProperty("Approved").GetBoolean();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spReviewBonusProof]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@EventID", eventId);
                        cmd.Parameters.AddWithValue("@ProofID", proofId);
                        cmd.Parameters.AddWithValue("@Approved", approved);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                string returnDesc = reader["ReturnDescription"]?.ToString() ?? "";
                                
                                var response = req.CreateResponse(returnValue == 1 ? HttpStatusCode.OK : HttpStatusCode.BadRequest);
                                await response.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDesc });
                                return response;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error reviewing bonus proof");
                var errorRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errorRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = $"Error: {ex.Message}" });
                return errorRes;
            }
            return req.CreateResponse(HttpStatusCode.InternalServerError);
        }
    }
}
