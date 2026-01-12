# Pi-hole Plugin for TRMNL

Display your Pi-hole stats on your TRMNL e-ink display.

<img width="1652" height="990" alt="image" src="https://github.com/user-attachments/assets/3b6d0799-1c1d-467e-9b3c-ad2398dca399" />

## What This Shows

- **DNS Stats**: Total requests, blocked requests, blocking percentage, query frequency (queries/second)
- **System Health**: CPU usage, RAM usage, temperature, uptime
- **Connected Clients**: Number of devices using your Pi-hole
- **Top Blocked Links**: Most frequently blocked domains
- **12-Hour Graph**: Visual breakdown of blocked, cached, and forwarded queries

## Requirements

This guide assumes you already have Pi-hole installed and running on your device.

**You'll need:**
- A Raspberry Pi (or similar device) with Pi-hole installed
- SSH access to your Pi-hole
- A TRMNL account with TRMNL+ subscription (uses ~3KB of the 5KB webhook limit)

**Tested on:**
- Raspberry Pi 3B+ with DietPi (DietPi_RPi234-ARMv8-Bookworm.img.xz)
- Raspberry Pi with Raspberry Pi OS

## How It Works

The install script sets up a webhook that automatically sends your Pi-hole stats to TRMNL every 15 minutes.

## Installation

SSH into your Pi-hole and run:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rishikeshsreehari/trmnl-pihole/main/install.sh)
```

The installer will:
1. Ask for your TRMNL webhook URL
2. Ask for your Pi-hole URL (defaults to `http://localhost`)
3. Test the connection
4. Set up automatic updates every 15 minutes

### Get Your Webhook URL

1. Go to [TRMNL Private Plugins](https://usetrmnl.com/plugins/private)
2. Click "New Private Plugin"
3. Set strategy to **webhook**
4. Copy the markup from `full.liquid` in this repository
5. Copy your Webhook URL

### Disable Pi-hole Password

If your Pi-hole requires a password, disable it for API access:

```bash
sudo pihole -a -p
```

Press Enter twice to set an empty password.

## After Installation

**View logs:**
```bash
tail -f ~/trmnl-push.log
```

**Test manually:**
```bash
~/push-pihole-to-trmnl.sh
```

**Change update frequency:**
```bash
crontab -e
```

Change `*/15 * * * *` to:
- Every 5 minutes: `*/5 * * * *`
- Every 30 minutes: `*/30 * * * *`
- Every hour: `0 * * * *`

**Note**: TRMNL free tier allows 12 updates/hour, TRMNL+ allows 30 updates/hour.

## Files

- `full.liquid` - Full screen layout
- `half_vertical.liquid` - Half screen layout
- `quadrant.liquid` - Quarter screen layout
- `push-pihole-to-trmnl.sh` - Webhook script
- `install.sh` - Installer
- `settings.yml` - Plugin configuration

## Troubleshooting

**Check if it's working:**
```bash
tail -f ~/trmnl-push.log
```

**Test the script:**
```bash
~/push-pihole-to-trmnl.sh
```

**Check Pi-hole API:**
```bash
curl http://localhost/api/stats/summary
```

**Too many requests error (429):**
You're updating too frequently. Free tier allows every 5 minutes max, TRMNL+ allows every 2 minutes max.

**Reduce payload size (for free tier):**

Edit the script to use less data:
```bash
nano ~/push-pihole-to-trmnl.sh
```

Change:
- `.history[-12:]` to `.history[-6:]` (6 hours instead of 12)
- `.domains[0:15]` to `.domains[0:10]` (top 10 instead of 15)

This reduces payload from ~3KB to ~2KB.

## Uninstall

```bash
rm ~/push-pihole-to-trmnl.sh
rm ~/trmnl-push.log
crontab -e  # Delete the line with push-pihole-to-trmnl.sh
```

## Contributing

Contributions, ideas, and feedback are welcome! Feel free to open an issue or submit a pull request.

## Support

Need help or want a custom TRMNL plugin? Reach out at [hello@rishikeshs.com](mailto:hello@rishikeshs.com)

If you find this useful: [r1l.in/s](https://r1l.in/s)

## License

MIT License - see [LICENSE](LICENSE) file for details
