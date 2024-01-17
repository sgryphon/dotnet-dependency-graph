using CompanyXyz.DependencySample.Library1;
using CompanyXyz.DependencySample.Worker;

var builder = Host.CreateApplicationBuilder(args);
builder.Services.AddHostedService<Worker>();
builder.Services.AddSingleton<Class1>();
builder.Services.AddSingleton(TimeProvider.System);

var host = builder.Build();
host.Run();
