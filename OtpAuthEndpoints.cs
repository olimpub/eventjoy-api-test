using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Data.SqlClient;
using System.Text;
using JsonSerializer = System.Text.Json.JsonSerializer;
using JsonSerializerOptions = System.Text.Json.JsonSerializerOptions;
using System.Security.Claims;
using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;
using System.Security.Cryptography;
using System.Collections.Generic;
using BCrypt.Net;

namespace EventJoy.Api
{
    public class OtpAuthEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";

        public OtpAuthEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<OtpAuthEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
        }

        // =========================================================================
        // 0. AZONOSÍTÓ ELLENŐRZÉSE (Létezik-e, van-e jelszava?)
        // =========================================================================
        [Function("PostCheckIdentity")]
        public async Task<HttpResponseData> CheckIdentity([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/check-identity")] HttpRequestData req)
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var data = JsonConvert.DeserializeObject<CheckIdentityDto>(requestBody);

            if (string.IsNullOrEmpty(data?.IdentityValue))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Identity (Email/Phone) required.");
                return badReq;
            }

            Dictionary<string, object?>? result1 = null;
            Dictionary<string, object?>? result2 = null;

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spCheckIdentity]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@IdentityValue", data.IdentityValue);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                result1 = ReadCurrentRow(reader);
                            }

                            if (await reader.NextResultAsync() && await reader.ReadAsync())
                            {
                                result2 = ReadCurrentRow(reader);
                            }
                        }
                    }
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    Result1 = result1 ?? new Dictionary<string, object?>(),
                    Result2 = result2 ?? new Dictionary<string, object?>()
                });
                return response;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Check Email Error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }

        // =========================================================================
        // 1.5. JELSZAVAS BELÉPÉS
        // =========================================================================
        [Function("PostPasswordLogin")]
        public async Task<HttpResponseData> PasswordLogin([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/password-login")] HttpRequestData req)
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var data = JsonConvert.DeserializeObject<PasswordLoginDto>(requestBody);

            if (data == null || string.IsNullOrEmpty(data.IdentityValue) || string.IsNullOrEmpty(data.Password))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Identity and Password required.");
                return badReq;
            }

            Dictionary<string, object?>? result1 = null;
            Dictionary<string, object?>? result2 = null;

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spGetAuthData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@IdentityValue", data.IdentityValue);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync()) result1 = ReadCurrentRow(reader);
                            if (await reader.NextResultAsync() && await reader.ReadAsync()) result2 = ReadCurrentRow(reader);
                        }
                    }

                    int? returnValue = TryGetInt(result1 ?? new Dictionary<string, object?>(), "ReturnValue");
                    if (returnValue != 1 || result2 == null)
                    {
                        var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                        await unauthRes.WriteAsJsonAsync(new { Result1 = result1 });
                        return unauthRes;
                    }

                    string dbHash = result2.ContainsKey("PasswordHash") && result2["PasswordHash"] != null ? result2["PasswordHash"]!.ToString()! : "";
                    
                    // BCrypt ellenőrzés
                    bool isValidPassword = false;
                    try 
                    {
                        isValidPassword = BCrypt.Net.BCrypt.Verify(data.Password, dbHash);
                    }
                    catch 
                    {
                        // Ha a hash formátum hibás
                    }

                    if (!isValidPassword)
                    {
                        var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                        await unauthRes.WriteAsJsonAsync(new { Result1 = new { ReturnValue = -1, ReturnDescription = "Hibás jelszó!" } });
                        return unauthRes;
                    }

                    // JWT Generálás
                    int userId = TryGetInt(result2, "UserID") ?? 0;
                    string email = result2.ContainsKey("EmailAddress") && result2["EmailAddress"] != null ? result2["EmailAddress"]!.ToString()! : "";
                    
                    var tokenHandler = new JwtSecurityTokenHandler();
                    var key = Encoding.ASCII.GetBytes(_jwtSecret);
                    var tokenDescriptor = new SecurityTokenDescriptor
                    {
                        Subject = new ClaimsIdentity(new[]
                        {
                            new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                            new Claim(ClaimTypes.Email, email)
                        }),
                        Expires = DateTime.UtcNow.AddDays(30), 
                        SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                    };
                    var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                    // Refresh token mentése
                    string refreshToken = GenerateRefreshToken();
                    string refreshTokenHash = ComputeSha256Hash(refreshToken);
                    DateTime expiresAt = DateTime.UtcNow.AddDays(30);

                    using (var saveConn = new SqlConnection(_connectionString))
                    {
                        await saveConn.OpenAsync();
                        using (var saveCmd = new SqlCommand("[EJ].[spSaveRefreshToken]", saveConn))
                        {
                            saveCmd.CommandType = System.Data.CommandType.StoredProcedure;
                            saveCmd.Parameters.AddWithValue("@UserId", userId);
                            saveCmd.Parameters.AddWithValue("@TokenHash", refreshTokenHash);
                            saveCmd.Parameters.AddWithValue("@DeviceId", string.IsNullOrEmpty(data.DeviceId) ? "unknown_device" : data.DeviceId);
                            saveCmd.Parameters.AddWithValue("@DeviceName", string.IsNullOrEmpty(data.DeviceName) ? "Web App" : data.DeviceName);
                            saveCmd.Parameters.AddWithValue("@ExpiresAt", expiresAt);
                            await saveCmd.ExecuteNonQueryAsync();
                        }
                    }

                    // Ne küldjük vissza a jelszó hash-t a frontendnek!
                    result2.Remove("PasswordHash");

                    var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                    await response.WriteAsJsonAsync(new
                    {
                        Result1 = result1,
                        Result2 = new
                        {
                            Token = jwtToken,
                            RefreshToken = refreshToken,
                            User = result2
                        }
                    });
                    return response;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Password Login Error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }

        // =========================================================================
        // 1.6. REGISZTRÁCIÓ (Jelszóval)
        // =========================================================================
        [Function("PostRegister")]
        public async Task<HttpResponseData> Register([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/register")] HttpRequestData req)
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var data = JsonConvert.DeserializeObject<RegisterDto>(requestBody);

            if (data == null || string.IsNullOrEmpty(data.IdentityValue) || string.IsNullOrEmpty(data.Password))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Identity and Password required.");
                return badReq;
            }

            Dictionary<string, object?>? result1 = null;
            Dictionary<string, object?>? result2 = null;

            try
            {
                // BCrypt titkosítás a mentés előtt
                string passwordHash = BCrypt.Net.BCrypt.HashPassword(data.Password);
                bool isEmail = data.IdentityValue.Contains("@");
                string? email = isEmail ? data.IdentityValue : null;
                string? phone = isEmail ? null : data.IdentityValue;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spRegisterUser]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EmailAddress", email ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@PhoneNumber", phone ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@PasswordHash", passwordHash);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync()) result1 = ReadCurrentRow(reader);
                            if (await reader.NextResultAsync() && await reader.ReadAsync()) result2 = ReadCurrentRow(reader);
                        }
                    }

                    int? returnValue = TryGetInt(result1 ?? new Dictionary<string, object?>(), "ReturnValue");
                    if (returnValue != 1 || result2 == null)
                    {
                        var errorRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                        await errorRes.WriteAsJsonAsync(new { Result1 = result1 });
                        return errorRes;
                    }

                    // JWT Generálás (automatikus beléptetés regisztráció után)
                    int userId = TryGetInt(result2, "UserID") ?? 0;
                    
                    var tokenHandler = new JwtSecurityTokenHandler();
                    var key = Encoding.ASCII.GetBytes(_jwtSecret);
                    var tokenDescriptor = new SecurityTokenDescriptor
                    {
                        Subject = new ClaimsIdentity(new[]
                        {
                            new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                            new Claim(ClaimTypes.Email, email ?? "")
                        }),
                        Expires = DateTime.UtcNow.AddDays(30), 
                        SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                    };
                    var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                    // Refresh token mentése
                    string refreshToken = GenerateRefreshToken();
                    string refreshTokenHash = ComputeSha256Hash(refreshToken);
                    DateTime expiresAt = DateTime.UtcNow.AddDays(30);

                    using (var saveConn = new SqlConnection(_connectionString))
                    {
                        await saveConn.OpenAsync();
                        using (var saveCmd = new SqlCommand("[EJ].[spSaveRefreshToken]", saveConn))
                        {
                            saveCmd.CommandType = System.Data.CommandType.StoredProcedure;
                            saveCmd.Parameters.AddWithValue("@UserId", userId);
                            saveCmd.Parameters.AddWithValue("@TokenHash", refreshTokenHash);
                            saveCmd.Parameters.AddWithValue("@DeviceId", string.IsNullOrEmpty(data.DeviceId) ? "unknown_device" : data.DeviceId);
                            saveCmd.Parameters.AddWithValue("@DeviceName", string.IsNullOrEmpty(data.DeviceName) ? "Web App" : data.DeviceName);
                            saveCmd.Parameters.AddWithValue("@ExpiresAt", expiresAt);
                            await saveCmd.ExecuteNonQueryAsync();
                        }
                    }

                    var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                    await response.WriteAsJsonAsync(new
                    {
                        Result1 = result1,
                        Result2 = new
                        {
                            Token = jwtToken,
                            RefreshToken = refreshToken,
                            User = result2
                        }
                    });
                    return response;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Register Error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }

        // =========================================================================
        // 1. KÓD KÉRÉSE
        // =========================================================================
        [Function("PostRequestOTP")]
        public async Task<HttpResponseData> RequestOtp([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/request-otp")] HttpRequestData req)
        {
            _logger.LogInformation("Request OTP Endpoint hit.");

            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var data = JsonConvert.DeserializeObject<OtpRequestDto>(requestBody);

            if (string.IsNullOrEmpty(data?.EmailAddress) && string.IsNullOrEmpty(data?.PhoneNumber))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Email or Phone required.");
                return badReq;
            }

            int? returnValue = null;
            Dictionary<string, object?>? result1 = null;
            Dictionary<string, object?>? result2 = null;

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spRequestOTP]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EmailAddress", data.EmailAddress ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@PhoneNumber", data.PhoneNumber ?? (object)DBNull.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                result1 = ReadCurrentRow(reader);
                                returnValue = TryGetInt(result1, "ReturnValue");
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                                await errRes.WriteAsJsonAsync(new
                                {
                                    Result1 = result1 ?? new Dictionary<string, object?>(),
                                    Result2 = result2 ?? new Dictionary<string, object?>()
                                });
                                return errRes;
                            }

                            bool hasSecondResult = await reader.NextResultAsync();
                            if (!hasSecondResult)
                            {
                                _logger.LogWarning("spRequestOTP has no second result set.");
                            }

                            if (hasSecondResult && await reader.ReadAsync())
                            {
                                result2 = ReadCurrentRow(reader);
                            }
                            else if (hasSecondResult)
                            {
                                _logger.LogWarning("spRequestOTP second result set exists but returned no rows.");
                            }
                        }
                    }
                }

                if (result1 != null && result1.TryGetValue("MailID", out var mailIdObj) && mailIdObj != null)
                {
                    if (Guid.TryParse(mailIdObj.ToString(), out Guid mailId))
                    {
                        var sbConnString = Environment.GetEnvironmentVariable("ServiceBusConnection");
                        if (!string.IsNullOrEmpty(sbConnString))
                        {
                            await using var client = new Azure.Messaging.ServiceBus.ServiceBusClient(sbConnString);
                            await using var sender = client.CreateSender("communication");
                            var payload = new { MailId = mailId };
                            var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage(System.Text.Json.JsonSerializer.Serialize(payload))
                            {
                                MessageId = mailId.ToString()
                            };
                            sbMessage.ApplicationProperties["channel"] = "email";
                            await sender.SendMessageAsync(sbMessage);
                            _logger.LogInformation($"Successfully published MailID {mailId} to ServiceBus.");
                        }
                        else
                        {
                            _logger.LogWarning("ServiceBusConnection is missing. Could not publish MailID.");
                        }
                    }
                }

                var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                await response.WriteAsJsonAsync(new
                {
                    Result1 = result1 ?? new Dictionary<string, object?>(),
                    Result2 = result2 ?? new Dictionary<string, object?>()
                });
                return response;

            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Request OTP Error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }


        // =========================================================================
        // 2. KÓD ELLENŐRZÉSE
        // =========================================================================
        [Function("PostVerifyOTP")]
        public async Task<HttpResponseData> VerifyOtp([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/verify-otp")] HttpRequestData req)
        {
            string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var data = JsonConvert.DeserializeObject<OtpVerifyDto>(requestBody);

            if (data == null || string.IsNullOrEmpty(data.IdentityValue) || string.IsNullOrEmpty(data.ValidationCode))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("IdentityValue and ValidationCode required.");
                return badReq;
            }

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    
                    int returnValue = 0;
                    string returnDescription = string.Empty;
                    UserDto? user = null;
                    Dictionary<string, object?>? result1 = null;
                    Dictionary<string, object?>? result2 = null;

                    using (var cmd = new SqlCommand("[EJ].[spVerifyOTP]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@IdentityValue", data.IdentityValue);
                        cmd.Parameters.AddWithValue("@ValidationCode", data.ValidationCode);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                result1 = ReadCurrentRow(reader);
                                returnValue = TryGetInt(result1, "ReturnValue") ?? 0;
                                returnDescription = result1.TryGetValue("ReturnDescription", out var desc)
                                    ? desc?.ToString() ?? string.Empty
                                    : string.Empty;
                            }

                            if (returnValue != 1)
                            {
                                var unauthRes = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                                await unauthRes.WriteAsJsonAsync(new
                                {
                                    Message = returnDescription,
                                    Result1 = result1 ?? new Dictionary<string, object?>(),
                                    Result2 = result2 ?? new Dictionary<string, object?>()
                                });
                                return unauthRes;
                            }

                            if (await reader.NextResultAsync() && await reader.ReadAsync())
                            {
                                result2 = ReadCurrentRow(reader);
                                user = new UserDto
                                {
                                    Id = TryGetInt(result2, "UserID") ?? 0,
                                    Email = result2.TryGetValue("EmailAddress", out var email) ? email?.ToString() : null,
                                    FirstName = result2.TryGetValue("FirstName", out var firstName) ? firstName?.ToString() : null,
                                    LastName = result2.TryGetValue("LastName", out var lastName) ? lastName?.ToString() : null
                                };
                            }
                        }
                    }

                    if (user == null)
                    {
                        var badRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                        await badRes.WriteAsJsonAsync(new
                        {
                            Message = "User record was not returned from spVerifyOTP.",
                            Result1 = result1 ?? new Dictionary<string, object?>(),
                            Result2 = result2 ?? new Dictionary<string, object?>()
                        });
                        return badRes;
                    }

                    var tokenHandler = new JwtSecurityTokenHandler();
                    var key = Encoding.ASCII.GetBytes(_jwtSecret);
                    var tokenDescriptor = new SecurityTokenDescriptor
                    {
                        Subject = new ClaimsIdentity(new[]
                        {
                            new Claim(ClaimTypes.NameIdentifier, user.Id.ToString()),
                            new Claim(ClaimTypes.Email, user.Email ?? "")
                        }),
                        Expires = DateTime.UtcNow.AddDays(30), 
                        SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                    };
                    var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                    string refreshToken = GenerateRefreshToken();
                    string refreshTokenHash = ComputeSha256Hash(refreshToken);
                    DateTime expiresAt = DateTime.UtcNow.AddDays(30);

                    using (var saveCmd = new SqlCommand("[EJ].[spSaveRefreshToken]", conn))
                    {
                        saveCmd.CommandType = System.Data.CommandType.StoredProcedure;
                        saveCmd.Parameters.AddWithValue("@UserId", user.Id);
                        saveCmd.Parameters.AddWithValue("@TokenHash", refreshTokenHash);
                        saveCmd.Parameters.AddWithValue("@DeviceId", string.IsNullOrEmpty(data.DeviceId) ? "unknown_device" : data.DeviceId);
                        saveCmd.Parameters.AddWithValue("@DeviceName", string.IsNullOrEmpty(data.DeviceName) ? "Web App" : data.DeviceName);
                        saveCmd.Parameters.AddWithValue("@ExpiresAt", expiresAt);
                        await saveCmd.ExecuteNonQueryAsync();
                    }

                    var response = req.CreateResponse(System.Net.HttpStatusCode.OK);
                    await response.WriteAsJsonAsync(new
                    {
                        Result1 = result1 ?? new Dictionary<string, object?>(),
                        Result2 = new
                        {
                            Token = jwtToken,
                            RefreshToken = refreshToken,
                            User = user
                        }
                    });
                    return response;
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Verification Error");
                return req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
            }
        }

        [Function("PostSocialLogin")]
        public async Task<HttpResponseData> PostSocialLogin([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "auth/social-login")] HttpRequestData req)
        {
            var requestBody = await new StreamReader(req.Body).ReadToEndAsync();
            var data = JsonSerializer.Deserialize<SocialLoginRequest>(requestBody, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });

            if (string.IsNullOrEmpty(data?.Provider) || string.IsNullOrEmpty(data?.ProviderId))
            {
                var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Provider and ProviderId are required.");
                return badReq;
            }

            int? returnValue = null;
            Dictionary<string, object?>? result1 = null;
            Dictionary<string, object?>? result2 = null;
            var extraResultSets = new Dictionary<string, List<Dictionary<string, object?>>>();

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSocialLogin]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@Provider", data.Provider);
                        cmd.Parameters.AddWithValue("@ProviderId", data.ProviderId);
                        cmd.Parameters.AddWithValue("@EmailAddress", data.EmailAddress ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@FirstName", data.FirstName ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@LastName", data.LastName ?? (object)DBNull.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                result1 = ReadCurrentRow(reader);
                                returnValue = TryGetInt(result1, "ReturnValue");
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                                await errRes.WriteAsJsonAsync(new { Result1 = result1 ?? new Dictionary<string, object?>() });
                                return errRes;
                            }

                            bool hasMoreResults = await reader.NextResultAsync();
                            int extraResultSetIndex = 1;

                            while (hasMoreResults)
                            {
                                var rs = await ReadResultSetAsync(reader);
                                extraResultSets[$"ResultSet{extraResultSetIndex}"] = rs;
                                
                                // Kikeressük a User rekordot, ha még nincs meg (a UserID oszlop alapján)
                                if (result2 == null && rs.Count > 0 && rs[0].ContainsKey("UserID"))
                                {
                                    result2 = rs[0];
                                }

                                extraResultSetIndex++;
                                hasMoreResults = await reader.NextResultAsync();
                            }
                        }
                    }
                }

                if (result2 != null)
                {
                    int userId = TryGetInt(result2, "UserID") ?? 0;
                    string email = result2.ContainsKey("EmailAddress") ? result2["EmailAddress"]?.ToString() ?? "" : "";
                    
                    // JWT Generálás
                    var tokenHandler = new JwtSecurityTokenHandler();
                    var key = Encoding.ASCII.GetBytes(_jwtSecret);
                    var tokenDescriptor = new SecurityTokenDescriptor
                    {
                        Subject = new ClaimsIdentity(new[]
                        {
                            new Claim(ClaimTypes.NameIdentifier, userId.ToString()),
                            new Claim(ClaimTypes.Email, email)
                        }),
                        Expires = DateTime.UtcNow.AddDays(30), 
                        SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                    };
                    var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                    // Refresh token mentése
                    string refreshToken = GenerateRefreshToken();
                    string refreshTokenHash = ComputeSha256Hash(refreshToken);
                    DateTime expiresAt = DateTime.UtcNow.AddDays(30);

                    using (var saveConn = new SqlConnection(_connectionString))
                    {
                        await saveConn.OpenAsync();
                        using (var saveCmd = new SqlCommand("[EJ].[spSaveRefreshToken]", saveConn))
                        {
                            saveCmd.CommandType = System.Data.CommandType.StoredProcedure;
                            saveCmd.Parameters.AddWithValue("@UserId", userId);
                            saveCmd.Parameters.AddWithValue("@TokenHash", refreshTokenHash);
                            saveCmd.Parameters.AddWithValue("@DeviceId", string.IsNullOrEmpty(data.DeviceId) ? "unknown_device" : data.DeviceId);
                            saveCmd.Parameters.AddWithValue("@DeviceName", string.IsNullOrEmpty(data.DeviceName) ? "Web App" : data.DeviceName);
                            saveCmd.Parameters.AddWithValue("@ExpiresAt", expiresAt);
                            await saveCmd.ExecuteNonQueryAsync();
                        }
                    }

                    var okRes = req.CreateResponse(System.Net.HttpStatusCode.OK);
                    await okRes.WriteAsJsonAsync(new
                    {
                        Result1 = result1,
                        Result2 = new
                        {
                            Token = jwtToken,
                            RefreshToken = refreshToken,
                            User = result2
                        },
                        ExtraResultSets = extraResultSets
                    });
                    return okRes;
                }

                var unauth = req.CreateResponse(System.Net.HttpStatusCode.Unauthorized);
                await unauth.WriteAsJsonAsync(new { Result1 = result1 });
                return unauth;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in PostSocialLogin");
                var err = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await err.WriteStringAsync("Internal server error");
                return err;
            }
        }

        private static Dictionary<string, object?> ReadCurrentRow(SqlDataReader reader)
        {
            var row = new Dictionary<string, object?>(StringComparer.OrdinalIgnoreCase);
            for (int i = 0; i < reader.FieldCount; i++)
            {
                var key = reader.GetName(i);
                row[key] = reader.IsDBNull(i) ? null : reader.GetValue(i);
            }

            return row;
        }

        private static int? TryGetInt(IDictionary<string, object?> source, string key)
        {
            if (!source.TryGetValue(key, out var value) || value == null)
            {
                return null;
            }

            return Convert.ToInt32(value);
        }

        private async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(SqlDataReader reader)
        {
            var list = new List<Dictionary<string, object?>>();
            while (await reader.ReadAsync())
            {
                list.Add(ReadCurrentRow(reader));
            }
            return list;
        }

        private string GenerateRefreshToken()
        {
            var randomNumber = new byte[32];
            using (var rng = RandomNumberGenerator.Create())
            {
                rng.GetBytes(randomNumber);
                return Convert.ToBase64String(randomNumber);
            }
        }

        private string ComputeSha256Hash(string rawData)
        {
            using (SHA256 sha256Hash = SHA256.Create())
            {
                byte[] bytes = sha256Hash.ComputeHash(Encoding.UTF8.GetBytes(rawData));
                var builder = new StringBuilder();
                foreach (byte b in bytes) builder.Append(b.ToString("x2"));
                return builder.ToString();
            }
        }

    }

    public class CheckIdentityDto { public string? IdentityValue { get; set; } }
    public class OtpRequestDto { public string? EmailAddress { get; set; } public string? PhoneNumber { get; set; } }
    public class OtpVerifyDto { public string? IdentityValue { get; set; } public string? ValidationCode { get; set; } public string? DeviceId { get; set; } public string? DeviceName { get; set; } }
    public class UserDto { public int Id { get; set; } public string? Email { get; set; } public string? FirstName { get; set; } public string? LastName { get; set; } }
    public class PasswordLoginDto { public string? IdentityValue { get; set; } public string? Password { get; set; } public string? DeviceId { get; set; } public string? DeviceName { get; set; } }
    public class RegisterDto { public string? IdentityValue { get; set; } public string? Password { get; set; } public string? DeviceId { get; set; } public string? DeviceName { get; set; } }
    public class PasswordLoginRequest
    {
        public string IdentityValue { get; set; } = string.Empty;
        public string Password { get; set; } = string.Empty;
        public string DeviceId { get; set; } = string.Empty;
        public string? DeviceName { get; set; }
    }

    public class SocialLoginRequest
    {
        public string Provider { get; set; } = string.Empty;
        public string ProviderId { get; set; } = string.Empty;
        public string? EmailAddress { get; set; }
        public string? FirstName { get; set; }
        public string? LastName { get; set; }
        public string DeviceId { get; set; } = string.Empty;
        public string? DeviceName { get; set; }
    }
}
