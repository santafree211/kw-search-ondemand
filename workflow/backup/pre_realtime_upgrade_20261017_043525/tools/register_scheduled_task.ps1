<#
.SYNOPSIS
    tools/register_scheduled_task.ps1
    Responsibility: Register or unregister Windows Task Scheduler job for automated daily kw-serch execution.
    Usage:
      # Register daily task at 09:15 JST (default):
      powershell -ExecutionPolicy Bypass -File tools\register_scheduled_task.ps1 -Action Register

      # Register custom time (e.g. 09:30):
      powershell -ExecutionPolicy Bypass -File tools\register_scheduled_task.ps1 -Action Register -DailyTime "09:30"

      # Check task status:
      powershell -ExecutionPolicy Bypass -File tools\register_scheduled_task.ps1 -Action Status

      # Run task immediately:
      powershell -ExecutionPolicy Bypass -File tools\register_scheduled_task.ps1 -Action RunNow

      # Unregister task:
      powershell -ExecutionPolicy Bypass -File tools\register_scheduled_task.ps1 -Action Unregister
    Implementation: Pure ASCII for full PowerShell 5.1 compatibility.
#>

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("Register", "Unregister", "Status", "RunNow")]
    [string]$Action = "Register",

    [Parameter(Mandatory=$false)]
    [string]$TaskName = "KwSearch_Daily_Autonomous_Pipeline",

    [Parameter(Mandatory=$false)]
    [string]$DailyTime = "09:15"
)

$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$batchPath = Join-Path $projectRoot "run_daily.bat"

Write-Output "=========================================================="
Write-Output "=== KW-SEARCH TASK SCHEDULER MANAGEMENT UTILITY ==="
Write-Output "=========================================================="
Write-Output "Action    : $Action"
Write-Output "Task Name : $TaskName"
Write-Output "Target Cmd: $batchPath --no-pause"

switch ($Action) {
    "Register" {
        Write-Output "Registering daily task to trigger at $DailyTime daily..."
        $actionObj = New-ScheduledTaskAction -Execute "cmd.exe" -Argument "/c `"$batchPath`" --no-pause" -WorkingDirectory $projectRoot
        $triggerObj = New-ScheduledTaskTrigger -Daily -At ([datetime]::ParseExact($DailyTime, "HH:mm", $null))
        $settingsObj = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 6)
        
        try {
            # Unregister first if existing
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue | Out-Null
        } catch {}

        Register-ScheduledTask -TaskName $TaskName -Action $actionObj -Trigger $triggerObj -Settings $settingsObj -Description "Autonomous 50-genre keyword research, SERP verification, sheet sync, and audit." | Out-Null
        Write-Output ">>> [SUCCESS] Task '$TaskName' registered successfully! It will trigger every day at $DailyTime."
        
        # Display registered task info
        Get-ScheduledTask -TaskName $TaskName | Select-Object TaskName, State
    }

    "Unregister" {
        Write-Output "Unregistering task '$TaskName'..."
        try {
            Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
            Write-Output ">>> [SUCCESS] Task '$TaskName' removed successfully."
        } catch {
            Write-Output "Task was not found or could not be unregistered: $_"
        }
    }

    "Status" {
        $task = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
        if ($task) {
            $taskInfo = Get-ScheduledTaskInfo -TaskName $TaskName -ErrorAction SilentlyContinue
            Write-Output "Task Name    : $($task.TaskName)"
            Write-Output "State        : $($task.State)"
            if ($taskInfo) {
                Write-Output "Last Run Time: $($taskInfo.LastRunTime)"
                Write-Output "Last Result  : $($taskInfo.LastTaskResult)"
                Write-Output "Next Run Time: $($taskInfo.NextRunTime)"
            }
        } else {
            Write-Output "Task '$TaskName' is currently NOT registered."
        }
    }

    "RunNow" {
        Write-Output "Triggering task '$TaskName' immediately..."
        Start-ScheduledTask -TaskName $TaskName
        Write-Output ">>> [SUCCESS] Task '$TaskName' started in background."
    }
}
