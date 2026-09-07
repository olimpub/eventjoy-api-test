using System;
using System.Collections.Generic;
using System.Linq;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class EmailRouterFunction
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly HttpClient _httpClient;
        
        // Cseréld ki a saját MailerSend tokenedre (vagy tedd local.settings.json-be)
        private readonly string _mailerSendToken = Environment.GetEnvironmentVariable("MailerSendToken") ?? "API_TOKEN_HERE";

        public EmailRouterFunction(ILoggerFactory loggerFactory, IHttpClientFactory httpClientFactory)
        {
            _logger = loggerFactory.CreateLogger<EmailRouterFunction>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString missing.");
            _httpClient = httpClientFactory.CreateClient();
        }

        [Function("EmailRouterFunction")]
        public async Task Run(
            [ServiceBusTrigger("communication", "email", Connection = "ServiceBusConnection")] string mySbMsg)
        {
            _logger.LogInformation($"C# ServiceBus trigger processing message: {mySbMsg}");

            try
            {
                var payload = JsonSerializer.Deserialize<OutboxMessagePayload>(mySbMsg, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
                
                if (payload == null || payload.MailId == Guid.Empty)
                {
                    _logger.LogWarning("Invalid payload. Missing MailID (UID).");
                    return;
                }

                var mailId = payload.MailId;
                
                var headers = new List<EmailHeaderDto>();
                var parameters = new List<EmailParamDto>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spGetEmailData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@UID", mailId);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            // RS1: ReturnStatus
                            if (await reader.ReadAsync())
                            {
                                int returnValue = reader.IsDBNull(0) ? 0 : reader.GetInt32(0);
                                if (returnValue != 1)
                                {
                                    _logger.LogWarning($"spGetEmailData returned error for UID {mailId}.");
                                    return;
                                }
                            }

                            // RS2: ResultList
                            if (!await reader.NextResultAsync()) return;
                            
                            // Skipeljük a ResultList sorait, nem létfontosságú a C# feldolgozáshoz
                            while (await reader.ReadAsync()) { }

                            // RS3: EmailHeaders
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    headers.Add(new EmailHeaderDto
                                    {
                                        EmailID = Convert.ToInt64(reader.GetValue(reader.GetOrdinal("EmailID"))),
                                        BatchID = reader.GetGuid(reader.GetOrdinal("BatchID")),
                                        SenderMail = reader.GetString(reader.GetOrdinal("SenderMail")),
                                        RecipientName = reader.IsDBNull(reader.GetOrdinal("RecipientName")) ? null : reader.GetString(reader.GetOrdinal("RecipientName")),
                                        RecipientEmail = reader.GetString(reader.GetOrdinal("RecipientEmail")),
                                        MsgSubject = reader.IsDBNull(reader.GetOrdinal("MsgSubject")) ? null : reader.GetString(reader.GetOrdinal("MsgSubject")),
                                        TemplateID = reader.GetString(reader.GetOrdinal("TemplateID")),
                                        ReplyToMail = reader.IsDBNull(reader.GetOrdinal("ReplyToMail")) ? null : reader.GetString(reader.GetOrdinal("ReplyToMail")),
                                        ReplyToName = reader.IsDBNull(reader.GetOrdinal("ReplyToName")) ? null : reader.GetString(reader.GetOrdinal("ReplyToName"))
                                    });
                                }
                            }

                            // RS4: EmailParams
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    parameters.Add(new EmailParamDto
                                    {
                                        EmailID = Convert.ToInt64(reader.GetValue(reader.GetOrdinal("EmailID"))),
                                        ParamName = reader.GetString(reader.GetOrdinal("ParamName")),
                                        ParamValue = reader.IsDBNull(reader.GetOrdinal("ParamValue")) ? null : reader.GetString(reader.GetOrdinal("ParamValue"))
                                    });
                                }
                            }
                        }
                    }
                }

                if (!headers.Any())
                {
                    _logger.LogInformation($"No emails found for batch UID {mailId}");
                    return;
                }

                // Chunking by 500 as per MailerSend limits
                int chunkSize = 500;
                for (int i = 0; i < headers.Count; i += chunkSize)
                {
                    var chunkHeaders = headers.Skip(i).Take(chunkSize).ToList();
                    string? bulkEmailId = await SendBulkToMailerSendAsync(chunkHeaders, parameters);
                    
                    if (!string.IsNullOrEmpty(bulkEmailId))
                    {
                        using (var conn = new SqlConnection(_connectionString))
                        {
                            await conn.OpenAsync();
                            using (var updateCmd = new SqlCommand("[EJ].[spUpdateEmailOutboxStatus]", conn))
                            {
                                updateCmd.CommandType = System.Data.CommandType.StoredProcedure;
                                updateCmd.Parameters.AddWithValue("@UID", mailId);
                                updateCmd.Parameters.AddWithValue("@MailerSendID", bulkEmailId);
                                updateCmd.Parameters.AddWithValue("@StatusID", 2); // 2 = Sent To MailerSend
                                await updateCmd.ExecuteNonQueryAsync();
                            }
                        }
                    }

                    // Opcionális delay a 15 request / minute limit miatt, ha több ezer email van
                    if (headers.Count > chunkSize && (i + chunkSize) < headers.Count)
                    {
                        await Task.Delay(4000); // 4 másodperc késleltetés chunkok között
                    }
                }

                _logger.LogInformation($"Successfully processed MailID {mailId}. Total emails sent: {headers.Count}.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing Email Service Bus message.");
                throw; // Újrapróbálkozás a Service Bus által
            }
        }

        private async Task<string?> SendBulkToMailerSendAsync(List<EmailHeaderDto> headers, List<EmailParamDto> parameters)
        {
            // A MailerSend /v1/bulk-email végpontja egy tömböt vár, amiben külön üzenet objektumok vannak
            var bulkPayload = new List<object>();

            foreach (var header in headers)
            {
                // Kikeressük az ehhez az EmailID-hoz tartozó paramétereket
                var emailParams = parameters.Where(p => p.EmailID == header.EmailID).ToList();
                var variablesDictionary = new Dictionary<string, string>();
                foreach (var p in emailParams)
                {
                    if (p.ParamValue != null)
                    {
                        variablesDictionary[p.ParamName] = p.ParamValue;
                    }
                }

                var emailObject = new
                {
                    from = new { email = header.SenderMail, name = "EventJoy" },
                    to = new[] { 
                        new { 
                            email = header.RecipientEmail, 
                            name = header.RecipientName ?? string.Empty 
                        } 
                    },
                    subject = header.MsgSubject,
                    template_id = header.TemplateID,
                    variables = variablesDictionary.Any() ? new[]
                    {
                        new {
                            email = header.RecipientEmail,
                            substitutions = variablesDictionary.Select(kv => new { var = kv.Key, value = kv.Value }).ToArray()
                        }
                    } : null
                };

                bulkPayload.Add(emailObject);
            }

            var jsonContent = new StringContent(JsonSerializer.Serialize(bulkPayload), Encoding.UTF8, "application/json");

            _httpClient.DefaultRequestHeaders.Clear();
            _httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_mailerSendToken}");

            var response = await _httpClient.PostAsync("https://api.mailersend.com/v1/bulk-email", jsonContent);

            if (!response.IsSuccessStatusCode)
            {
                var errorBody = await response.Content.ReadAsStringAsync();
                _logger.LogError($"MailerSend Bulk API error: {response.StatusCode} - {errorBody}");
                throw new Exception($"MailerSend error: {response.StatusCode}");
            }

            var successBody = await response.Content.ReadAsStringAsync();
            try
            {
                var jsonResponse = JsonDocument.Parse(successBody);
                if (jsonResponse.RootElement.TryGetProperty("bulk_email_id", out JsonElement idElement))
                {
                    return idElement.GetString();
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse bulk_email_id from MailerSend response.");
            }
            
            return null;
        }
    }

    public class OutboxMessagePayload
    {
        public Guid MailId { get; set; }
    }

    public class EmailHeaderDto
    {
        public long EmailID { get; set; }
        public Guid BatchID { get; set; }
        public string SenderMail { get; set; } = string.Empty;
        public string? RecipientName { get; set; }
        public string RecipientEmail { get; set; } = string.Empty;
        public string? MsgSubject { get; set; }
        public string TemplateID { get; set; } = string.Empty;
        public string? ReplyToMail { get; set; }
        public string? ReplyToName { get; set; }
    }

    public class EmailParamDto
    {
        public long EmailID { get; set; }
        public string ParamName { get; set; } = string.Empty;
        public string? ParamValue { get; set; }
    }
}
