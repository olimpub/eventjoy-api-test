using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.Messaging.ServiceBus;
using System;
using EventJoy.Api.Logging;
using Microsoft.Extensions.Logging;

var builder = FunctionsApplication.CreateBuilder(args);

builder.ConfigureFunctionsWebApplication();

var sbConnString = Environment.GetEnvironmentVariable("ServiceBusConnection");
if (!string.IsNullOrEmpty(sbConnString))
{
    builder.Services.AddSingleton(new ServiceBusClient(sbConnString));
}

builder.Services
    .AddApplicationInsightsTelemetryWorkerService()
    .ConfigureFunctionsApplicationInsights();

var sqlConnForLogging = Environment.GetEnvironmentVariable("SqlConnectionString");
if (!string.IsNullOrEmpty(sqlConnForLogging))
{
    builder.Services.AddLogging(loggingBuilder =>
    {
        loggingBuilder.AddProvider(new DatabaseLoggerProvider(sqlConnForLogging));
    });
}
builder.Build().Run();

