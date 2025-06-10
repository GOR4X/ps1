try {
    # Check if the scheduled task exists
    $taskName = "SystemInfoWidget"
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

    if ($task) {
        # Task exists - return 0 for compliant
        Write-Host "Scheduled task '$taskName' exists."
        exit 0
    } else {
        # Task doesn't exist - return 1 for non-compliant
        Write-Host "Scheduled task '$taskName' does not exist."
        exit 1
    }
} catch {
    # Error occurred during check - return 1 for non-compliant
    Write-Host "Error checking for scheduled task: $_"
    exit 1
}