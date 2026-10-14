using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;
using System.IdentityModel.Tokens.Jwt;
using Newtonsoft.Json;

namespace EventJoy.Api
{
    public class PlayerPassRequestDto
    {
        public long? EventID { get; set; }
        public long? EventUserID { get; set; }
        public bool? Rotate { get; set; }
    }

    public class PlayerDeviceJoinRequestDto
    {
        public string? PassToken { get; set; }
        public string? DeviceId { get; set; }
        public string? DeviceName { get; set; }
    }

    public class PlayerPassEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public PlayerPassEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<PlayerPassEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret")
                ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        }

        // =========================================================================
        // 1. JÁTÉKOS BELÉPŐ KÓD KÉRÉSE (Szervező / Játékmester)
        // =========================================================================
        [Function("PlayerPass")]
        public async Task<HttpResponseData> PlayerPass(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/player-pass")] HttpRequestData req)
        {
            int? callerUserId = JwtValidator.ValidateTokenAndGetUserId(req, _jwtSecret);
            if (callerUserId == null)
            {
                var unauthRes = req.CreateResponse(HttpStatusCode.Unauthorized);
                await unauthRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Érvénytelen vagy lejárt bejelentkezési token." });
                return unauthRes;
            }

            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = JsonConvert.DeserializeObject<PlayerPassRequestDto>(requestBody);

                if (data == null || data.EventID == null || data.EventUserID == null)
                {
                    var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badReq.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "EventID és EventUserID megadása kötelező." });
                    return badReq;
                }

                // Generálunk egy URL-biztos 32 bájtos kriptográfiailag biztonságos tokent (64 karakteres hex)
                string newPassToken = Convert.ToHexString(RandomNumberGenerator.GetBytes(32)).ToLowerInvariant();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spCreateOrGetPlayerPass]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", data.EventID.Value);
                        cmd.Parameters.AddWithValue("@EventUserID", data.EventUserID.Value);
                        cmd.Parameters.AddWithValue("@CallerUserID", callerUserId.Value);
                        cmd.Parameters.AddWithValue("@Rotate", data.Rotate == true);
                        cmd.Parameters.AddWithValue("@NewPassToken", newPassToken);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                string returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;

                                if (returnValue == 1)
                                {
                                    string passToken = reader["PassToken"].ToString()!;
                                    DateTimeOffset expiresAtUtc = (DateTimeOffset)reader["ExpiresAtUtc"];

                                    var okRes = req.CreateResponse(HttpStatusCode.OK);
                                    await okRes.WriteAsJsonAsync(new
                                    {
                                        ReturnValue = 1,
                                        ReturnDescription = returnDescription,
                                        PassToken = passToken,
                                        ExpiresAtUtc = expiresAtUtc.ToString("o")
                                    });
                                    return okRes;
                                }

                                HttpStatusCode statusCode = returnValue switch
                                {
                                    403 => HttpStatusCode.Forbidden,
                                    400 => HttpStatusCode.BadRequest,
                                    404 => HttpStatusCode.NotFound,
                                    _ => HttpStatusCode.BadRequest
                                };

                                var errRes = req.CreateResponse(statusCode);
                                await errRes.WriteAsJsonAsync(new
                                {
                                    ReturnValue = -1,
                                    ReturnDescription = returnDescription
                                });
                                return errRes;
                            }
                        }
                    }
                }

                var fallbackErr = req.CreateResponse(HttpStatusCode.InternalServerError);
                await fallbackErr.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Váratlan hiba történt a belépő kiadásakor." });
                return fallbackErr;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "PlayerPass error");
                var errRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }

        // =========================================================================
        // 2. JÁTÉKOS ESZKÖZ CSATLAKOZÁSA (Telefon olvasás)
        // =========================================================================
        [Function("PlayerDeviceJoin")]
        public async Task<HttpResponseData> PlayerDeviceJoin(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/player-device-join")] HttpRequestData req)
        {
            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = JsonConvert.DeserializeObject<PlayerDeviceJoinRequestDto>(requestBody);

                if (data == null || string.IsNullOrWhiteSpace(data.DeviceId) || !Guid.TryParse(data.DeviceId, out Guid deviceGuid))
                {
                    var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                    await badReq.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Hiányzik az eszköz." });
                    return badReq;
                }

                if (string.IsNullOrWhiteSpace(data.PassToken))
                {
                    var notFoundRes = req.CreateResponse(HttpStatusCode.NotFound);
                    await notFoundRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "A belépő kód nem érvényes." });
                    return notFoundRes;
                }

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spJoinPlayerDevicePass]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@PassToken", data.PassToken.Trim());
                        cmd.Parameters.AddWithValue("@DeviceId", deviceGuid);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                string returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;

                                if (returnValue == 1)
                                {
                                    long eventId = Convert.ToInt64(reader["EventID"]);
                                    long eventUserId = Convert.ToInt64(reader["EventUserID"]);
                                    long userId = Convert.ToInt64(reader["UserID"]);
                                    string email = reader["Email"]?.ToString() ?? string.Empty;
                                    bool isSysadmin = Convert.ToBoolean(reader["IsSysadmin"]);
                                    bool checkedIn = Convert.ToBoolean(reader["CheckedIn"]);

                                    // Rendes belépő JWT generálása a játékos UserID-jához (30 napos lejárat)
                                    var tokenHandler = new JwtSecurityTokenHandler();
                                    var key = Encoding.ASCII.GetBytes(_jwtSecret);
                                    var claims = new List<Claim>
                                    {
                                        new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                                        new Claim(ClaimTypes.Email, email)
                                    };
                                    if (isSysadmin) claims.Add(new Claim("sysadmin", "true"));

                                    var tokenDescriptor = new SecurityTokenDescriptor
                                    {
                                        Subject = new ClaimsIdentity(claims),
                                        Expires = DateTime.UtcNow.AddDays(30),
                                        SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                                    };
                                    var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                                    var okRes = req.CreateResponse(HttpStatusCode.OK);
                                    await okRes.WriteAsJsonAsync(new
                                    {
                                        ReturnValue = 1,
                                        ReturnDescription = returnDescription,
                                        Token = jwtToken,
                                        EventID = eventId,
                                        EventUserID = eventUserId,
                                        CheckedIn = checkedIn
                                    });
                                    return okRes;
                                }

                                HttpStatusCode statusCode = returnValue switch
                                {
                                    400 => HttpStatusCode.BadRequest,
                                    404 => HttpStatusCode.NotFound,
                                    409 => HttpStatusCode.Conflict,
                                    _ => HttpStatusCode.BadRequest
                                };

                                var errRes = req.CreateResponse(statusCode);
                                await errRes.WriteAsJsonAsync(new
                                {
                                    ReturnValue = -1,
                                    ReturnDescription = returnDescription
                                });
                                return errRes;
                            }
                        }
                    }
                }

                var fallbackErr = req.CreateResponse(HttpStatusCode.InternalServerError);
                await fallbackErr.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Váratlan hiba történt a csatlakozáskor." });
                return fallbackErr;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "PlayerDeviceJoin error");
                var errRes = req.CreateResponse(HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }
    }
}
