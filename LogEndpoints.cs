using System;
using System.IO;
using System.Net;
using System.Security.Claims;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace EventJoy.Api
{
    public class LogEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;

        public LogEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<LogEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") ?? "";
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "";
        }

        public class FrontendErrorLogDto
        {
            public string Source { get; set; } = "Frontend";
            public string Severity { get; set; } = "Error";
            public string UrlOrAction { get; set; }
            public string ErrorMessage { get; set; }
            public string StackTrace { get; set; }
            public object ContextPayload { get; set; }
            public object ClientInfo { get; set; }
        }

        [Function("PostFrontendError")]
        public async Task<HttpResponseData> PostFrontendError(
            [HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "logs/error")] HttpRequestData req)
        {
            try
            {
                string requestBody = await new StreamReader(req.Body).ReadToEndAsync();
                var data = JsonConvert.DeserializeObject<FrontendErrorLogDto>(requestBody);
                if (data == null || string.IsNullOrEmpty(data.ErrorMessage))
                    return req.CreateResponse(HttpStatusCode.BadRequest);

                var principal = JwtValidator.ValidateTokenAndGetPrincipal(req, _jwtSecret);
                long? userId = null;
                if (principal != null)
                {
                    var userIdClaim = principal.FindFirst(ClaimTypes.NameIdentifier);
                    if (userIdClaim != null && long.TryParse(userIdClaim.Value, out long uid)) userId = uid;
                }

                var contextCombined = new
                {
                    Context = data.ContextPayload,
                    Client = data.ClientInfo
                };

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("INSERT INTO [LOG].[tblErrorLog] (UserID, Source, Severity, UrlOrAction, ErrorMessage, StackTrace, ContextPayload_JSON, CreatedAt) VALUES (@UserID, @Source, @Severity, @UrlOrAction, @ErrorMessage, @StackTrace, @ContextPayload, SYSDATETIMEOFFSET())", conn))
                    {
                        cmd.Parameters.AddWithValue("@UserID", userId.HasValue ? userId.Value : DBNull.Value);
                        cmd.Parameters.AddWithValue("@Source", data.Source ?? "Frontend");
                        cmd.Parameters.AddWithValue("@Severity", data.Severity ?? "Error");
                        cmd.Parameters.AddWithValue("@UrlOrAction", data.UrlOrAction ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@ErrorMessage", data.ErrorMessage);
                        cmd.Parameters.AddWithValue("@StackTrace", data.StackTrace ?? (object)DBNull.Value);
                        cmd.Parameters.AddWithValue("@ContextPayload", JsonConvert.SerializeObject(contextCombined));

                        await cmd.ExecuteNonQueryAsync();
                    }
                }
                return req.CreateResponse(HttpStatusCode.OK);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to save frontend error log.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
