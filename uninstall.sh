#!/bin/bash

echo "=================================================="
echo "Pi-hole TRMNL Plugin Uninstaller"
echo "(v0.2.0)"
echo "=================================================="
echo ""

# Check for all installed components
SCRIPT_EXISTS=false
CRON_EXISTS=false
STATE_EXISTS=false
LOG_EXISTS=false
CREDS_EXISTS=false

if [ -f ~/push-pihole-to-trmnl.sh ]; then
    echo "✓ Found script at ~/push-pihole-to-trmnl.sh"
    SCRIPT_EXISTS=true
else
    echo "⚠ Script not found at ~/push-pihole-to-trmnl.sh"
fi

if crontab -l 2>/dev/null | grep -q "push-pihole-to-trmnl.sh"; then
    echo "✓ Found cron job"
    CRON_EXISTS=true
else
    echo "⚠ Cron job not found"
fi

if [ -f ~/.pihole-trmnl-state ]; then
    echo "✓ Found state file at ~/.pihole-trmnl-state"
    STATE_EXISTS=true
else
    echo "⚠ State file not found"
fi

if [ -f ~/trmnl-push.log ]; then
    echo "✓ Found log file at ~/trmnl-push.log"
    LOG_EXISTS=true
else
    echo "⚠ Log file not found"
fi

if [ -f ~/.pihole-trmnl-creds ]; then
    echo "✓ Found credentials file at ~/.pihole-trmnl-creds"
    CREDS_EXISTS=true
else
    echo "⚠ Credentials file not found"
fi

echo ""

# If nothing to uninstall
if [ "$SCRIPT_EXISTS" = false ] && [ "$CRON_EXISTS" = false ] && [ "$STATE_EXISTS" = false ] && [ "$LOG_EXISTS" = false ] && [ "$CREDS_EXISTS" = false ]; then
    echo "Nothing to uninstall. Plugin appears to be already removed."
    exit 0
fi

# Confirm uninstall
echo "This will remove:"
[ "$CRON_EXISTS" = true ] && echo "  - Cron job"
[ "$SCRIPT_EXISTS" = true ] && echo "  - Script: ~/push-pihole-to-trmnl.sh"
[ "$STATE_EXISTS" = true ] && echo "  - State file: ~/.pihole-trmnl-state"
[ "$LOG_EXISTS" = true ] && echo "  - Log file: ~/trmnl-push.log"
[ "$CREDS_EXISTS" = true ] && echo "  - Credentials file: ~/.pihole-trmnl-creds"
echo ""
echo "⚠️  This does NOT affect your Pi-hole installation or settings."
echo ""
read -p "Continue? (y/n) " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Uninstalling..."
echo ""

# Remove cron job first (stops future runs)
if [ "$CRON_EXISTS" = true ]; then
    crontab -l | grep -v "push-pihole-to-trmnl.sh" | crontab -
    if crontab -l 2>/dev/null | grep -q "push-pihole-to-trmnl.sh"; then
        echo "❌ Failed to remove cron job"
    else
        echo "✓ Removed cron job"
    fi
fi

# Remove script
if [ "$SCRIPT_EXISTS" = true ]; then
    rm ~/push-pihole-to-trmnl.sh
    if [ -f ~/push-pihole-to-trmnl.sh ]; then
        echo "❌ Failed to remove script"
    else
        echo "✓ Removed script"
    fi
fi

# Remove state file
if [ "$STATE_EXISTS" = true ]; then
    rm ~/.pihole-trmnl-state
    if [ -f ~/.pihole-trmnl-state ]; then
        echo "❌ Failed to remove state file"
    else
        echo "✓ Removed state file"
    fi
fi

# Remove log file
if [ "$LOG_EXISTS" = true ]; then
    rm ~/trmnl-push.log
    if [ -f ~/trmnl-push.log ]; then
        echo "❌ Failed to remove log file"
    else
        echo "✓ Removed log file"
    fi
fi

# Remove credentials file
if [ "$CREDS_EXISTS" = true ]; then
    rm ~/.pihole-trmnl-creds
    if [ -f ~/.pihole-trmnl-creds ]; then
        echo "❌ Failed to remove credentials file"
    else
        echo "✓ Removed credentials file"
    fi
fi

echo ""
echo "=================================================="
echo "✅ Uninstall complete!"
echo "=================================================="
echo ""
echo "Your Pi-hole continues to run normally."
echo "The TRMNL plugin has been completely removed."
echo ""
echo "To reinstall later, run:"
echo "  bash install.sh"
echo ""
