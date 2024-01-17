using CompanyXyz.DependencySample.Library1;

namespace CompanyXyz.DependencySample.Worker;

public class Worker(ILogger<Worker> logger, TimeProvider timeProvider, Class1 class1) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        while (!stoppingToken.IsCancellationRequested)
        {
            if (logger.IsEnabled(LogLevel.Information))
            {
                logger.LogInformation(class1.GetMessage(), timeProvider.GetLocalNow());
            }
            await Task.Delay(1000, stoppingToken);
        }
    }
}
