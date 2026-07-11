# Duplicati Backup + Ntfy Notifications Setup Guide

## Step 1: Access Duplicati Web Interface

Open your browser and go to: **http://localhost:8200** or **http://192.168.4.200:8200**

On first run, Duplicati will ask you to set a password. Choose a secure password and save it.

## Step 2: Create Backup Job

1. Click **"Add backup"** button
2. Choose **"Configure a new backup"**
3. Click **Next**

### General Settings
- **Name**: "Homelab Docker Configs Nightly Backup"
- **Description**: "Nightly backup of all Docker project configurations"
- **Encryption**: Choose "AES-256 encryption" and set a passphrase (SAVE THIS!)
- Click **Next**

### Destination
- **Storage Type**: Choose "Local folder or drive"
- **Path**: `/backups` (this maps to C:\backups on your host)
- Click **Next**

### Source Data
- Click **"Add path"**
- Select `/source/docker-configs` (this maps to C:\docker-projects on your host)
- You can exclude certain patterns if needed (e.g., `*/node_modules/*`, `*/.git/*`)
- Click **Next**

### Schedule
- **Automatically run backups**: Check this box
- **Run**: Choose "Daily"
- **Time**: Set to "1:00 AM" (or your preferred time)
- Click **Next**

### Options - IMPORTANT FOR NOTIFICATIONS

In the options screen, scroll down and click **"Edit as text"** to add these advanced options:

```
--send-http-url=https://ntfy.sh/YOUR_TOPIC_NAME
--send-http-message=Backup %OPERATIONNAME% completed: %PARSEDRESULT%
--send-http-level=Success,Warning,Error
--send-http-result-output-format=Json
```

**Replace `YOUR_TOPIC_NAME` with a unique topic name** (e.g., `homelab-backups-matt-2024`).
This topic name is what you'll subscribe to in the ntfy app.

### Alternative: Use Custom JSON Payload (Recommended)

For better formatted notifications, use:
```
--send-http-url=https://ntfy.sh/YOUR_TOPIC_NAME
--send-http-message={"topic":"YOUR_TOPIC_NAME","title":"Duplicati Backup %PARSEDRESULT%","message":"Backup: %OPERATIONNAME%\\nResult: %PARSEDRESULT%\\nBackup: %backup-name%","priority":3,"tags":["backup","duplicati"]}
--send-http-level=Success,Warning,Error
--send-http-result-output-format=Json
```

Click **Save** to create the backup job.

## Step 3: Set Up Ntfy Notifications on Your Device

### On Your Phone:
1. Install ntfy app from Google Play Store or Apple App Store
2. Open the app
3. Click **"+"** to add a subscription
4. Enter the same topic name you used above (e.g., `homelab-backups-matt-2024`)
5. Click Subscribe

### On Your Computer:
1. Go to https://ntfy.sh
2. Enter your topic name in the subscribe box
3. Click Subscribe
4. Keep the tab open or enable browser notifications

## Step 4: Test the Backup

1. In Duplicati, find your newly created backup job
2. Click the job name
3. Click **"Run now"** to test it immediately
4. You should receive a notification on your phone/browser when it completes!

## Step 5: Verify Backup Files

After the backup runs, check that files were created in `C:\backups` on your host machine.

## Important Notes

- **Save your encryption passphrase!** You'll need it to restore backups.
- **Save your ntfy topic name!** You'll need it to receive notifications.
- **New encryption key**: Your new Duplicati encryption key is stored in `.env`:
  `Ci4slb7PedRe2k982YqrhB6usueFeZF80POQ4SQwLrs=`
- Backups will run automatically at the scheduled time (1:00 AM by default)
- You can create multiple backup jobs for different directories if needed

## Troubleshooting

### Not Receiving Notifications?
- Check that the ntfy URL in Duplicati options is correct
- Make sure you're subscribed to the same topic name
- Try running the backup manually and check Duplicati logs
- Test the ntfy URL by sending a test notification:
  ```bash
  curl -d "Test notification" https://ntfy.sh/YOUR_TOPIC_NAME
  ```

### Backup Failing?
- Check Duplicati logs in the web interface
- Verify source and destination paths are accessible
- Check disk space on C:\backups drive

## Step 6: Set Up Healthchecks.io Monitoring (Optional but Recommended)

Healthchecks.io provides dead man's switch monitoring - it alerts you if your backups STOP running (different from ntfy which alerts you when they DO run).

### Create a Healthcheck

1. Go to https://healthchecks.io and create a free account
2. Create a new check with these settings:
   - **Name**: "Duplicati Docker Backups"
   - **Schedule**: Daily at 1:00 AM (or your backup schedule)
   - **Grace Time**: 2 hours (allows backup to complete)
3. Copy the ping URL (looks like: `https://hc-ping.com/XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX`)

### Configure the Healthcheck URL

Add your healthcheck URL to the `.env` file in `docker-projects/backups/.env`:

