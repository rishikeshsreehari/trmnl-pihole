#!/bin/bash

echo "======================================"
echo "Pi-hole TRMNL Plugin Installer"
echo "(v0.2.0)"
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
if [[ ! "$WEBHOOK_URL" =~ ^https://trmnl\.com/api/custom_plugins/ ]]; then
    echo "⚠️  Warning: URL doesn't look like a TRMNL webhook URL"
    echo "Expected format: https://trmnl.com/api/custom_plugins/xxxxx-xxxx-xxxx"
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

# --- Authentication Auto-Detection ---
echo ""
echo "🔍 Testing Pi-hole API access..."

TEST_RESPONSE=$(curl -s -w "\n%{http_code}" "$BASE_URL/api/stats/summary")
TEST_HTTP_CODE=$(echo "$TEST_RESPONSE" | tail -n1)
TEST_BODY=$(echo "$TEST_RESPONSE" | head -n-1)

PIHOLE_PASSWORD=""
CREDS_FILE="$HOME/.pihole-trmnl-creds"

if [ "$TEST_HTTP_CODE" = "200" ]; then
    # Check if response is actual data or an error
    IS_ERROR=$(echo "$TEST_BODY" | jq -r '.error // empty' 2>/dev/null)
    if [ -z "$IS_ERROR" ]; then
        echo "✅ API accessible without authentication."
        AUTH_NEEDED=false
    else
        echo "⚠️  API returned an error. Authentication may be required."
        AUTH_NEEDED=true
    fi
elif [ "$TEST_HTTP_CODE" = "401" ]; then
    echo "🔐 Pi-hole requires authentication."
    AUTH_NEEDED=true
else
    echo "❌ Could not reach Pi-hole API (HTTP $TEST_HTTP_CODE)"
    echo "Check your base URL: $BASE_URL"
    echo ""
    echo "Common fixes:"
    echo "  - Is Pi-hole running? Try: pihole status"
    echo "  - Docker users: use your Pi-hole container's IP or hostname"
    echo "  - Custom port? Include it: http://localhost:8080"
    exit 1
fi

if [ "$AUTH_NEEDED" = true ]; then
    echo ""
    echo "======================================"
    echo "Pi-hole Authentication"
    echo "======================================"
    echo ""
    echo "Enter your Pi-hole password or app password."
    echo ""
    echo "💡 Tip: App passwords are recommended for scripts."
    echo "   Generate one in Pi-hole Admin UI:"
    echo "   Settings > Web Interface/API > Expert mode > Configure app password"
    echo ""
    echo "Enter password:"
    read -rs PIHOLE_PASSWORD
    echo ""

    if [ -z "$PIHOLE_PASSWORD" ]; then
        echo "❌ Password cannot be empty when authentication is required."
        exit 1
    fi

    # Test authentication
    echo "🔐 Testing authentication..."

    AUTH_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"password\": \"$PIHOLE_PASSWORD\"}")

    AUTH_HTTP_CODE=$(echo "$AUTH_RESPONSE" | tail -n1)
    AUTH_BODY=$(echo "$AUTH_RESPONSE" | head -n-1)

    if [ "$AUTH_HTTP_CODE" = "200" ]; then
        AUTH_VALID=$(echo "$AUTH_BODY" | jq -r '.session.valid // false')
        AUTH_SID=$(echo "$AUTH_BODY" | jq -r '.session.sid // empty')

        if [ "$AUTH_VALID" = "true" ] && [ -n "$AUTH_SID" ]; then
            echo "✅ Authentication successful!"

            # Logout test session
            curl -s -X DELETE "$BASE_URL/api/auth" -H "X-FTL-SID: $AUTH_SID" > /dev/null 2>&1
        else
            echo "❌ Authentication failed. Invalid password."
            echo ""
            echo "Tips:"
            echo "  - Double-check your Pi-hole password"
            echo "  - Try generating an app password in Pi-hole Settings"
            echo "  - If using 2FA, you must use an app password"
            exit 1
        fi
    elif [ "$AUTH_HTTP_CODE" = "429" ]; then
        echo "❌ Too many login attempts. Wait a minute and try again."
        exit 1
    else
        echo "❌ Authentication failed (HTTP $AUTH_HTTP_CODE)"
        echo "Response: $AUTH_BODY"
        exit 1
    fi

    # Store password securely
    echo "$PIHOLE_PASSWORD" > "$CREDS_FILE"
    chmod 600 "$CREDS_FILE"
    echo "🔒 Password stored securely at $CREDS_FILE (owner-read only)"
fi

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

# Credentials file
CREDS_FILE="$HOME/.pihole-trmnl-creds"

# Log file path
LOG_FILE="$HOME/trmnl-push.log"

# State file to track what was sent last
STATE_FILE="$HOME/.pihole-trmnl-state"

# Redirect all output to log file AND terminal
exec > >(tee -a "$LOG_FILE") 2>&1

# ---- Authentication Helper ----
AUTH_SID=""

get_auth_session() {
    if [ ! -f "$CREDS_FILE" ]; then
        # No credentials file = no auth needed
        return 0
    fi

    local password
    password=$(cat "$CREDS_FILE")

    if [ -z "$password" ]; then
        return 0
    fi

    local response
    response=$(curl -s -w "\n%{http_code}" -X POST "$BASE_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"password\": \"$password\"}")

    local http_code
    http_code=$(echo "$response" | tail -n1)
    local body
    body=$(echo "$response" | head -n-1)

    if [ "$http_code" = "200" ]; then
        AUTH_SID=$(echo "$body" | jq -r '.session.sid // empty')
        if [ -n "$AUTH_SID" ]; then
            echo "🔐 Authenticated successfully"
            return 0
        fi
    fi

    echo "❌ Authentication failed (HTTP $http_code)"
    echo "Response: $body"
    echo "💡 Tip: Update password with: echo 'new_password' > $CREDS_FILE"
    return 1
}

# Wrapper for authenticated curl calls with validation
pihole_api() {
    local endpoint=$1
    local response
    if [ -n "$AUTH_SID" ]; then
        response=$(curl -s "$BASE_URL$endpoint" -H "X-FTL-SID: $AUTH_SID")
    else
        response=$(curl -s "$BASE_URL$endpoint")
    fi

    # Check for empty response
    if [ -z "$response" ]; then
        echo "❌ Empty response from Pi-hole for $endpoint" >&2
        return 1
    fi

    # Check for API error (auth, bad request, etc.)
    local error_key
    error_key=$(echo "$response" | jq -r '.error.key // empty' 2>/dev/null)
    if [ -n "$error_key" ]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "❌ Pi-hole API error for $endpoint: $error_msg" >&2
        return 1
    fi

    echo "$response"
    return 0
}

# Function to send payload with detailed logging
send_payload() {
    local payload=$1
    local description=$2
    local data_points=$3

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

# Authenticate first
get_auth_session
if [ $? -ne 0 ]; then
    echo "❌ Cannot authenticate with Pi-hole. Aborting."
    echo "💡 Re-run the installer if your password changed."
    exit 1
fi

# Fetch stats data with validation
echo "Fetching stats data..."
STATS=$(pihole_api "/api/stats/summary")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch stats from Pi-hole. Aborting."
    echo "💡 If your password changed, update it: echo 'new_pass' > $CREDS_FILE"
    exit 1
fi
STATS=$(echo "$STATS" | jq '{
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

SYSTEM=$(pihole_api "/api/info/system")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch system info. Aborting."
    exit 1
fi
SYSTEM=$(echo "$SYSTEM" | jq '{
    cpu: {"%cpu": .system.cpu["%cpu"]},
    memory: {ram: {"%used": .system.memory.ram["%used"]}},
    uptime: .system.uptime
}')

SENSORS=$(pihole_api "/api/info/sensors")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch sensor data. Aborting."
    exit 1
fi
SENSORS=$(echo "$SENSORS" | jq '{
    cpu_temp: .sensors.cpu_temp,
    unit: .sensors.unit
}')

HOST=$(pihole_api "/api/info/host")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch host info. Aborting."
    exit 1
fi
HOST=$(echo "$HOST" | jq '{
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
    echo ""
    echo "First run detected - sending History"
    LAST_CHART="domains"
else
    LAST_CHART=$(cat "$STATE_FILE")
fi

# Alternate between History and Domains
if [ "$LAST_CHART" = "domains" ]; then
    echo ""
    echo "Fetching history data..."
    HISTORY=$(pihole_api "/api/history")
    if [ $? -ne 0 ]; then
        echo "❌ Failed to fetch history. Skipping."
    else
        HISTORY=$(echo "$HISTORY" | jq '{history: .history[-4:]}')

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
    fi

else
    echo ""
    echo "Fetching domains data..."
    DOMAINS=$(pihole_api "/api/stats/top_domains?blocked=true")
    if [ $? -ne 0 ]; then
        echo "❌ Failed to fetch domains. Skipping."
    else
        DOMAINS=$(echo "$DOMAINS" | jq '{domains: .domains[0:10]}')

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
fi

# Invalidate session when done
if [ -n "$AUTH_SID" ]; then
    curl -s -X DELETE "$BASE_URL/api/auth" -H "X-FTL-SID: $AUTH_SID" > /dev/null 2>&1
    echo "🔐 Session closed"
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

# Function for authenticated API calls during setup
SETUP_SID=""
setup_auth() {
    if [ -z "$PIHOLE_PASSWORD" ]; then
        return 0
    fi

    local resp
    resp=$(curl -s -X POST "$BASE_URL/api/auth" \
        -H "Content-Type: application/json" \
        -d "{\"password\": \"$PIHOLE_PASSWORD\"}")
    SETUP_SID=$(echo "$resp" | jq -r '.session.sid // empty')

    if [ -n "$SETUP_SID" ]; then
        return 0
    fi
    return 1
}

setup_api() {
    local endpoint=$1
    local response
    if [ -n "$SETUP_SID" ]; then
        response=$(curl -s "$BASE_URL$endpoint" -H "X-FTL-SID: $SETUP_SID")
    else
        response=$(curl -s "$BASE_URL$endpoint")
    fi

    # Validate response
    local error_key
    error_key=$(echo "$response" | jq -r '.error.key // empty' 2>/dev/null)
    if [ -n "$error_key" ]; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"' 2>/dev/null)
        echo "❌ Pi-hole API error for $endpoint: $error_msg" >&2
        return 1
    fi

    if [ -z "$response" ]; then
        echo "❌ Empty response from Pi-hole for $endpoint" >&2
        return 1
    fi

    echo "$response"
    return 0
}

setup_auth

{
echo "=========================================="
echo "$(date '+%Y-%m-%d %H:%M:%S') - Initial Setup"
echo "=========================================="
echo ""

# Fetch all data with auth and validation
STATS=$(setup_api "/api/stats/summary")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch stats. Check your Pi-hole connection and password."
    exit 1
fi
STATS=$(echo "$STATS" | jq '{
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

SYSTEM=$(setup_api "/api/info/system")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch system info."
    exit 1
fi
SYSTEM=$(echo "$SYSTEM" | jq '{system: {cpu: {"%cpu": .system.cpu["%cpu"]}, memory: {ram: {"%used": .system.memory.ram["%used"]}}, uptime: .system.uptime}}')

SENSORS=$(setup_api "/api/info/sensors")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch sensor data."
    exit 1
fi
SENSORS=$(echo "$SENSORS" | jq '{sensors: {cpu_temp: .sensors.cpu_temp, unit: .sensors.unit}}')

HOST=$(setup_api "/api/info/host")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch host info."
    exit 1
fi
HOST=$(echo "$HOST" | jq '{host: {uname: {nodename: .host.uname.nodename}}}')

HISTORY=$(setup_api "/api/history")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch history."
    exit 1
fi
HISTORY=$(echo "$HISTORY" | jq '{history: .history[-4:]}')

DOMAINS=$(setup_api "/api/stats/top_domains?blocked=true")
if [ $? -ne 0 ]; then
    echo "❌ Failed to fetch domains."
    exit 1
fi
DOMAINS=$(echo "$DOMAINS" | jq '{domains: .domains[0:10]}')

# Send Stats
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

# Cleanup setup auth session
if [ -n "$SETUP_SID" ]; then
    curl -s -X DELETE "$BASE_URL/api/auth" -H "X-FTL-SID: $SETUP_SID" > /dev/null 2>&1
fi

# Create initial state file
echo "domains" > "$STATE_FILE"

echo ""
echo "✅ Initial data structure established!"

# Cron setup
echo ""
echo "======================================"
echo "Cron Setup"
echo "======================================"
echo ""
echo "Recommended: Run every 15 minutes"
echo "This will update:"
echo "  - Stats/System/Sensors: Every 15 min"
echo "  - History: Every 30 min (alternating)"
echo "  - Domains: Every 30 min (alternating)"
echo ""
echo "Update frequency (in minutes) [default: 15]:"
echo "(Choose: 5, 10, 15, 20, or 30)"
read -r FREQUENCY
FREQUENCY=${FREQUENCY:-15}

if [[ ! "$FREQUENCY" =~ ^(5|10|15|20|30)$ ]]; then
    echo "⚠️  Invalid frequency. Using default: 15 minutes"
    FREQUENCY=15
fi

# Remove any old cron jobs
crontab -l 2>/dev/null | grep -v "push-pihole-to-trmnl.sh" | crontab - 2>/dev/null

# Add new cron job
(crontab -l 2>/dev/null; echo "*/$FREQUENCY * * * * $SCRIPT_PATH") | crontab -

echo ""
echo "✅ Cron job added! Updates every $FREQUENCY minutes."

echo ""
echo "======================================"
echo "✅ Installation Complete!"
echo "======================================"
echo ""
echo "Your Pi-hole dashboard is now connected to TRMNL!"
echo ""
echo "Configuration:"
echo "  - Pi-hole URL: $BASE_URL"
if [ -f "$CREDS_FILE" ]; then
echo "  - Auth: Enabled (credentials at $CREDS_FILE)"
else
echo "  - Auth: Not required"
fi
echo "  - State file: $STATE_FILE"
echo "  - Log file: $LOG_PATH"
echo "  - Update frequency: Every $FREQUENCY minutes"
echo ""
echo "Useful commands:"
echo "  - Manual run:         $SCRIPT_PATH"
echo "  - View logs:          tail -f $LOG_PATH"
echo "  - Check state:        cat $STATE_FILE"
if [ -f "$CREDS_FILE" ]; then
echo "  - Update password:    echo 'new_pass' > $CREDS_FILE"
fi
echo "  - Edit cron:          crontab -e"
