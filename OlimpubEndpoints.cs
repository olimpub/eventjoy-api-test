using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class GenerateRoundDto
    {
        public long EventID { get; set; }
        public int TopicID { get; set; }
        public string Mode { get; set; } = "pick";
        public int RoundSortIndex { get; set; }
    }

    public class OlimpubEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";

        public OlimpubEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<OlimpubEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
        }

        [Function("GenerateOlimpubQuestions")]
        public async Task<HttpResponseData> GenerateOlimpubQuestions([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/round/generate")] HttpRequestData req)
        {
            // JWT Validáció a szervező / játékmester jogosultság ellenőrzésére
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = JsonConvert.DeserializeObject<GenerateRoundDto>(requestBody);

                if (data == null || data.EventID <= 0 || data.TopicID <= 0 || data.RoundSortIndex <= 0)
                {
                    var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("Hiányzó vagy érvénytelen paraméterek (EventID, TopicID, RoundSortIndex).");
                    return badReq;
                }

                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";
                int? roundId = null;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    
                    // TODO: Itt érdemes lehet csekkolni, hogy a UserID (Kvízmester/Szervező) valóban jogosult-e az EventID-hoz.
                    // Erre lehet használni egy [EJ].[spCheckEventPermission] eljárást, de most feltételezzük, hogy a UI validált.

                    using (var cmd = new SqlCommand("[OP].[spGenerateOlimpubQuestions]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", data.EventID);
                        cmd.Parameters.AddWithValue("@TopicID", data.TopicID);
                        cmd.Parameters.AddWithValue("@Mode", data.Mode);
                        cmd.Parameters.AddWithValue("@RoundSortIndex", data.RoundSortIndex);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                roundId = reader["RoundID"] != DBNull.Value ? Convert.ToInt32(reader["RoundID"]) : null;
                            }
                        }
                    }
                }

                if (returnValue != 1)
                {
                    var errorRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await errorRes.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDescription });
                    return errorRes;
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    ReturnValue = 1,
                    ReturnDescription = returnDescription,
                    RoundID = roundId
                });

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "GenerateOlimpubQuestions error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }

        [Function("SaveOlimpubQuestion")]
        public async Task<HttpResponseData> SaveOlimpubQuestion([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/question/save")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                if (string.IsNullOrWhiteSpace(requestBody))
                {
                    var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("Hiányzó kérés törzs.");
                    return badReq;
                }

                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spSaveQuestion]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Json", requestBody);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                            }
                        }
                    }
                }

                if (returnValue != 1)
                {
                    var errorRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await errorRes.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDescription });
                    return errorRes;
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    ReturnValue = 1,
                    ReturnDescription = returnDescription
                });

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "SaveOlimpubQuestion error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }

        [Function("ImportOlimpubQuestions")]
        public async Task<HttpResponseData> ImportOlimpubQuestions([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/questions/import")] HttpRequestData req)
        {
            int? userId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (userId == null)
            {
                var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                await unauthRes.WriteStringAsync("Érvénytelen vagy lejárt bejelentkezési token!");
                return unauthRes;
            }

            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                if (string.IsNullOrWhiteSpace(requestBody))
                {
                    var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("Hiányzó kérés törzs.");
                    return badReq;
                }

                                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";
                int? roundId = null;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spImportQuestions]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Json", requestBody);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                if (reader.FieldCount > 2 && reader["RoundID"] != DBNull.Value)
                                {
                                    roundId = Convert.ToInt32(reader["RoundID"]);
                                }
                            }
                        }
                    }
                }

                if (returnValue != 1)
                {
                    var errorRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await errorRes.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDescription });
                    return errorRes;
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    ReturnValue = 1,
                    ReturnDescription = returnDescription,
                    RoundID = roundId
                });

                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "ImportOlimpubQuestions error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }
    }
}
