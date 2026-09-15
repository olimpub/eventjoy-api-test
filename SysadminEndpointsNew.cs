using System;
using System.Collections.Generic;
using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Security.Claims;
using System.Text;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Microsoft.IdentityModel.Tokens;

namespace EventJoy.Api
{
    public class SysadminEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public SysadminEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<SysadminEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret")
                ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
        }

        [Function("ImpersonateUser")]
        public async Task<HttpResponseData> ImpersonateUser(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "sysadmin/users/{userId:long}/impersonate")] HttpRequestData req,
            long userId)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                long targetUserId = 0;
                string email = "";

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminGetImpersonationData]", conn) { CommandType = System.Data.CommandType.StoredProcedure })
                    {
                        cmd.Parameters.AddWithValue("@UserId", userId);
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                targetUserId = reader.GetInt32(reader.GetOrdinal("Id"));
                                email = reader.IsDBNull(reader.GetOrdinal("EmailAddress")) ? "" : reader.GetString(reader.GetOrdinal("EmailAddress"));
                            }
                            else return req.CreateResponse(HttpStatusCode.NotFound);
                        }
                    }
                }

                var tokenHandler = new JwtSecurityTokenHandler();
                var key = Encoding.ASCII.GetBytes(_jwtSecret);
                
                var claims = new List<Claim>
                {
                    new Claim(ClaimTypes.NameIdentifier, targetUserId.ToString()),
                    new Claim(ClaimTypes.Email, email)
                };

                var tokenDescriptor = new SecurityTokenDescriptor
                {
                    Subject = new ClaimsIdentity(claims),
                    Expires = DateTime.UtcNow.AddHours(2), 
                    SigningCredentials = new SigningCredentials(new SymmetricSecurityKey(key), SecurityAlgorithms.HmacSha256Signature)
                };
                
                var jwtToken = tokenHandler.WriteToken(tokenHandler.CreateToken(tokenDescriptor));

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new
                {
                    Token = jwtToken,
                    Message = $"Sikeres belépés {email} ({targetUserId}) nevében."
                });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error in ImpersonateUser");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetSysadminDashboard")]
        public async Task<HttpResponseData> GetSysadminDashboard(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/dashboard")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            int? days = null;
            if (int.TryParse(query["days"], out int parsedDays)) days = parsedDays;

            try
            {
                var metrics = new Dictionary<string, object>();
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[LOG].[spGetSysadminDashboardMetrics]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        if (days.HasValue) cmd.Parameters.AddWithValue("@Days", days.Value);
                        else cmd.Parameters.AddWithValue("@Days", DBNull.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                for (int i = 0; i < reader.FieldCount; i++) metrics[reader.GetName(i)] = reader.GetValue(i);
                            }
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(metrics);
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching dashboard metrics");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetUsers")]
        public async Task<HttpResponseData> GetUsers(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/users")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            string? searchTerm = query["search"];
            int skip = int.TryParse(query["skip"], out int s) ? s : 0;
            int take = int.TryParse(query["take"], out int t) ? t : 50;

            try
            {
                var users = new List<Dictionary<string, object>>();
                int totalCount = 0;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminGetUsers]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@SearchTerm", string.IsNullOrEmpty(searchTerm) ? DBNull.Value : searchTerm);
                        cmd.Parameters.AddWithValue("@Skip", skip);
                        cmd.Parameters.AddWithValue("@Take", take);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                var user = new Dictionary<string, object>();
                                for (int i = 0; i < reader.FieldCount; i++) user[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                users.Add(user);
                            }
                            if (await reader.NextResultAsync() && await reader.ReadAsync())
                                totalCount = reader.GetInt32(0);
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Data = users, TotalCount = totalCount });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching users");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        public class UpdateUserDto
        {
            public string? FirstName { get; set; }
            public string? LastName { get; set; }
            public int StatusID { get; set; }
            public bool IsSysadmin { get; set; }
        }

        [Function("UpdateUser")]
        public async Task<HttpResponseData> UpdateUser(
            [HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "sysadmin/users/{userId:long}")] HttpRequestData req,
            long userId)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);
            
            var adminUserIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier);
            if (adminUserIdClaim == null || !long.TryParse(adminUserIdClaim.Value, out long adminUserId)) return req.CreateResponse(HttpStatusCode.Forbidden);

            string body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
            var data = System.Text.Json.JsonSerializer.Deserialize<UpdateUserDto>(body, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (data == null) return req.CreateResponse(HttpStatusCode.BadRequest);

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminUpdateUser]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@TargetUserID", userId);
                        cmd.Parameters.AddWithValue("@FirstName", data.FirstName ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@LastName", data.LastName ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@StatusID", data.StatusID);
                        cmd.Parameters.AddWithValue("@IsSysadmin", data.IsSysadmin);
                        cmd.Parameters.AddWithValue("@SysadminUserID", adminUserId);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                                if (returnVal == 1) return req.CreateResponse(HttpStatusCode.OK);
                            }
                        }
                    }
                }
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating user");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("ForceLogoutUser")]
        public async Task<HttpResponseData> ForceLogoutUser(
            [HttpTrigger(AuthorizationLevel.Anonymous, "delete", Route = "sysadmin/users/{userId:long}/tokens")] HttpRequestData req,
            long userId)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminForceLogoutUser]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@TargetUserID", userId);
                        await cmd.ExecuteNonQueryAsync();
                    }
                }
                return req.CreateResponse(HttpStatusCode.OK);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error force logout user");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetErrorLogs")]
        public async Task<HttpResponseData> GetErrorLogs(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/logs/error")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            
            if (string.IsNullOrEmpty(query["from"]) || string.IsNullOrEmpty(query["to"]))
            {
                var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Missing 'from' or 'to' query parameters.");
                return badReq;
            }

            if (!DateTime.TryParse(query["from"], null, System.Globalization.DateTimeStyles.RoundtripKind, out DateTime fromDate)) fromDate = DateTime.MinValue;
            if (!DateTime.TryParse(query["to"], null, System.Globalization.DateTimeStyles.RoundtripKind, out DateTime toDate)) toDate = DateTime.MaxValue;
            
            string? source = query["source"];
            string? searchTerm = query["search"];
            long? userId = long.TryParse(query["userId"], out long u) ? u : null;
            int skip = int.TryParse(query["skip"], out int s) ? s : 0;
            int take = int.TryParse(query["take"], out int t) ? t : 50;

            try
            {
                var logs = new List<Dictionary<string, object>>();
                int totalCount = 0;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[LOG].[spSysadminGetErrorLogs]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@From", fromDate);
                        cmd.Parameters.AddWithValue("@To", toDate);
                        cmd.Parameters.AddWithValue("@Source", string.IsNullOrEmpty(source) ? DBNull.Value : source);
                        cmd.Parameters.AddWithValue("@SearchTerm", string.IsNullOrEmpty(searchTerm) ? DBNull.Value : searchTerm);
                        cmd.Parameters.AddWithValue("@UserID", userId.HasValue ? userId.Value : DBNull.Value);
                        cmd.Parameters.AddWithValue("@Skip", skip);
                        cmd.Parameters.AddWithValue("@Take", take);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                var log = new Dictionary<string, object>();
                                for (int i = 0; i < reader.FieldCount; i++) log[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                logs.Add(log);
                            }
                            if (await reader.NextResultAsync() && await reader.ReadAsync()) totalCount = reader.GetInt32(0);
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Data = logs, TotalCount = totalCount });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching error logs");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetDataChangeLogs")]
        public async Task<HttpResponseData> GetDataChangeLogs(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/logs/data-change")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            
            if (string.IsNullOrEmpty(query["from"]) || string.IsNullOrEmpty(query["to"]))
            {
                var badReq = req.CreateResponse(HttpStatusCode.BadRequest);
                await badReq.WriteStringAsync("Missing 'from' or 'to' query parameters.");
                return badReq;
            }

            if (!DateTime.TryParse(query["from"], null, System.Globalization.DateTimeStyles.RoundtripKind, out DateTime fromDate)) fromDate = DateTime.MinValue;
            if (!DateTime.TryParse(query["to"], null, System.Globalization.DateTimeStyles.RoundtripKind, out DateTime toDate)) toDate = DateTime.MaxValue;

            string? tableName = query["tableName"];
            long? userId = long.TryParse(query["userId"], out long u) ? u : null;
            int skip = int.TryParse(query["skip"], out int s) ? s : 0;
            int take = int.TryParse(query["take"], out int t) ? t : 50;

            try
            {
                var logs = new List<Dictionary<string, object>>();
                int totalCount = 0;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[LOG].[spSysadminGetDataChangeLogs]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@From", fromDate);
                        cmd.Parameters.AddWithValue("@To", toDate);
                        cmd.Parameters.AddWithValue("@TableName", string.IsNullOrEmpty(tableName) ? DBNull.Value : tableName);
                        cmd.Parameters.AddWithValue("@UserID", userId.HasValue ? userId.Value : DBNull.Value);
                        cmd.Parameters.AddWithValue("@Skip", skip);
                        cmd.Parameters.AddWithValue("@Take", take);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                var log = new Dictionary<string, object>();
                                for (int i = 0; i < reader.FieldCount; i++) log[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                logs.Add(log);
                            }
                            if (await reader.NextResultAsync() && await reader.ReadAsync()) totalCount = reader.GetInt32(0);
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Data = logs, TotalCount = totalCount });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching data change logs");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetSysadminTickets")]
        public async Task<HttpResponseData> GetSysadminTickets(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/tickets")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            var query = System.Web.HttpUtility.ParseQueryString(req.Url.Query);
            int? statusId = int.TryParse(query["statusId"], out int st) ? st : null;
            int skip = int.TryParse(query["skip"], out int s) ? s : 0;
            int take = int.TryParse(query["take"], out int t) ? t : 50;

            try
            {
                var tickets = new List<Dictionary<string, object>>();
                int totalCount = 0;

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminGetTickets]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@StatusID", statusId.HasValue ? statusId.Value : DBNull.Value);
                        cmd.Parameters.AddWithValue("@Skip", skip);
                        cmd.Parameters.AddWithValue("@Take", take);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                var ticket = new Dictionary<string, object>();
                                for (int i = 0; i < reader.FieldCount; i++) ticket[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                tickets.Add(ticket);
                            }
                            if (await reader.NextResultAsync() && await reader.ReadAsync()) totalCount = reader.GetInt32(0);
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Data = tickets, TotalCount = totalCount });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching tickets");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        public class UpdateTicketStatusDto
        {
            public int StatusID { get; set; }
            public int? TargetVersionID { get; set; }
        }

        [Function("UpdateSysadminTicketStatus")]
        public async Task<HttpResponseData> UpdateSysadminTicketStatus(
            [HttpTrigger(AuthorizationLevel.Anonymous, "put", Route = "sysadmin/tickets/{ticketId:long}/status")] HttpRequestData req,
            long ticketId)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);
            
            var adminUserIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier);
            if (adminUserIdClaim == null || !long.TryParse(adminUserIdClaim.Value, out long adminUserId)) return req.CreateResponse(HttpStatusCode.Forbidden);

            string body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
            var data = System.Text.Json.JsonSerializer.Deserialize<UpdateTicketStatusDto>(body, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (data == null) return req.CreateResponse(HttpStatusCode.BadRequest);

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminUpdateTicketStatus]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@TicketID", ticketId);
                        cmd.Parameters.AddWithValue("@StatusID", data.StatusID);
                        cmd.Parameters.AddWithValue("@UserID", adminUserId);
                        cmd.Parameters.AddWithValue("@TargetVersionID", data.TargetVersionID.HasValue ? (object)data.TargetVersionID.Value : DBNull.Value);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                                if (returnVal == 1) return req.CreateResponse(HttpStatusCode.OK);
                            }
                        }
                    }
                }
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error updating ticket status");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetSysadminDictionaries")]
        public async Task<HttpResponseData> GetSysadminDictionaries(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/dictionaries")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                var tables = new List<Dictionary<string, object>>();
                var fields = new List<Dictionary<string, object>>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[LOG].[spSysadminGetDictionaries]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                var row = new Dictionary<string, object>();
                                for (int i = 0; i < reader.FieldCount; i++) row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                tables.Add(row);
                            }
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var row = new Dictionary<string, object>();
                                    for (int i = 0; i < reader.FieldCount; i++) row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                    fields.Add(row);
                                }
                            }
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Tables = tables, Fields = fields });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching dictionaries");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetSysadminTicketDetails")]
        public async Task<HttpResponseData> GetSysadminTicketDetails(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/tickets/{ticketId:long}")] HttpRequestData req,
            long ticketId)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                var ticket = new Dictionary<string, object>();
                var comments = new List<Dictionary<string, object>>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminGetTicketDetails]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@TicketID", ticketId);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                for (int i = 0; i < reader.FieldCount; i++) ticket[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                            }
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var comment = new Dictionary<string, object>();
                                    for (int i = 0; i < reader.FieldCount; i++) comment[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                    comments.Add(comment);
                                }
                            }
                        }
                    }
                }
                if (ticket.Count == 0) return req.CreateResponse(HttpStatusCode.NotFound);

                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Ticket = ticket, Comments = comments });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching ticket details");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        public class PostSysadminTicketCommentDto
        {
            public string? CommentText { get; set; }
        }

        [Function("PostSysadminTicketComment")]
        public async Task<HttpResponseData> PostSysadminTicketComment(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "sysadmin/tickets/{ticketId:long}/comments")] HttpRequestData req,
            long ticketId)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);
            
            var adminUserIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier);
            if (adminUserIdClaim == null || !long.TryParse(adminUserIdClaim.Value, out long adminUserId)) return req.CreateResponse(HttpStatusCode.Forbidden);

            string body = await new System.IO.StreamReader(req.Body).ReadToEndAsync();
            var data = System.Text.Json.JsonSerializer.Deserialize<PostSysadminTicketCommentDto>(body, new System.Text.Json.JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            if (data == null || string.IsNullOrWhiteSpace(data.CommentText)) return req.CreateResponse(HttpStatusCode.BadRequest);

            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminPostTicketComment]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@TicketID", ticketId);
                        cmd.Parameters.AddWithValue("@UserID", adminUserId);
                        cmd.Parameters.AddWithValue("@CommentText", data.CommentText);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                int returnVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                                if (returnVal == 1) return req.CreateResponse(HttpStatusCode.OK);
                            }
                        }
                    }
                }
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error posting ticket comment");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }

        [Function("GetSysadminTicketMasterData")]
        public async Task<HttpResponseData> GetSysadminTicketMasterData(
            [HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "sysadmin/tickets/masterdata")] HttpRequestData req)
        {
            var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
            if (principal == null || !JwtValidator.IsSysadmin(principal)) return req.CreateResponse(HttpStatusCode.Forbidden);

            try
            {
                var statuses = new List<Dictionary<string, object>>();
                var flows = new List<Dictionary<string, object>>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spSysadminGetTicketMasterData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            while (await reader.ReadAsync())
                            {
                                var row = new Dictionary<string, object>();
                                for (int i = 0; i < reader.FieldCount; i++) row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                statuses.Add(row);
                            }
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    var row = new Dictionary<string, object>();
                                    for (int i = 0; i < reader.FieldCount; i++) row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                                    flows.Add(row);
                                }
                            }
                        }
                    }
                }
                var res = req.CreateResponse(HttpStatusCode.OK);
                await res.WriteAsJsonAsync(new { Statuses = statuses, Flows = flows });
                return res;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching ticket masterdata");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
