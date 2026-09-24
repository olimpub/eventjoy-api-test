using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.DependencyInjection;

namespace EventJoy.Api
{
    public class GameChangeDto
    {
        public long EventID { get; set; }
        public string Action { get; set; } = string.Empty;
        public object Payload { get; set; } = new object();
    }

    public class OlimpubGameEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;
        private readonly string _jwtSecret;
        private readonly Azure.Messaging.ServiceBus.ServiceBusClient? _serviceBusClient;

        public OlimpubGameEndpoints(ILoggerFactory loggerFactory, IServiceProvider serviceProvider)
        {
            _logger = loggerFactory.CreateLogger<OlimpubGameEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
            _jwtSecret = Environment.GetEnvironmentVariable("JwtSecret") ?? "eventjoy_nagyon_titkos_es_biztonsagos_256bit_kulcs_2026_!!";
            _serviceBusClient = serviceProvider.GetService<Azure.Messaging.ServiceBus.ServiceBusClient>();
        }

        [Function("OlimpubChangeGame")]
        public async Task<HttpResponseData> ChangeGame([HttpTrigger(AuthorizationLevel.Anonymous, "post", Route = "op/game/change")] HttpRequestData req)
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
                var data = JsonConvert.DeserializeObject<GameChangeDto>(requestBody);

                if (data == null || data.EventID <= 0 || string.IsNullOrEmpty(data.Action))
                {
                    var badReq = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                    await badReq.WriteStringAsync("Érvénytelen kérés: EventID és Action kötelező.");
                    return badReq;
                }

                int returnValue = -1;
                string returnDescription = "Ismeretlen hiba";

                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand("[OP].[spChangeGame]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;
                        cmd.Parameters.AddWithValue("@EventID", data.EventID);
                        cmd.Parameters.AddWithValue("@UserID", userId.Value);
                        cmd.Parameters.AddWithValue("@Action", data.Action);
                        cmd.Parameters.AddWithValue("@Json", requestBody);

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            // Első ResultSet: HTTP API Válasz
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                            }

                            // Második ResultSet: SignalR Service Bus Outbox!
                            if (returnValue == 1 && await reader.NextResultAsync())
                            {
                                if (_serviceBusClient != null)
                                {
                                    await using var sender = _serviceBusClient.CreateSender("communication");
                                    var messages = new System.Collections.Generic.List<Azure.Messaging.ServiceBus.ServiceBusMessage>();

                                    while (await reader.ReadAsync())
                                    {
                                        var targetGroup = reader["TargetGroup"]?.ToString();
                                        var eventName = reader["EventName"]?.ToString();
                                        var payloadJson = reader["PayloadJson"]?.ToString();

                                        if (!string.IsNullOrEmpty(targetGroup) && !string.IsNullOrEmpty(eventName) && !string.IsNullOrEmpty(payloadJson))
                                        {
                                            var sbPayload = new { TargetGroup = targetGroup, EventName = eventName, PayloadJson = System.Text.Json.JsonSerializer.Deserialize<object>(payloadJson) };
                                            var sbMessage = new Azure.Messaging.ServiceBus.ServiceBusMessage(System.Text.Json.JsonSerializer.Serialize(sbPayload))
                                            {
                                                MessageId = Guid.NewGuid().ToString()
                                            };
                                            sbMessage.ApplicationProperties["channel"] = "signalr";
                                            messages.Add(sbMessage);
                                        }
                                    }

                                    if (messages.Count > 0)
                                    {
                                        await sender.SendMessagesAsync(messages);
                                        _logger.LogInformation($"Successfully published {messages.Count} Olimpub SignalR messages to ServiceBus.");
                                    }
                                }
                                else
                                {
                                    _logger.LogWarning("ServiceBusClient is not configured. Real-time updates will not be sent.");
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
                    ReturnDescription = returnDescription
                });

                return response;
            }
            catch (SqlException ex)
            {
                _logger.LogError(ex, "Olimpub ChangeGame SQL error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.BadRequest);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = ex.Message });
                return errRes;
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Olimpub ChangeGame error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }
    }
}
