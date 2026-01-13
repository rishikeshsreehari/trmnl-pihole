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
- Raspberry Pi with Raspberry Pi OS

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
3. **Asks for Pi-hole URL** - Defaults to `http://localhost` (works for 99% of setups)
4. **Sends initial data** - Establishes complete data structure:
   - Stats payload (~625 bytes)
   - History payload (~605 bytes)
   - Domains payload (~812 bytes)
5. **Creates state file** - Starts alternating tracking
6. **Sets up cron job** - Defaults to every 15 minutes (customizable)
7. **Creates log file** - Track all updates at `~/trmnl-push.log`

### Get Your Webhook URL

1. Go to [TRMNL Private Plugins](https://usetrmnl.com/plugins/private)
2. Click "New Private Plugin"
3. Set strategy to **webhook**
4. Copy the markup from `template.liquid` in this repository
5. Copy your Webhook URL (looks like: `https://usetrmnl.com/api/custom_plugins/xxxxx-xxxx-xxxx`)

## After Installation

**View logs:**
```bash
tail -f ~/trmnl-push.log
```

**Check what's being sent:**
```bash
# See last few updates with payload sizes
tail -20 ~/trmnl-push.log
```

**Check state file:**
```bash
cat ~/.pihole-trmnl-state
# Shows either "history" or "domains"
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


### Log Format

Logs show detailed information for each update:

```
2026-01-13 00:15:03 - Stats Update
Payload size: 1331 bytes
Sending: IDX_0 (Stats), IDX_1 (System), IDX_2 (Sensors), IDX_5 (Host)
HTTP Status: 200
✅ Success
---
2026-01-13 00:15:04 - Domains Update
Payload size: 817 bytes
Sending: IDX_4 (Top 15 blocked domains)
HTTP Status: 200
✅ Success
```

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
- 
## Troubleshooting

### Check if it's working

```bash
tail -f ~/trmnl-push.log
```

Look for `✅ Success` messages and HTTP Status 200.

### Test the script manually

```bash
~/push-pihole-to-trmnl.sh
```

### Check Pi-hole API

```bash
curl http://localhost/api/stats/summary
```

Should return JSON with Pi-hole stats. If this fails:
- Verify Pi-hole is running: `pihole status`
- Check Pi-hole web interface is accessible

### API Endpoints Used

```
/api/stats/summary          # Overall statistics
/api/info/system            # System metrics (CPU, RAM, uptime)
/api/info/sensors           # Temperature sensors
/api/info/host              # Hostname
/api/history                # Query history over time
/api/stats/top_domains      # Top blocked domains
```

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

## Uninstalling

To completely remove the Pi-hole plugin:

### Quick Uninstall

SSH into your Pi-hole and run:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rishikeshsreehari/trmnl-pihole/main/uninstall.sh)
```

### Manual Uninstall

If you prefer to remove components manually:

1. **Remove the cron job:**
```bash
crontab -e
# Delete the line containing: ~/push-pihole-to-trmnl.sh
```

2. **Remove the script:**
```bash
rm ~/push-pihole-to-trmnl.sh
```

3. **Remove the state file:**
```bash
rm ~/.pihole-trmnl-state
```

4. **Remove the log file (optional):**
```bash
rm ~/trmnl-push.log
```

5. **Verify cron job is removed:**
```bash
crontab -l | grep pihole
# Should return nothing
```

## Contributing

Contributions, ideas, and feedback are welcome! Feel free to open an issue or submit a pull request.

## Support

Need help or want a custom TRMNL plugin? Reach out at [hello@rishikeshs.com](mailto:hello@rishikeshs.com)

If you find this useful support at: [r1l.in/s](https://r1l.in/s)

## Credits

- Built for [TRMNL](https://usetrmnl.com)
- Pi-hole API documentation: [Pi-hole Docs](https://docs.pi-hole.net)
- Created by [Rishikesh](https://rishikeshs.com)

## License

MIT License - see [LICENSE](LICENSE) file for details
