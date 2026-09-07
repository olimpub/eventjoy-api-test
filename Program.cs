using Microsoft.Azure.Functions.Worker;
using Microsoft.Azure.Functions.Worker.Builder;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Azure.Messaging.ServiceBus;
using System;

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

builder.Build().Run();
