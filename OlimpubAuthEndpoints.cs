using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Data.SqlClient;
using System.Text;
using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;
using System.Collections.Generic;

namespace EventJoy.Api
{
    public class DeviceJoinDto
    {
        public string DeviceId { get; set; } = string.Empty;
        public string EventUID { get; set; } = string.Empty;
        public int? TeamId { get; set; }
        public string? LastName { get; set; }
        public string? FirstName { get; set; }
    }

    public class OlimpubAuthEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";

        public OlimpubAuthEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<OlimpubAuthEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
        }

        [Function("DeviceJoin")]
        public async Task<HttpResponseData> DeviceJoin([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/device-join")] HttpRequestData req)
        {
            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = JsonConvert.DeserializeObject<DeviceJoinDto>(requestBody);

                if (string.IsNullOrEmpty(data?.DeviceId) || string.IsNullOrEmpty(data?.EventUID))
                {
                    var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("DeviceId and EventUID are required.");
                    return badReq;
                }

                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";
                long? eventId = null;
                long? eventUserId = null;
                long? userId = null;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spDeviceJoin]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                                
                                if (returnValue == 1)
                                {
                                    eventId = reader["EventID"] != DBNull.Value ? Convert.ToInt64(reader["EventID"]) : null;
                                    eventUserId = reader["EventUserID"] != DBNull.Value ? Convert.ToInt64(reader["EventUserID"]) : null;
                                    userId = reader["UserID"] != DBNull.Value ? Convert.ToInt64(reader["UserID"]) : null;
                                }
                            }
                        }
                    }
                }

                if (returnValue != 1 || userId == null)
                {
                    var errorRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await errorRes.WriteAsJsonAsync(new { ReturnValue = returnValue, ReturnDescription = returnDescription });
                    return errorRes;
                }

                // Generáljuk a JWT tokent a Device User számára
                var tokenHandler = new JwtSecurityTokenHandler();
                var key = Encoding.ASCII.GetBytes(_jwtSecret);
                var claims = new List<Claim>
                {
                    new Claim(ClaimTypes.NameIdentifier, userId.Value.ToString()),
                    new Claim("DeviceId", data.DeviceId), // Egyedi claim az Olimpubhoz
                    new Claim("EventId", eventId.ToString() ?? ""), // Esemény azonosító (hogy ne lehessen másikba belépni ezzel a tokennel)
                    new Claim("TeamId", data.TeamId?.ToString() ?? "") // Csapat azonosító a SignalR csoportba léptetéshez
                };

                var tokenDescriptor = new SecurityTokenDescriptor
                {
                    Subject = new ClaimsIdentity(claims),
                    Expires = DateTime.UtcNow.AddDays(7), // Elég egy hetes token a pubkvízhez
                    SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                };

                var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    ReturnValue = 1,
                    ReturnDescription = "Sikeres bejelentkezés",
                    EventId = eventId,
                    EventUserId = eventUserId,
                    UserId = userId,
                    JwtToken = jwtToken
                });

                return response;
            }
            catch (SqlException ex)
            {
                // A throw 50000... exceptionök elkapása
                _logger.LogError(ex, "DeviceJoin SQL error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = ex.Message });
                return errRes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "DeviceJoin error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }
    }
}
