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

        [Function("EmailBatchSenderTimer")]
        public async Task Run([TimerTrigger("*/10 * * * * *")] TimerInfo myTimer)
        {
            try
            {
                var headers = new List<EmailHeaderDto>();
                var parameters = new List<EmailParamDto>();

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[EJ].[spGetPendingEmailsBulk]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (!await reader.ReadAsync()) return;
                            int retVal = reader.GetInt32(reader.GetOrdinal("ReturnValue"));
                            if (retVal != 1) return; // Nincs kiküldendő e-mail

                            // RS2: ResultList (Kihagyjuk)
                            await reader.NextResultAsync();

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
                        var emailIdsJson = JsonSerializer.Serialize(chunkHeaders.Select(h => h.EmailID).ToList());

                        using (var conn = new SqlConnection(_connectionString))
                        {
                            await conn.OpenAsync();
                            using (var updateCmd = new SqlCommand("[EJ].[spUpdateEmailOutboxStatusBulk]", conn))
                            {
                                updateCmd.CommandType = System.Data.CommandType.StoredProcedure;
                                updateCmd.Parameters.AddWithValue("@EmailIDsJSON", emailIdsJson);
                                updateCmd.Parameters.AddWithValue("@MailerSendID", bulkEmailId);
                                updateCmd.Parameters.AddWithValue("@StatusID", 2); // 2 = Sent To MailerSend
                                await updateCmd.ExecuteNonQueryAsync();
                            }
                        }
                    }

                    if (headers.Count > chunkSize && (i + chunkSize) < headers.Count)
                    {
                        await Task.Delay(4000); // 4 másodperc késleltetés chunkok között
                    }
                }

                _logger.LogInformation($"Successfully processed {headers.Count} emails in bulk timer.");
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error processing Email Batch Timer.");
            }
        }

        private async Task<string?> SendBulkToMailerSendAsync(List<EmailHeaderDto> headers, List<EmailParamDto> parameters)
        {
            var bulkPayload = new List<object>();

            foreach (var header in headers)
            {
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
                    to = string.IsNullOrEmpty(header.RecipientName) 
                        ? new object[] { new { email = header.RecipientEmail } } 
                        : new object[] { new { email = header.RecipientEmail, name = header.RecipientName } },
                    subject = header.MsgSubject,
                    template_id = header.TemplateID,
                    variables = variablesDictionary.Any() ? new[]
                    {
                        new {
                            email = header.RecipientEmail,
                            substitutions = variablesDictionary.Select(kv => new { var = kv.Key, value = kv.Value }).ToArray()
                        }
                    } : null,
                    personalization = variablesDictionary.Any() ? new[]
                    {
                        new {
                            email = header.RecipientEmail,
                            data = variablesDictionary
                        }
                    } : null
                };

                bulkPayload.Add(emailObject);
            }

            var jsonContent = new StringContent(JsonSerializer.Serialize(bulkPayload, new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull }), Encoding.UTF8, "application/json");

            _httpClient.DefaultRequestHeaders.Clear();
            _httpClient.DefaultRequestHeaders.Add("Authorization", $"Bearer {_mailerSendToken}");

            var response = await _httpClient.PostAsync("https://api.mailersend.com/v1/bulk-email", jsonContent);

            if (!response.IsSuccessStatusCode)
            {
                var errorBody = await response.Content.ReadAsStringAsync();
                _logger.LogError($"MailerSend Bulk API error: {response.StatusCode} - {errorBody}");
                throw new Exception($"MailerSend error: {response.StatusCode} - {errorBody}");
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
