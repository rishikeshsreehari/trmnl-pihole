# Pi-hole Plugin for TRMNL

Monitor your Pi-hole network-wide ad blocker statistics on your TRMNL e-ink display.

<img width="1652" height="990" alt="image" src="https://github.com/user-attachments/assets/3b6d0799-1c1d-467e-9b3c-ad2398dca399" />



## Features

- Real-time DNS statistics (queries, blocked requests, blocking percentage, query frequency)
- System health monitoring (CPU, RAM, temperature, uptime)
- 12-hour query history chart (blocked, cached, forwarded)
- Top 15 blocked domains
- Multiple layouts: Full screen, half-vertical, and quadrant
- Auto-refresh every 15 minutes

## Requirements

- Pi-hole server running on your local network
- Pi-hole API password authentication must be disabled
- SSH access to your Pi-hole (or any device on your network)
- TRMNL+ subscription recommended (uses ~3KB of 5KB webhook limit)

## Installation

### Quick Install (Recommended)

SSH into your Pi-hole and run this one-liner:

```bash
curl -fsSL https://raw.githubusercontent.com/rishikeshsreehari/trmnl-pihole/main/install.sh | bash
```

The installer will:
1. Download and configure the webhook script
2. Ask for your TRMNL webhook URL
3. Test the connection
4. Optionally set up automatic updates (cron job)

### Manual Installation

<details>
<summary>Click to expand manual installation steps</summary>

#### 1. Create Plugin in TRMNL

1. Go to [TRMNL Private Plugins](https://usetrmnl.com/plugins/private)
2. Click "New Private Plugin"
3. Set strategy to **webhook**
4. Copy the markup from `full.liquid` in this repository
5. Copy your Webhook URL (you'll need this in step 2)

#### 2. Install Webhook Script

SSH into your Pi-hole and run:

```bash
curl -o ~/push-pihole-to-trmnl.sh https://raw.githubusercontent.com/rishikeshsreehari/trmnl-pihole/main/push-pihole-to-trmnl.sh
chmod +x ~/push-pihole-to-trmnl.sh
```

#### 3. Configure the Script

Edit the script with your webhook URL:

```bash
nano ~/push-pihole-to-trmnl.sh
```

Replace `YOUR_WEBHOOK_URL_HERE` with your actual webhook URL from step 1, and set your Pi-hole base URL (default: `http://localhost`).

#### 4. Test the Script

```bash
~/push-pihole-to-trmnl.sh
```

You should see:
```
✅ Success
```

#### 5. Set Up Auto-refresh

Add to crontab to run every 15 minutes:

```bash
crontab -e
```

Add this line:

```
*/15 * * * * /home/pi/push-pihole-to-trmnl.sh >> /home/pi/trmnl-push.log 2>&1
```

Save and exit. Done!

</details>

## Files in This Repository

- `full.liquid` - Full screen layout template
- `half_vertical.liquid` - Half-vertical layout template  
- `quadrant.liquid` - Quadrant layout template
- `push-pihole-to-trmnl.sh` - Webhook script to push data from Pi-hole to TRMNL
- `install.sh` - Automated installer script
- `settings.yml` - Plugin configuration for TRMNL

## Configuration

### Adjust Update Frequency

Edit your crontab to change how often data is pushed:

```bash
crontab -e
```

- Every 5 minutes: `*/5 * * * *`
- Every 15 minutes: `*/15 * * * *` (default)
- Every 30 minutes: `*/30 * * * *`
- Every hour: `0 * * * *`

**Note**: TRMNL free tier allows 12 pushes/hour, TRMNL+ allows 30 pushes/hour.

### Disable Pi-hole Password

If your Pi-hole requires password authentication, disable it for API access:

```bash
sudo pihole -a -p
```

Press Enter twice to set an empty password, or configure API authentication in Pi-hole settings.

### Reduce Payload Size (Free Tier)

If you're on TRMNL free tier (2KB limit), edit the script to reduce data:

```bash
nano ~/push-pihole-to-trmnl.sh
```

Changes to make:
- History: Change `.history[-12:]` to `.history[-6:]` (6 hours instead of 12)
- Top Domains: Change `.domains[0:15]` to `.domains[0:10]` (top 10 instead of 15)

This should reduce payload from ~3KB to ~2KB.

## Troubleshooting

### Check if script is running

View real-time logs:

```bash
tail -f ~/trmnl-push.log
```

### Manually test the script

```bash
~/push-pihole-to-trmnl.sh
```

### Verify Pi-hole API is accessible

```bash
curl http://localhost/api/stats/summary
```

You should see JSON data. If you get an error, check that:
- Pi-hole is running
- Password authentication is disabled
- API endpoints are accessible

### Script not found error

If you see "command not found", ensure the script path matches your username:

```bash
# For user 'pi'
/home/pi/push-pihole-to-trmnl.sh

# For user 'rishikesh'
/home/rishikesh/push-pihole-to-trmnl.sh

# Or use ~/ which works for any user
~/push-pihole-to-trmnl.sh
```

Update your crontab with the correct path.

### 429 Rate Limit Error

You're pushing data too frequently. TRMNL limits:
- Free tier: 12 requests/hour (every 5 minutes max)
- TRMNL+: 30 requests/hour (every 2 minutes max)

Reduce your cron frequency.

### Uninstall

To remove the plugin:

```bash
# Remove the script
rm ~/push-pihole-to-trmnl.sh

# Remove cron job
crontab -e
# Delete the line with push-pihole-to-trmnl.sh

# Remove log file
rm ~/trmnl-push.log
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request or open an issue for bugs and feature requests.


## Support

If you find this plugin useful, consider supporting my work: [r1l.in/s](https://r1l.in/s)

Need a custom TRMNL plugin for your business? I'm available for contract work. Reach out at [hello@rishikeshs.com](mailto:hello@rishikeshs.com).


## License

MIT License - see [LICENSE](LICENSE) file for details
