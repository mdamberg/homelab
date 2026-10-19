# n8n Workflows

## Active Workflows

| File | Purpose | Target Table | Schedule |
|------|---------|--------------|----------|
| `media_library_collection.json` | Collects Plex/Sonarr/Radarr/Prowlarr stats | `raw_media_library` | Every 6 hours |
| `system_health_metrics.json` | Collects desktop CPU/memory/disk metrics | `raw_system_health` | Every 15 min |
| `hardware_sensors.json` | Collects temps, fans, voltages from LibreHardwareMonitor | `raw_hardware_sensors` | Every 5 min |
| `power_consumption.json` | Collects power consumption from Home Assistant | `raw_power_consumption` | Continuous |
| `workflow_run_tracker.json` | Logs ALL workflow executions | `raw_n8n_workflow_runs` | Every 1 hour |
| `error_catcher.json` | Catches and logs workflow failures | `raw_n8n_alerts` | On any error |

## Setup

1. Import each JSON file into n8n
2. Configure PostgreSQL credentials on database nodes
3. Configure Discord webhook URL (optional, for alerts)
4. Activate each workflow

### LibreHardwareMonitor autostart (Hardware Sensors workflow)

The workflow reads `http://host.docker.internal:8085/data.json` from LibreHardwareMonitor's
Remote Web Server. LHM's manifest is `requireAdministrator`, so launching it from the startup
script at boot raises a UAC prompt nobody answers, and LHM never starts (every run errors
until it is opened by hand). Instead, a Task Scheduler task starts it elevated at logon with
no prompt. Register it once from an **elevated** PowerShell:

```powershell
$exe = "$env:USERPROFILE\LibreHardwareMonitor\LibreHardwareMonitor\LibreHardwareMonitor.exe"
$user = "$env:USERDOMAIN\$env:USERNAME"
Register-ScheduledTask -TaskName "LibreHardwareMonitor" `
  -Action (New-ScheduledTaskAction -Execute $exe) `
  -Trigger (New-ScheduledTaskTrigger -AtLogOn -User $user) `
  -Principal (New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest) `
  -Settings (New-ScheduledTaskSettingsSet -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries)
```

`ExecutionTimeLimit` of zero means no limit; the default (72h) would kill LHM after three days.
`start-all-services.ps1 -StartLibreHardwareMonitor` still runs at login but skips LHM when it
is already running. Nothing runs until Windows login (see the Hello PIN note in reboot docs).

## Column Mappings

### raw_media_library
- `source` - plex, sonarr, radarr, prowlarr
- `media_type` - movie, tv_show, indexer
- `library_name` - Library or service name
- `item_count` - Number of items
- `total_size_bytes` - Storage used
- `recorded_at` - When data was captured
- `metadata` - Additional JSON details

### raw_system_health
- `hostname` - System hostname
- `cpu_percent` - CPU usage %
- `memory_percent` - RAM usage %
- `disk_percent` - C: drive usage %
- `recorded_at` - When captured
- `metadata` - Core count, uptime, etc.

### raw_hardware_sensors
- `hostname` - Computer name
- `sensor_type` - temperature, fan, voltage, power, load, clock
- `sensor_name` - CPU Core #1, GPU Temperature, etc.
- `sensor_id` - Unique sensor path
- `value` - Current reading
- `value_min` / `value_max` - Min/max observed
- `unit` - °C, RPM, V, W, %, MHz
- `hardware_name` - CPU/GPU model name
- `hardware_type` - CPU, GPU, Motherboard, Storage
- `recorded_at` - When captured

### raw_power_consumption
- `entity_id` - Home Assistant entity ID
- `friendly_name` - Sensor name
- `state` - Power reading value
- `unit_of_measurement` - W, kWh, etc.
- `recorded_at` - When captured
- `attributes` - Additional sensor attributes

### raw_n8n_workflow_runs
- `workflow_id` - n8n workflow ID
- `workflow_name` - Workflow name
- `source` - Trigger type (manual, schedule, webhook)
- `status` - success, error, running
- `started_at` - When execution started
- `finished_at` - When execution finished
- `metadata` - execution_id, mode, retry info

### raw_n8n_alerts
- `alert_type` - workflow_failure
- `severity` - error
- `source` - Failed workflow name
- `title` - Short description
- `message` - Error details
- `triggered_at` - When alert fired
- `metadata` - execution_id, error_stack, etc.

## Folders

- `n8n_data/` - Runtime data (do not modify)
- `_legacy/` - Old/unused workflows (safe to delete)
