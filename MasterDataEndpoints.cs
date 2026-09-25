using System;
using System.Collections.Generic;
using System.Linq;
using System.Net;
using System.Threading.Tasks;
using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Http;
using Microsoft.Extensions.Logging;
using Microsoft.Data.SqlClient;

namespace EventJoy.Api
{
    public class MasterDataEndpoints
    {
        private readonly ILogger _logger;
        private readonly string _connectionString;

        public MasterDataEndpoints(ILoggerFactory loggerFactory)
        {
            _logger = loggerFactory.CreateLogger<MasterDataEndpoints>();
            _connectionString = Environment.GetEnvironmentVariable("SqlConnectionString")
                ?? throw new InvalidOperationException("SqlConnectionString app setting is missing.");
        }

        private async Task<List<Dictionary<string, object?>>> ReadResultSetAsync(SqlDataReader reader)
        {
            var list = new List<Dictionary<string, object?>>();
            while (await reader.ReadAsync())
            {
                var row = new Dictionary<string, object?>();
                for (int i = 0; i < reader.FieldCount; i++)
                {
                    row[reader.GetName(i)] = reader.IsDBNull(i) ? null : reader.GetValue(i);
                }
                list.Add(row);
            }
            return list;
        }

        [Function("GetMasterData")]
        public async Task<HttpResponseData> GetMasterData([HttpTrigger(AuthorizationLevel.Anonymous, "get", Route = "master/data")] HttpRequestData req)
        {
            // A MasterData lehet anonim vagy védett is. Általában publikus, vagy elég egy alap JWT validáció.
            // Ebben az architektúrában a Store hívja meg bejelentkezés után, szóval lehetne JWT védett is, 
            // de törzsadatok esetén opcionális lehet. Hagyjuk anonimnak, de lekérjük az adatokat.
            
            try
            {
                using (var conn = new SqlConnection(_connectionString))
                {
                    await conn.OpenAsync();

                    using (var cmd = new SqlCommand("[EJ].[spGetMasterData]", conn))
                    {
                        cmd.CommandType = System.Data.CommandType.StoredProcedure;

                        int returnValue = 0;
                        string returnDescription = string.Empty;

                        using (var reader = await cmd.ExecuteReaderAsync())
                        {
                            if (await reader.ReadAsync())
                            {
                                returnValue = Convert.ToInt32(reader["ReturnValue"]);
                                returnDescription = reader["ReturnDescription"]?.ToString() ?? string.Empty;
                            }

                            if (returnValue != 1)
                            {
                                var errRes = req.CreateResponse(HttpStatusCode.BadRequest);
                                await errRes.WriteAsJsonAsync(new { ReturnValue = -1, ReturnDescription = returnDescription });
                                return errRes;
                            }

                            var dynamicResults = new Dictionary<string, object?>();

                            // 2. RS: ResultList (a nevek listája)
                            var resultNames = new List<string>();
                            if (await reader.NextResultAsync())
                            {
                                while (await reader.ReadAsync())
                                {
                                    // Biztonságos beolvasás: ha van 2 oszlop, akkor az 1-es indexű, ha csak 1, akkor a 0-ás.
                                    // Ez kivédi, ha az SSMS-ből kimásolt "1" valójában csak sorszám volt, nem adatbázis oszlop.
                                    var rsName = reader.FieldCount > 1 ? reader.GetValue(1)?.ToString() : reader.GetValue(0)?.ToString();
                                    if (!string.IsNullOrEmpty(rsName))
                                    {
                                        resultNames.Add(rsName);
                                    }
                                }
                            }

                            // A további result set-ek beolvasása a kapott nevek alapján
                            int nameIndex = 0;
                            // Ha a nevek listája tartalmazza a "ReturnStatus"-t, akkor az első kettőt (ReturnStatus, ResultList) már beolvastuk!
                            if (resultNames.Count > 0 && resultNames[0].Equals("ReturnStatus", StringComparison.OrdinalIgnoreCase))
                            {
                                nameIndex = 2;
                            }

                            while (await reader.NextResultAsync())
                            {
                                var rsData = await ReadResultSetAsync(reader);
                                
                                string currentName;
                                if (nameIndex < resultNames.Count)
                                {
                                    currentName = resultNames[nameIndex];
                                }
                                else
                                {
                                    currentName = $"ExtraResultSet_{nameIndex + 1}";
                                }

                                // Ha a név "DataVersion", akkor csak az első sort (vagy null-t) adjuk vissza a kompatibilitás miatt
                                if (currentName.Equals("DataVersion", StringComparison.OrdinalIgnoreCase))
                                {
                                    dynamicResults[currentName] = rsData.FirstOrDefault();
                                }
                                else
                                {
                                    dynamicResults[currentName] = rsData;
                                }

                                nameIndex++;
                            }

                            var response = req.CreateResponse(HttpStatusCode.OK);
                            await response.WriteAsJsonAsync(dynamicResults);
                            
                            return response;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error fetching master data.");
                return req.CreateResponse(HttpStatusCode.InternalServerError);
            }
        }
    }
}
