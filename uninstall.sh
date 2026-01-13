#!/bin/bash

echo "=================================================="
echo "Pi-hole TRMNL Plugin Uninstaller"
echo "=================================================="
echo ""

# Check if script exists
if [ -f ~/push-pihole-to-trmnl.sh ]; then
    echo "✓ Found script at ~/push-pihole-to-trmnl.sh"
    SCRIPT_EXISTS=true
else
    echo "⚠ Script not found at ~/push-pihole-to-trmnl.sh"
    SCRIPT_EXISTS=false
fi

# Check if cron job exists
if crontab -l 2>/dev/null | grep -q "push-pihole-to-trmnl.sh"; then
    echo "✓ Found cron job"
    CRON_EXISTS=true
else
    echo "⚠ Cron job not found"
    CRON_EXISTS=false
fi

# Check if state file exists
if [ -f ~/.pihole-trmnl-state ]; then
    echo "✓ Found state file at ~/.pihole-trmnl-state"
    STATE_EXISTS=true
else
    echo "⚠ State file not found"
    STATE_EXISTS=false
fi

# Check if log file exists
if [ -f ~/trmnl-push.log ]; then
    echo "✓ Found log file at ~/trmnl-push.log"
    LOG_EXISTS=true
else
    echo "⚠ Log file not found"
    LOG_EXISTS=false
fi

echo ""

# If nothing to uninstall
if [ "$SCRIPT_EXISTS" = false ] && [ "$CRON_EXISTS" = false ] && [ "$STATE_EXISTS" = false ] && [ "$LOG_EXISTS" = false ]; then
    echo "Nothing to uninstall. Plugin appears to be already removed."
    exit 0
fi

# Confirm uninstall
echo "This will remove:"
[ "$SCRIPT_EXISTS" = true ] && echo "  - Script: ~/push-pihole-to-trmnl.sh"
[ "$CRON_EXISTS" = true ] && echo "  - Cron job"
[ "$STATE_EXISTS" = true ] && echo "  - State file: ~/.pihole-trmnl-state"
[ "$LOG_EXISTS" = true ] && echo "  - Log file: ~/trmnl-push.log"
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

# Remove cron job
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

echo ""
echo "=================================================="
echo "Uninstall complete!"
echo "=================================================="
echo ""
echo "Your Pi-hole continues to run normally."
echo "The TRMNL plugin has been completely removed."
echo ""
