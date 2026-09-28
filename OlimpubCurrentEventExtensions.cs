using System;
using System.IO;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Mvc;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api.Endpoints
{
    public static class OlimpubCurrentEventExtensions
    {
        [Function("GetOlimpubCurrentEvent")]
        public static async Task<HttpResponseData> GetCurrentEvent([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "op/current")] HttpRequestData req, FunctionContext executionContext)
        {
            var logger = executionContext.GetLogger("OlimpubCurrentEventExtensions");
            string connectionString = Environment.GetEnvironmentVariable("SqlConnectionString") ?? "";
            
            try
            {
                using (var conn = new SqlConnection(connectionString))
                {
                    await conn.OpenAsync();
                    using (var cmd = new SqlCommand(@"
                        SELECT TOP 1 e.id AS EventID, e.EventUID, e.EventName AS Title,
                        CASE WHEN (s.StatusName LIKE '%bejelentkez%' OR s.StatusName LIKE '%játék%' OR s.StatusName LIKE '%jatek%') THEN 1 ELSE 0 END AS JoinOpen
                        FROM [OP].[tblEventSettings] op
                        JOIN [EJ].[tblEvent] e ON e.id = op.EventID
                        JOIN [EJ].[tblEventStatus] s ON e.EventStatusID = s.id
                        JOIN [EJ].[tblEventType] et ON e.EventTypeID = et.id
                        WHERE op.CurrentFlg = 1 AND e.ActiveFlg = 1 AND et.OPFlg = 1
                    ", conn))
                    {
                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                var res = req.CreateResponse(System.Net.HttpStatusCode.OK);
                                await res.WriteAsJsonAsync(new {
                                    ReturnValue = 1,
                                    EventID = reader["EventID"],
                                    EventUID = reader["EventUID"],
                                    Title = reader["Title"],
                                    JoinOpen = Convert.ToBoolean(reader["JoinOpen"])
                                });
                                return res;
                            }
                            else
                            {
                                // Nincs aktuális esemény -> mostantól ez 200 OK, hogy ne törje a frontend interceptorokat
                                var res = req.CreateResponse(System.Net.HttpStatusCode.OK);
                                await res.WriteAsJsonAsync(new { 
                                    ReturnValue = 0, 
                                    ReturnDescription = "Nincs aktuális Olimpub esemény.",
                                    EventID = (int?)null
                                });
                                return res;
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                logger.LogError(ex, "GetOlimpubCurrentEvent error");
                var errRes = req.CreateResponse(System.Net.HttpStatusCode.InternalServerError);
                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = "Belső szerverhiba történt." });
                return errRes;
            }
        }
    }
}
