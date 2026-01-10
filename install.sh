#!/bin/bash

echo "======================================"
echo "Pi-hole TRMNL Plugin Installer"
echo "======================================"
echo ""

# Check if running on correct system
if ! command -v curl &> /dev/null; then
    echo "❌ Error: curl is not installed. Please install it first."
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo "⚠️  Warning: jq is not installed. Installing..."
    sudo apt-get update && sudo apt-get install -y jq
fi

# Get webhook URL from user
echo "Please enter your TRMNL Webhook URL:"
echo "(Example: https://usetrmnl.com/api/custom_plugins/xxxxx-xxxx-xxxx)"
read -r WEBHOOK_URL

if [ -z "$WEBHOOK_URL" ]; then
    echo "❌ Error: Webhook URL cannot be empty"
    exit 1
fi

# Get Pi-hole base URL (default to localhost)
echo ""
echo "Enter your Pi-hole base URL [default: http://localhost]:"
read -r BASE_URL
BASE_URL=${BASE_URL:-http://localhost}

# Download the script
echo ""
echo "📥 Downloading webhook script..."
SCRIPT_PATH="$HOME/push-pihole-to-trmnl.sh"

cat > "$SCRIPT_PATH" << 'SCRIPT_EOF'
#!/bin/bash

# Your TRMNL webhook URL
WEBHOOK_URL="WEBHOOK_URL_PLACEHOLDER"

# Pi-hole base URL
BASE_URL="BASE_URL_PLACEHOLDER"

# Fetch optimized data
STATS=$(curl -s "$BASE_URL/api/stats/summary")
SYSTEM=$(curl -s "$BASE_URL/api/info/system" | jq '{system: {cpu: {"%cpu": .system.cpu["%cpu"]}, memory: {ram: {"%used": .system.memory.ram["%used"]}}, uptime: .system.uptime}}')
SENSORS=$(curl -s "$BASE_URL/api/info/sensors" | jq '{sensors: {cpu_temp: .sensors.cpu_temp, unit: .sensors.unit}}')
HISTORY=$(curl -s "$BASE_URL/api/history" | jq '{history: .history[-12:]}')
TOP_DOMAINS=$(curl -s "$BASE_URL/api/stats/top_domains" | jq '{domains: .domains[0:15]}')
HOST=$(curl -s "$BASE_URL/api/info/host" | jq '{host: {uname: {nodename: .host.uname.nodename}}}')

# Build payload
PAYLOAD=$(cat <<EOF
{
  "merge_variables": {
    "IDX_0": $STATS,
    "IDX_1": $SYSTEM,
    "IDX_2": $SENSORS,
    "IDX_3": $HISTORY,
    "IDX_4": $TOP_DOMAINS,
    "IDX_5": $HOST
  }
}
EOF
)

# Send to TRMNL
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
BODY=$(echo "$RESPONSE" | head -n-1)

echo "$(date '+%Y-%m-%d %H:%M:%S') - Push to TRMNL"
echo "HTTP Status: $HTTP_CODE"

if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
  echo "✅ Success"
else
  echo "❌ Failed"
  echo "Response: $BODY"
fi
SCRIPT_EOF

# Replace placeholders
sed -i "s|WEBHOOK_URL_PLACEHOLDER|$WEBHOOK_URL|g" "$SCRIPT_PATH"
sed -i "s|BASE_URL_PLACEHOLDER|$BASE_URL|g" "$SCRIPT_PATH"

chmod +x "$SCRIPT_PATH"

echo "✅ Script installed at $SCRIPT_PATH"

# Test the script
echo ""
echo "🧪 Testing the script..."
"$SCRIPT_PATH"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Test successful!"
else
    echo ""
    echo "❌ Test failed. Please check your Pi-hole and webhook URL."
    exit 1
fi

# Ask about cron setup
echo ""
echo "Do you want to set up automatic updates every 15 minutes? (y/n)"
read -r SETUP_CRON

if [ "$SETUP_CRON" = "y" ] || [ "$SETUP_CRON" = "Y" ]; then
    # Check if cron job already exists
    if crontab -l 2>/dev/null | grep -q "push-pihole-to-trmnl.sh"; then
        echo "⚠️  Cron job already exists. Skipping..."
    else
        # Add to crontab
        (crontab -l 2>/dev/null; echo "*/15 * * * * $SCRIPT_PATH >> $HOME/trmnl-push.log 2>&1") | crontab -
        echo "✅ Cron job added! Data will push every 15 minutes."
        echo "📝 Logs will be saved to $HOME/trmnl-push.log"
    fi
else
    echo ""
    echo "ℹ️  To manually add cron job later, run:"
    echo "   crontab -e"
    echo ""
    echo "   Then add this line:"
    echo "   */15 * * * * $SCRIPT_PATH >> $HOME/trmnl-push.log 2>&1"
fi

echo ""
echo "======================================"
echo "✅ Installation Complete!"
echo "======================================"
echo ""
echo "Your Pi-hole stats will now update on TRMNL."
echo ""
echo "Useful commands:"
echo "  - View logs: tail -f ~/trmnl-push.log"
echo "  - Test script: ~/push-pihole-to-trmnl.sh"
echo "  - Edit cron: crontab -e"
echo ""
