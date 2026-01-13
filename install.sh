#!/bin/bash

echo "======================================"
echo "Pi-hole TRMNL Plugin Installer"
echo "(v0.1.1)"
echo "======================================"
echo ""

# Check dependencies
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
echo "(Find it at: TRMNL Dashboard > Your Plugin > Settings > Webhook URL)"
echo ""
read -r WEBHOOK_URL

if [ -z "$WEBHOOK_URL" ]; then
    echo "❌ Error: Webhook URL cannot be empty"
    exit 1
fi

# Validate webhook URL format
if [[ ! "$WEBHOOK_URL" =~ ^https://usetrmnl\.com/api/custom_plugins/ ]]; then
    echo "⚠️  Warning: URL doesn't look like a TRMNL webhook URL"
    echo "Expected format: https://usetrmnl.com/api/custom_plugins/xxxxx-xxxx-xxxx"
    echo ""
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Get Pi-hole base URL
echo ""
echo "Enter your Pi-hole base URL [default: http://localhost]:"
echo "⚠️  For most users, the default (http://localhost) works fine."
echo "Only change this if Pi-hole is on a different machine or custom port."
echo ""
read -r BASE_URL
BASE_URL=${BASE_URL:-http://localhost}

echo ""
echo "Using Pi-hole at: $BASE_URL"

# Create the script
echo ""
echo "📥 Creating webhook script..."
SCRIPT_PATH="$HOME/push-pihole-to-trmnl.sh"
LOG_PATH="$HOME/trmnl-push.log"
STATE_FILE="$HOME/.pihole-trmnl-state"

cat > "$SCRIPT_PATH" << 'SCRIPT_EOF'
#!/bin/bash

# Your TRMNL webhook URL
WEBHOOK_URL="WEBHOOK_URL_PLACEHOLDER"

# Pi-hole base URL
BASE_URL="BASE_URL_PLACEHOLDER"

# Log file path
LOG_FILE="$HOME/trmnl-push.log"

# State file to track what was sent last
STATE_FILE="$HOME/.pihole-trmnl-state"

# Redirect all output to log file AND terminal
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to send payload with detailed logging
send_payload() {
    local payload=$1
    local description=$2
    local data_points=$3
    
    # Calculate payload size
    local size=$(echo "$payload" | wc -c)
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $description"
    echo "Payload size: $size bytes"
    echo "Sending: $data_points"
    
    RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
        -H "Content-Type: application/json" \
        -d "$payload")
    
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    BODY=$(echo "$RESPONSE" | head -n-1)
    
    echo "HTTP Status: $HTTP_CODE"
    
    if [ "$HTTP_CODE" = "200" ] || [ "$HTTP_CODE" = "201" ]; then
        echo "✅ Success"
    else
        echo "❌ Failed"
        echo "Response: $BODY"
        return 1
    fi
    
    echo "---"
    return 0
}

echo "=========================================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - TRMNL Push Started"
echo "=========================================="

# Always send Stats + System + Sensors + Host
echo "Fetching stats data..."
STATS=$(curl -s "$BASE_URL/api/stats/summary" | jq '{
  clients: .clients,
  queries: {
    total: .queries.total,
    blocked: .queries.blocked,
    cached: .queries.cached,
    percent_blocked: .queries.percent_blocked
  },
  gravity: {
    domains_being_blocked: .gravity.domains_being_blocked
  }
}')
SYSTEM=$(curl -s "$BASE_URL/api/info/system" | jq '{
    cpu: {"%cpu": .system.cpu["%cpu"]}, 
    memory: {ram: {"%used": .system.memory.ram["%used"]}}, 
    uptime: .system.uptime
}')
SENSORS=$(curl -s "$BASE_URL/api/info/sensors" | jq '{
    cpu_temp: .sensors.cpu_temp, 
    unit: .sensors.unit
}')
HOST=$(curl -s "$BASE_URL/api/info/host" | jq '{
    uname: {nodename: .host.uname.nodename}
}')

STATS_PAYLOAD=$(cat <<EOF
{
  "merge_variables": {
    "IDX_0": $STATS,
    "IDX_1": {"system": $SYSTEM},
    "IDX_2": {"sensors": $SENSORS},
    "IDX_5": {"host": $HOST}
  },
  "merge_strategy": "deep_merge"
}
EOF
)

send_payload "$STATS_PAYLOAD" "Stats Update" "IDX_0 (Stats), IDX_1 (System), IDX_2 (Sensors), IDX_5 (Host)"

if [ $? -ne 0 ]; then
    echo "❌ Stats update failed, aborting"
    exit 1
fi

# Check state file to determine what to send next
if [ ! -f "$STATE_FILE" ]; then
    # First run - send History and create state
    echo ""
    echo "First run detected - sending History"
    LAST_CHART="domains"
else
    LAST_CHART=$(cat "$STATE_FILE")
fi

# Alternate between History and Domains
if [ "$LAST_CHART" = "domains" ]; then
    # Send History
    echo ""
    echo "Fetching history data..."
    HISTORY=$(curl -s "$BASE_URL/api/history" | jq '{history: .history[-4:]}')
    
    HISTORY_PAYLOAD=$(cat <<EOF
{
  "merge_variables": {
    "IDX_3": $HISTORY
  },
  "merge_strategy": "deep_merge"
}
EOF
)
    
    send_payload "$HISTORY_PAYLOAD" "History Update" "IDX_3 (History - 4 data points)"
    
    if [ $? -eq 0 ]; then
        echo "history" > "$STATE_FILE"
    fi
    
else
    # Send Domains
    echo ""
    echo "Fetching domains data..."
    DOMAINS=$(curl -s "$BASE_URL/api/stats/top_domains?blocked=true" | jq '{domains: .domains[0:10]}')
    
    DOMAINS_PAYLOAD=$(cat <<EOF
{
  "merge_variables": {
    "IDX_4": $DOMAINS
  },
  "merge_strategy": "deep_merge"
}
EOF
)
    
    send_payload "$DOMAINS_PAYLOAD" "Domains Update" "IDX_4 (Top 10 blocked domains)"
    
    if [ $? -eq 0 ]; then
        echo "domains" > "$STATE_FILE"
    fi
fi

echo ""
echo "=========================================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Push Complete"
echo "=========================================="
SCRIPT_EOF

# Replace placeholders
sed -i "s|WEBHOOK_URL_PLACEHOLDER|$WEBHOOK_URL|g" "$SCRIPT_PATH"
sed -i "s|BASE_URL_PLACEHOLDER|$BASE_URL|g" "$SCRIPT_PATH"

chmod +x "$SCRIPT_PATH"

echo "✅ Script installed at $SCRIPT_PATH"

# Initial setup - send all data to establish structure
echo ""
echo "🔧 Running initial setup to establish data structure..."
echo ""
echo "📝 Logging setup to: $LOG_PATH"
echo ""

# Create log file and add initial entry
{
echo "=========================================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Initial Setup"
echo "=========================================="
echo ""

# Fetch all data
STATS=$(curl -s "$BASE_URL/api/stats/summary" | jq '{
  clients: .clients,
  queries: {
    total: .queries.total,
    blocked: .queries.blocked,
    cached: .queries.cached,
    percent_blocked: .queries.percent_blocked
  },
  gravity: {
    domains_being_blocked: .gravity.domains_being_blocked
  }
}')
SYSTEM=$(curl -s "$BASE_URL/api/info/system" | jq '{system: {cpu: {"%cpu": .system.cpu["%cpu"]}, memory: {ram: {"%used": .system.memory.ram["%used"]}}, uptime: .system.uptime}}')
SENSORS=$(curl -s "$BASE_URL/api/info/sensors" | jq '{sensors: {cpu_temp: .sensors.cpu_temp, unit: .sensors.unit}}')
HOST=$(curl -s "$BASE_URL/api/info/host" | jq '{host: {uname: {nodename: .host.uname.nodename}}}')
HISTORY=$(curl -s "$BASE_URL/api/history" | jq '{history: .history[-4:]}')
DOMAINS=$(curl -s "$BASE_URL/api/stats/top_domains?blocked=true" | jq '{domains: .domains[0:10]}')

# Send Stats first
echo "Sending Stats..."
STATS_INITIAL=$(cat <<EOF
{
  "merge_variables": {
    "IDX_0": $STATS,
    "IDX_1": $SYSTEM,
    "IDX_2": $SENSORS,
    "IDX_5": $HOST
  }
}
EOF
)

STATS_SIZE=$(echo "$STATS_INITIAL" | wc -c)
echo "Payload size: $STATS_SIZE bytes"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$STATS_INITIAL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "❌ Stats setup failed. HTTP Status: $HTTP_CODE"
    echo "Response: $(echo "$RESPONSE" | head -n-1)"
    exit 1
fi

echo "✅ Stats sent"
echo ""
sleep 2

# Send History
echo "Sending History..."
HISTORY_INITIAL=$(cat <<EOF
{
  "merge_variables": {
    "IDX_3": $HISTORY
  },
  "merge_strategy": "deep_merge"
}
EOF
)

HISTORY_SIZE=$(echo "$HISTORY_INITIAL" | wc -c)
echo "Payload size: $HISTORY_SIZE bytes"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$HISTORY_INITIAL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "❌ History setup failed. HTTP Status: $HTTP_CODE"
    exit 1
fi

echo "✅ History sent"
echo ""
sleep 2

# Send Domains
echo "Sending Domains..."
DOMAINS_INITIAL=$(cat <<EOF
{
  "merge_variables": {
    "IDX_4": $DOMAINS
  },
  "merge_strategy": "deep_merge"
}
EOF
)

DOMAINS_SIZE=$(echo "$DOMAINS_INITIAL" | wc -c)
echo "Payload size: $DOMAINS_SIZE bytes"

RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$DOMAINS_INITIAL")

HTTP_CODE=$(echo "$RESPONSE" | tail -n1)

if [ "$HTTP_CODE" != "200" ] && [ "$HTTP_CODE" != "201" ]; then
    echo "❌ Domains setup failed. HTTP Status: $HTTP_CODE"
    exit 1
fi

echo "✅ Domains sent"
echo ""
echo "=========================================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Initial Setup Complete"
echo "=========================================="
} | tee -a "$LOG_PATH"

# Create initial state file (last sent was domains, so next will be history)
echo "domains" > "$STATE_FILE"

echo ""
echo "✅ Initial data structure established!"

# Ask about cron setup
echo ""
echo "======================================"
echo "Cron Setup"
echo "======================================"
echo ""
echo "Recommended: Run every 15 minutes"
echo "This will update:"
echo "  - Stats/System/Sensors: Every 15 min (optimized)"
echo "  - History: Every 30 min (4 data points)"
echo "  - Domains: Every 30 min (top 10)"
echo ""
echo "Update frequency (in minutes) [default: 15]:"
echo "(Choose: 5, 10, 15, 20, or 30)"
read -r FREQUENCY
FREQUENCY=${FREQUENCY:-15}

# Validate frequency
if [[ ! "$FREQUENCY" =~ ^(5|10|15|20|30)$ ]]; then
    echo "⚠️  Invalid frequency. Using default: 15 minutes"
    FREQUENCY=15
fi

# Remove any old cron jobs
crontab -l 2>/dev/null | grep -v "push-pihole-to-trmnl.sh" | crontab - 2>/dev/null

# Add new cron job (no need for >> redirect since script handles it)
(crontab -l 2>/dev/null; echo "*/$FREQUENCY * * * * $SCRIPT_PATH") | crontab -

echo ""
echo "✅ Cron job added! Updates every $FREQUENCY minutes."
echo ""
echo "With $FREQUENCY minute intervals:"
echo "  - Stats update every $FREQUENCY min"
echo "  - History/Domains alternate every $((FREQUENCY * 2)) min"
echo "  - Total: $((60 / FREQUENCY * 2)) requests/hour"
echo ""
echo "📝 Logs automatically saved to: $LOG_PATH"

echo ""
echo "======================================"
echo "✅ Installation Complete!"
echo "======================================"
echo ""
echo "Your Pi-hole dashboard is now connected to TRMNL!"
echo ""
echo "Configuration:"
echo "  - Pi-hole URL: $BASE_URL"
echo "  - State file: $STATE_FILE"
echo "  - Log file: $LOG_PATH"
echo "  - Update frequency: Every $FREQUENCY minutes"
echo ""
echo "How it works:"
echo "  - State file tracks alternating updates"
echo "  - Every run sends Stats (optimized for size)"
echo "  - Alternates between History (4 points) and Domains (top 10)"
echo "  - Uses deep_merge to update only changed data"
echo "  - All output automatically logged to file"
echo "  - Total payload optimized to stay under 2KB limit"
echo ""
echo "Useful commands:"
echo "  - Manual run:       $SCRIPT_PATH"
echo "  - View logs:        tail -f $LOG_PATH"
echo "  - Check state:      cat $STATE_FILE"
echo "  - Edit cron:        crontab -e"
echo "  - View cron jobs:   crontab -l"
echo ""
