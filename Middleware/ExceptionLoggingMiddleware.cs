using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Middleware;
using Microsoft.Extensions.Configuration;
using Microsoft.Data.SqlClient;
using System;
using System.Threading.Tasks;

namespace EventJoy.Api.Middleware
{
    public class ExceptionLoggingMiddleware : IFunctionsWorkerMiddleware
    {
        private readonly string _sqlConnectionString;

        public ExceptionLoggingMiddleware(IConfiguration configuration)
        {
            _sqlConnectionString = configuration["SqlConnectionString"] ?? string.Empty;
        }

        public async Task Invoke(FunctionContext context, FunctionExecutionDelegate next)
        {
            try
            {
                await next(context);
            }
            catch (Exception ex)
            {
                // Hiba logolása az adatbázisba
                try
                {
                    using (var conn = new SqlConnection(_sqlConnectionString))
                    {
                        await conn.OpenAsync();
                        var cmd = new SqlCommand(@"
                            INSERT INTO [LOG].[tblErrorLog] (Source, Severity, UrlOrAction, ErrorMessage, StackTrace, CreatedAt)
                            VALUES ('Backend', 'Fatal', @UrlOrAction, @ErrorMessage, @StackTrace, SYSUTCDATETIME())", conn);
                        
                        cmd.Parameters.AddWithValue("@UrlOrAction", context.FunctionDefinition.Name);
                        cmd.Parameters.AddWithValue("@ErrorMessage", ex.Message);
                        cmd.Parameters.AddWithValue("@StackTrace", ex.StackTrace ?? (object)DBNull.Value);
                        
                        await cmd.ExecuteNonQueryAsync();
                    }
                }
                catch
                {
                    // Ha a logolás is elszáll (pl. nincs DB kapcsolat), akkor lenyeljük, hogy az eredeti hiba tovább menjen.
                }

                // Az eredeti kivétel továbbdobása a Function host felé
                throw;
            }
        }
    }
}
