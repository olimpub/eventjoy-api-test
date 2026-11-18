using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using Azure.Messaging.ServiceBus;

namespace EventJoy.Api
{
    public static class SignalRManagementHelper
    {
        private static readonly HttpClient _httpClient = new HttpClient { Timeout = TimeSpan.FromSeconds(4) };
        private static readonly ConcurrentDictionary<long, DateTime> _lastConnectionsPingUtc = new ConcurrentDictionary<long, DateTime>();

        private static bool TryParseConnectionString(out string endpoint, out string accessKey)
        {
            endpoint = string.Empty;
            accessKey = string.Empty;
            string connStr = Environment.GetEnvironmentVariable("AzureSignalRConnectionString") ?? string.Empty;
            if (string.IsNullOrWhiteSpace(connStr)) return false;

            foreach (var part in connStr.Split(';', StringSplitOptions.RemoveEmptyEntries))
            {
                var kv = part.Split('=', 2);
                if (kv.Length == 2)
                {
                    var key = kv[0].Trim();
                    var val = kv[1].Trim();
                    if (key.Equals("Endpoint", StringComparison.OrdinalIgnoreCase)) endpoint = val.TrimEnd('/');
                    else if (key.Equals("AccessKey", StringComparison.OrdinalIgnoreCase)) accessKey = val;
                }
            }
            return !string.IsNullOrEmpty(endpoint) && !string.IsNullOrEmpty(accessKey);
        }

        private static string GenerateRestJwt(string audience, string accessKey)
        {
            string headerB64 = Base64UrlEncode(Encoding.UTF8.GetBytes("{\"alg\":\"HS256\",\"typ\":\"JWT\"}"));
            long exp = DateTimeOffset.UtcNow.AddMinutes(5).ToUnixTimeSeconds();
            string payloadJson = JsonSerializer.Serialize(new { aud = audience, exp = exp });
            string payloadB64 = Base64UrlEncode(Encoding.UTF8.GetBytes(payloadJson));
            string unsignedToken = $"{headerB64}.{payloadB64}";

            using var hmac = new HMACSHA256(Encoding.UTF8.GetBytes(accessKey));
            string sigB64 = Base64UrlEncode(hmac.ComputeHash(Encoding.UTF8.GetBytes(unsignedToken)));
            return $"{unsignedToken}.{sigB64}";
        }

        private static string Base64UrlEncode(byte[] bytes)
        {
            return Convert.ToBase64String(bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_');
        }

        public static async Task<bool> IsConnectionAliveAsync(string connectionId)
        {
            if (string.IsNullOrWhiteSpace(connectionId)) return false;
            if (!TryParseConnectionString(out string endpoint, out string accessKey)) return true;

            try
            {
                string url = $"{endpoint}/api/v1/hubs/eventHub/connections/{Uri.EscapeDataString(connectionId)}";
                string token = GenerateRestJwt(url, accessKey);

                using var req = new HttpRequestMessage(HttpMethod.Head, url);
                req.Headers.Authorization = new AuthenticationHeaderValue("Bearer", token);
                using var res = await _httpClient.SendAsync(req);
                if (res.StatusCode == HttpStatusCode.NotFound) return false;
                return res.IsSuccessStatusCode;
            }
            catch
            {
                return true;
            }
        }

        public static async Task RemoveAndCloseDisplayConnectionAsync(long eventId, string connectionId)
        {
            if (string.IsNullOrWhiteSpace(connectionId)) return;
            if (!TryParseConnectionString(out string endpoint, out string accessKey)) return;

            string groupName = $"event_{eventId}_display";

            try
            {
                string groupUrl = $"{endpoint}/api/v1/hubs/eventHub/groups/{Uri.EscapeDataString(groupName)}/connections/{Uri.EscapeDataString(connectionId)}";
                string groupToken = GenerateRestJwt(groupUrl, accessKey);
                using var groupReq = new HttpRequestMessage(HttpMethod.Delete, groupUrl);
                groupReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", groupToken);
                using var groupRes = await _httpClient.SendAsync(groupReq);
            }
            catch { }

            try
            {
                string connBaseUrl = $"{endpoint}/api/v1/hubs/eventHub/connections/{Uri.EscapeDataString(connectionId)}";
                string connUrl = $"{connBaseUrl}?reason=DisplayDisconnected";
                string connToken = GenerateRestJwt(connBaseUrl, accessKey);
                using var connReq = new HttpRequestMessage(HttpMethod.Delete, connUrl);
                connReq.Headers.Authorization = new AuthenticationHeaderValue("Bearer", connToken);
                using var connRes = await _httpClient.SendAsync(connReq);
            }
            catch { }
        }

        public static bool ShouldEmitConnectionsChanged(long eventId)
        {
            var now = DateTime.UtcNow;
            while (true)
            {
                if (_lastConnectionsPingUtc.TryGetValue(eventId, out var lastUtc))
                {
                    if ((now - lastUtc).TotalMilliseconds < 1000)
                    {
                        return false;
                    }
                    if (_lastConnectionsPingUtc.TryUpdate(eventId, now, lastUtc))
                    {
                        return true;
                    }
                }
                else
                {
                    if (_lastConnectionsPingUtc.TryAdd(eventId, now))
                    {
                        return true;
                    }
                }
            }
        }

        public static async Task TryPublishConnectionsChangedAsync(ServiceBusClient? serviceBusClient, long eventId, long stateVersion = 0)
        {
            if (serviceBusClient == null || !ShouldEmitConnectionsChanged(eventId)) return;

            try
            {
                await using var sender = serviceBusClient.CreateSender(Environment.GetEnvironmentVariable("CommunicationTopic") ?? "communication");
                var pingPayload = new
                {
                    Action = "Op.ConnectionsChanged",
                    EventID = eventId,
                    StateVersion = stateVersion,
                    Payload = new
                    {
                        EventID = eventId,
                        StateVersion = stateVersion
                    }
                };

                var groups = new[]
                {
                    $"event_{eventId}_gamemaster",
                    $"event_{eventId}_organizer"
                };

                var messages = new List<ServiceBusMessage>();
                foreach (var tg in groups)
                {
                    var sbPayload = new
                    {
                        TargetGroup = tg,
                        EventName = "Op.ConnectionsChanged",
                        PayloadJson = pingPayload
                    };
                    var msg = new ServiceBusMessage(JsonSerializer.Serialize(sbPayload))
                    {
                        MessageId = Guid.NewGuid().ToString()
                    };
                    msg.ApplicationProperties["channel"] = "signalr";
                    messages.Add(msg);
                }

                await sender.SendMessagesAsync(messages);
            }
            catch { }
        }
    }
}