```
HEALTHCHECKS_URL=https://hc-ping.com/your-check-id-here
```

The healthcheck script (`ping-healthchecks.sh`) is already configured to:
- Automatically ping healthchecks.io after successful backups
- Skip pinging if the backup fails (so you get alerted)
- Use the URL from the environment variable

### Test the Healthcheck

After adding the URL and restarting the container:

```bash
# Test successful backup scenario
docker exec duplicati bash -c "DUPLICATI__PARSED_RESULT=Success bash /config/ping-healthchecks.sh"

# Should output: "Backup successful, pinging healthchecks.io... Successfully pinged healthchecks.io"
```

Check your healthchecks.io dashboard to see the ping.

### Integrate with Duplicati

To run the healthcheck script after each backup:

1. In Duplicati web interface, edit your backup job
2. Go to Options → Advanced options
3. Add these settings:
   ```
   run-script-after=/config/ping-healthchecks.sh
   run-script-timeout=60s
   ```
4. Save the backup job

Now healthchecks.io will monitor your backups and alert you if they fail or don't run!

## Step 7: Off-Site Backup with Backblaze B2 (Recommended)

The local job above writes to `C:\backups` — on the **same PC** as your data. If that
machine dies, is stolen, or gets ransomwared, the live data *and* the backup are lost together.
Off-site backup is the missing layer. This follows the **3-2-1 rule**: keep the existing local
backup, and add a second copy in the cloud.

### Why B2

Backblaze B2 is **metered/pay-as-you-go**: **$6/TB/month = $0.006/GB/month, first 10 GB free**.
Billed for what you actually store (prorated), so a config+database backup (tens of GB) costs
**pennies per month**. Restores are free up to 3× your stored size. Purpose-built for backups and
very reliable with Duplicati.

> Alternative: if you already pay for Microsoft 365, OneDrive's 1 TB is $0 extra — use Duplicati's
> native OneDrive connector (NOT the OneDrive sync client on `C:\backups`, which doubles disk use).
> B2 is preferred here for reliability and near-zero metered cost.

### Step 7a: Create the B2 bucket and key

1. Sign up at https://www.backblaze.com/cloud-storage and enable B2.
2. Create a **private** bucket, e.g. `homelab-duplicati-offsite`.
3. Create an **Application Key** scoped to that bucket. Save the **keyID** and **applicationKey**
   somewhere secure (a password manager) — the applicationKey is shown only once.

### Step 7b: Add a second Duplicati backup job for off-site

Keep the local job as-is; add a **new** job so you have both local (fast restore) and cloud (disaster).

1. Duplicati → **Add backup** → **Configure a new backup**.
2. **General**: Name "Homelab Off-Site (B2)". Use **AES-256 encryption** with a passphrase and
   **SAVE THE PASSPHRASE** — without it the cloud copy is unrecoverable.
3. **Destination**: Storage Type **"B2 Cloud Storage"**. Fill in:
   - Bucket: `homelab-duplicati-offsite`
   - Folder path: `docker-homelab`
   - Application Key ID / Application Key: from Step 7a
   - Click **"Test connection"**.
4. **Source Data**: select the **same sources as the local job** so everything is protected:
   - `/source/docker-configs`
   - `/source/media-configs`
   - `/source/linkding-data`, `/source/lightdash-pgdata`, `/source/minio-data`
5. **Schedule**: Daily, staggered after the local job (e.g. 2:30 AM).
6. **Options → retention**: e.g. "Smart backup retention" (keeps a tapering history) to cap growth.
7. Reuse the ntfy and Healthchecks options (Steps 4 & 6) if you want alerts for this job too
   — use a **separate** Healthchecks check so a local-vs-cloud failure is distinguishable.

### Step 7c: Keep the cloud set small — exclude Plex's regenerable caches

`C:\media\config` (Plex) is usually the largest source, and much of it is **thumbnails/transcodes
that Plex regenerates on its own** — no need to pay to store them off-site. In the job's
**Filters**, add these excludes:

```
-*/Plex Media Server/Cache/
-*/Plex Media Server/Media/
-*/Plex Media Server/Metadata/
-*/Plex Media Server/Transcode/
-*/Plex Media Server/Logs/
```

This protects the databases/settings (the part you can't regenerate) while keeping the off-site
set — and therefore the bill — tiny. Measure first with:

```powershell
"{0:N2} GB" -f ((gci "C:\media\config" -Recurse -File -EA SilentlyContinue | Measure Length -Sum).Sum/1GB)
```

### Step 7d: Verify

1. **Run now** on the B2 job; confirm it completes and files appear in the B2 bucket.
2. Do a **test restore** of a single file from B2 to a temp folder — a backup you haven't restored
   from is only a hypothesis.

## Next Steps

- Consider setting up retention policies (how long to keep old backups)
- Test restoration process from **both** local and B2 to ensure backups work
- Document your encryption passphrase(s) in a secure location (e.g. password manager)
