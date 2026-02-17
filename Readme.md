# Pi-hole Plugin for TRMNL

Display your [Pi-hole](https://pi-hole.net) stats on your TRMNL e-ink display.

<img width="1652" height="990" alt="image" src="https://github.com/user-attachments/assets/3b6d0799-1c1d-467e-9b3c-ad2398dca399" />

## What This Shows

- **DNS Stats**: Total requests, blocked requests, blocking percentage, query frequency (queries/second)
- **System Health**: CPU usage, RAM usage, temperature, uptime
- **Connected Clients**: Number of devices using your Pi-hole
- **Top Blocked Domains**: Most frequently blocked domains
- **Historical Chart**: Recent data points showing blocked, cached, and forwarded queries

## Requirements

This guide assumes you already have [Pi-hole](https://pi-hole.net) installed and running on your device.

**You'll need:**
- A Raspberry Pi (or similar device) with Pi-hole installed
- SSH access to your Pi-hole (root or sudo privileges required for installation)
- A TRMNL account

**Tested on:**
- Raspberry Pi 3B+ with DietPi (DietPi_RPi234-ARMv8-Bookworm.img.xz)
- Raspberry Pi 4 with Raspberry Pi OS

## Pi-hole Authentication

Pi-hole v6 requires authentication for API access. The installer will automatically detect if your Pi-hole needs a password and prompt you if so.

You can use either your **Pi-hole login password** or an **app password**. App passwords are recommended since they can be revoked independently without changing your main login, and they bypass 2FA.

**To generate an app password:**
1. Open your Pi-hole Admin UI
2. Go to **Settings → Web Interface / API**
3. Switch from **Basic** to **Expert** mode
4. Click **Configure app password**
5. Copy the generated password (shown only once)

If you don't have a password set on Pi-hole, the installer will skip authentication entirely.

## How It Works

### Update Strategy

The plugin uses a smart alternating pattern to stay within TRMNL's free tier limits (12 requests/hour, 2KB per request):

**Every 15 minutes (default):**
- Always sends: Stats, System metrics (CPU/RAM/Temp), Host info
- Alternates: History chart OR Top blocked domains

**Example hourly schedule:**
```
:00 → Stats + History (2 requests)
:15 → Stats + Domains (2 requests)
:30 → Stats + History (2 requests)
:45 → Stats + Domains (2 requests)
Total: 8 requests/hour ✅ (well within 12/hour limit)
```

### Smart State Tracking

The installer creates a state file (`~/.pihole-trmnl-state`) that automatically tracks what was sent last:
- State shows `history` → Next run sends Domains
- State shows `domains` → Next run sends History
- No manual intervention needed!

### Optimized Payloads

Data is carefully optimized to stay within TRMNL's 2KB limit:
- **Stats payload**: ~600 bytes (essential metrics only)
- **History payload**: ~600 bytes (4 data points)
- **Domains payload**: ~800 bytes (top 10 domains)
- **Total combined**: ~1,700 bytes ✅ (well under 2KB)

Uses TRMNL's `deep_merge` strategy for efficient updates.

## Installation

### Quick Start

SSH into your Pi-hole and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rishikeshsreehari/trmnl-pihole/main/install.sh)
```

### What the Installer Does

1. **Checks dependencies** - Installs `jq` if needed
2. **Asks for your TRMNL webhook URL**
3. **Asks for Pi-hole URL** - Defaults to `http://localhost`
4. **Auto-detects authentication** - Tests the API, only asks for password if needed
5. **Validates Pi-hole responses** - Ensures real data is received before sending to TRMNL
6. **Sends initial data** - Establishes complete data structure
7. **Creates state file** - Starts alternating tracking
8. **Sets up cron job** - Defaults to every 15 minutes (customizable)
9. **Creates log file** - Track all updates at `~/trmnl-push.log`

### Get Your Webhook URL

1. Go to [TRMNL Private Plugins](https://usetrmnl.com/plugins/private)
2. Click "New Private Plugin"
3. Set strategy to **webhook**
4. Copy the markup from `template.liquid` in this repository
5. Copy your Webhook URL (looks like: `https://trmnl.com/api/custom_plugins/xxxxx-xxxx-xxxx`)

### Installation Video

Video instructions by RelfWolf: https://www.youtube.com/watch?v=OnRFtMqgquk

## After Installation

**View logs:**
```bash
tail -f ~/trmnl-push.log
```

**Check what's being sent:**
```bash
tail -20 ~/trmnl-push.log
```

**Check state file:**
```bash
cat ~/.pihole-trmnl-state
```

**Test manually:**
```bash
~/push-pihole-to-trmnl.sh
```

**Change update frequency:**
```bash
crontab -e
```

Change `*/15 * * * *` to your preferred interval:
- Every 5 minutes: `*/5 * * * *` (12 requests/hour - at free tier limit)
- Every 10 minutes: `*/10 * * * *` (12 requests/hour - at free tier limit)
- Every 15 minutes: `*/15 * * * *` (8 requests/hour - recommended ✅)
- Every 20 minutes: `*/20 * * * *` (6 requests/hour)
- Every 30 minutes: `*/30 * * * *` (4 requests/hour)

**Note**: Each run sends 2 webhooks (Stats + alternating chart data), so frequency × 2 = requests/hour.

**Update password** (if your Pi-hole password changes):
```bash
echo 'your_new_password' > ~/.pihole-trmnl-creds
```

### Log Format

Logs show detailed information for each update:

```
2026-01-13 00:15:02 - TRMNL Push Started
🔐 Authenticated successfully
Fetching stats data...
2026-01-13 00:15:03 - Stats Update
Payload size: 532 bytes
Sending: IDX_0 (Stats), IDX_1 (System), IDX_2 (Sensors), IDX_5 (Host)
HTTP Status: 200
✅ Success
---
2026-01-13 00:15:04 - Domains Update
Payload size: 817 bytes
Sending: IDX_4 (Top 10 blocked domains)
HTTP Status: 200
✅ Success
---
🔐 Session closed
```

If authentication or data fetching fails, the script will log clear error messages and abort rather than sending empty data to TRMNL.

### What Gets Sent

**Stats Payload (every 15 min):**
- Total queries, blocked queries, % blocked, frequency
- CPU usage, RAM usage, temperature, uptime
- Hostname, active clients

**History Payload (every 30 min):**
- Last 4 data points for chart (optimized for size)
- Blocked, cached, forwarded counts per interval

**Domains Payload (every 30 min):**
- Top 10 blocked domains with request counts

## API Endpoints Used

This plugin reads data from the following Pi-hole v6 API endpoints:

| Endpoint | Data | IDX |
|---|---|---|
| `/api/stats/summary` | Queries, blocked count, clients, gravity | IDX_0 |
| `/api/info/system` | CPU usage, RAM usage, uptime | IDX_1 |
| `/api/info/sensors` | CPU temperature | IDX_2 |
| `/api/history` | Historical query data (last 4 points) | IDX_3 |
| `/api/stats/top_domains?blocked=true` | Top 10 blocked domains | IDX_4 |
| `/api/info/host` | Hostname | IDX_5 |
| `/api/auth` | Session authentication (POST) | — |

All endpoints are **read-only**. The plugin never modifies your Pi-hole configuration.

If you'd like to build your own integration or adapt this for a different display, feel free to use these endpoints directly. The [Pi-hole API documentation](https://docs.pi-hole.net/api/) has full details, and your Pi-hole also serves its own API docs at `http://<your-pihole>/api/docs`.

### Data Structure

```json
{
  "IDX_0": {/* Essential Pi-hole stats (queries, blocked, cached, percent) */},
  "IDX_1": {"system": {/* CPU, RAM, uptime */}},
  "IDX_2": {"sensors": {/* temperature */}},
  "IDX_3": {"history": [/* 4 data points */]},
  "IDX_4": {"domains": [/* 10 domains */]},
  "IDX_5": {"host": {/* hostname */}}
}
```

### Why deep_merge?

The `deep_merge` strategy lets us update only parts of the data:
1. Initial setup sends everything once
2. Each update only sends changed sections
3. TRMNL merges new data with existing data
4. Reduces bandwidth and stays within 2KB limit

### Rate Limit Strategy

TRMNL free tier: 12 requests/hour, 2KB per request

- Send Stats every 15 min (always needed for display)
- Alternate History/Domains every 30 min (chart data doesn't need constant updates)
- 2 webhooks per run × 4 runs/hour = 8 requests/hour
- Leaves 4 requests/hour buffer for manual tests

## Troubleshooting

### Check if it's working

```bash
tail -f ~/trmnl-push.log
```

Look for `✅ Success` messages and HTTP Status 200. If you see `❌ Failed to fetch` or `❌ Authentication failed`, check the suggestions below.

### Test the script manually

```bash
~/push-pihole-to-trmnl.sh
```

### Check Pi-hole API directly

```bash
curl http://localhost/api/stats/summary
```

If this returns `{"error":{"key":"unauthorized"...}}`, your Pi-hole requires authentication. Re-run the installer and enter your password or app password when prompted.

If this fails entirely, verify Pi-hole is running: `pihole status`

### Common Issues

| Problem | Cause | Fix |
|---|---|---|
| Zeros on TRMNL screen | Pi-hole auth required but not configured | Re-run installer, enter password when prompted |
| `❌ Authentication failed` in logs | Password changed or incorrect | Update: `echo 'new_pass' > ~/.pihole-trmnl-creds` |
| `HTTP Status: 429` | Too many requests (TRMNL or Pi-hole rate limit) | Wait a few minutes and try again |
| `❌ Empty response` | Pi-hole not reachable | Check base URL and that Pi-hole is running |
| Script works manually but not via cron | PATH or environment issue | Check `crontab -l` for the correct script path |

### Authentication Not Working?

1. Verify your password works: `curl -s -X POST "http://localhost/api/auth" -H "Content-Type: application/json" -d '{"password":"your_password"}'`
2. You should see `"valid": true` and a `sid` in the response
3. If using 2FA, you must use an app password (regular password requires a TOTP code)
4. If you get `429`, wait a minute — Pi-hole rate-limits login attempts

## Uninstalling

### Quick Uninstall

SSH into your Pi-hole and run:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rishikeshsreehari/trmnl-pihole/main/uninstall.sh)
```

This removes the push script, cron job, state file, log file, and credentials file. It does **not** affect your Pi-hole installation or settings.

### Manual Uninstall

If you prefer to remove components manually:

```bash
# Remove the cron job
crontab -l | grep -v "push-pihole-to-trmnl.sh" | crontab -

# Remove all files
rm ~/push-pihole-to-trmnl.sh
rm ~/.pihole-trmnl-state
rm ~/.pihole-trmnl-creds
rm ~/trmnl-push.log

# Verify
crontab -l | grep pihole   # Should return nothing
```

## Contributing

Contributions, ideas, and feedback are welcome! Feel free to open an issue or submit a pull request.

## Support

For issues or setup help, feel free to reach out via:
- **Discord**: rishikeshs
- **Email**: [hello@rishikeshs.com](mailto:hello@rishikeshs.com)
- **GitHub Issues**: [Open an issue](https://github.com/rishikeshsreehari/trmnl-pihole/issues)

Need a custom TRMNL plugin? Get in touch!

Use this [link](https://trmnl.com/?ref=Rishikesh10) or the code `Rishikesh10` on checkout to get $10 off on your TRMNL purchase.

If you find this useful, support at: [r1l.in/s](https://r1l.in/s)

## Credits

- Built for [TRMNL](https://usetrmnl.com)
- Pi-hole API documentation: [Pi-hole Docs](https://docs.pi-hole.net)
- Created by [Rishikesh](https://rishikeshs.com)

## License

MIT License - see [LICENSE](LICENSE) file for details
