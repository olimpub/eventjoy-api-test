using System;
using System.Collections.Concurrent;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Data.SqlClient;
using Microsoft.Extensions.Logging;
using Newtonsoft.Json;

namespace EventJoy.Api.Logging
{
    public class DatabaseLoggerProvider : ILoggerProvider
    {
        private readonly string _connectionString;
        private readonly ConcurrentQueue<LogEntry> _logQueue = new();
        private readonly Timer _timer;
        private bool _isDisposed;

        public DatabaseLoggerProvider(string connectionString)
        {
            _connectionString = connectionString;
            _timer = new Timer(ProcessQueue, null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
        }

        public ILogger CreateLogger(string categoryName)
        {
            return new DatabaseLogger(categoryName, this);
        }

        public void EnqueueLog(LogEntry entry)
        {
            if (!_isDisposed)
                _logQueue.Enqueue(entry);
        }

        private void ProcessQueue(object? state)
        {
            if (_logQueue.IsEmpty) return;
            _ = ProcessQueueAsync();
        }

        private async Task ProcessQueueAsync()
        {
            var logsToProcess = new System.Collections.Generic.List<LogEntry>();
            while (_logQueue.TryDequeue(out var log))
            {
                logsToProcess.Add(log);
            }

            if (logsToProcess.Count == 0) return;

            try
            {
                using var conn = new SqlConnection(_connectionString);
                await conn.OpenAsync();
                
                foreach (var log in logsToProcess)
                {
                    using var cmd = new SqlCommand(@"
                        INSERT INTO [LOG].[tblErrorLog] (Source, Severity, ErrorMessage, StackTrace, ContextPayload_JSON, CreatedAt) 
                        VALUES (@Source, @Severity, @ErrorMessage, @StackTrace, @ContextPayload, SYSDATETIMEOFFSET())", conn);
                    
                    // Replace Function categories with friendly names
                    string source = log.Category;
                    if (source.StartsWith("Function.")) source = source.Replace("Function.", "API.");

                    cmd.Parameters.AddWithValue("@Source", source);
                    cmd.Parameters.AddWithValue("@Severity", log.LogLevel.ToString());
                    cmd.Parameters.AddWithValue("@ErrorMessage", log.Message);
                    cmd.Parameters.AddWithValue("@StackTrace", log.Exception?.StackTrace ?? (object)DBNull.Value);
                    
                    var payload = new {
                        ExceptionType = log.Exception?.GetType().Name,
                        OriginalCategory = log.Category
                    };
                    cmd.Parameters.AddWithValue("@ContextPayload", JsonConvert.SerializeObject(payload));
                    
                    await cmd.ExecuteNonQueryAsync();
                }
            }
            catch 
            {
                // Végtelen ciklus elkerülése, ha maga a logolás hal meg
            }
        }

        public void Dispose()
        {
            _isDisposed = true;
            _timer?.Dispose();
            ProcessQueueAsync().GetAwaiter().GetResult();
        }
    }

    public class DatabaseLogger : ILogger
    {
        private readonly string _categoryName;
        private readonly DatabaseLoggerProvider _provider;

        public DatabaseLogger(string categoryName, DatabaseLoggerProvider provider)
        {
            _categoryName = categoryName;
            _provider = provider;
        }

        public IDisposable? BeginScope<TState>(TState state) where TState : notnull => null;

        public bool IsEnabled(LogLevel logLevel) => logLevel >= LogLevel.Error;

        public void Log<TState>(LogLevel logLevel, EventId eventId, TState state, Exception? exception, Func<TState, Exception?, string> formatter)
        {
            if (!IsEnabled(logLevel)) return;

            if (_categoryName.StartsWith("Microsoft.Data.SqlClient") || _categoryName.StartsWith("System.Data")) return;
            if (exception != null && exception.GetType().Name.Contains("SqlException")) return;

            var message = formatter(state, exception);
            _provider.EnqueueLog(new LogEntry
            {
                Category = _categoryName,
                LogLevel = logLevel,
                Message = message,
                Exception = exception
            });
        }
    }

    public class LogEntry
    {
        public string Category { get; set; } = "";
        public LogLevel LogLevel { get; set; }
        public string Message { get; set; } = "";
        public Exception? Exception { get; set; }
    }
}
