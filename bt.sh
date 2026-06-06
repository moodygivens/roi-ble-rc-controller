#!/bin/bash

ACTION="show"

# Check if a parameter was provided
if [ ! -z "$1" ]; then
    if [ "$1" == "-on" ]; then
        ACTION="on"
    elif [ "$1" == "-off" ]; then
        ACTION="off"
    else
        echo "Error: Invalid parameter '$1'."
        echo "Usage: ./bt.sh | ./bt.sh -on | ./bt.sh -off"
        exit 1
    fi
fi

# Execute actions if requested
if [ "$ACTION" == "on" ]; then
    echo "=========================================="
    echo "ACTIVATING BLE CAR TESTING RECEIVER..."
    echo "=========================================="
    
    # 1. Restart the system service
    sudo systemctl restart bluetooth
    
    # 2. Loop: Wait until the Bluetooth controller hardware is responsive
    COUNTER=0
    MAX_ATTEMPTS=10
    while ! bluetoothctl show &>/dev/null; do
        COUNTER=$((COUNTER+1))
        if [ "$COUNTER" -gt "$MAX_ATTEMPTS" ]; then
            echo "Debug Error: Bluetooth service failed to respond."
            exit 1
        fi
        echo "Waiting for Bluetooth hardware... (Attempt $COUNTER/$MAX_ATTEMPTS)"
        sleep 0.5
    done

    # 3. Power on the adapter first
    bluetoothctl power on > /dev/null
    sleep 0.2
    
    # 4. Turn on Nordic UART Advertising FIRST so it stops overriding our later flags
    echo -e "menu advertise\nuuids 6e400001-b5a3-f393-e0a9-e50e24dcca9e\nback\nadvertise on\nquit" | bluetoothctl > /dev/null
    sleep 0.3

    # 5. Loop: Force and verify Discoverable state flips to YES
    COUNTER=0
    while [ "$(bluetoothctl show | grep -c "Discoverable: yes")" -eq 0 ]; do
        COUNTER=$((COUNTER+1))
        if [ "$COUNTER" -gt "$MAX_ATTEMPTS" ]; then
            echo "Debug Error: Controller stuck on Discoverable: no."
            exit 1
        fi
        echo "Waiting for Discoverable state... (Attempt $COUNTER/$MAX_ATTEMPTS)"
        bluetoothctl discoverable yes > /dev/null
        sleep 0.3
    done

    # 6. Loop: Force and verify Pairable state flips to YES
    COUNTER=0
    while [ "$(bluetoothctl show | grep -c "Pairable: yes")" -eq 0 ]; do
        COUNTER=$((COUNTER+1))
        if [ "$COUNTER" -gt "$MAX_ATTEMPTS" ]; then
            echo "Debug Error: Controller stuck on Pairable: no."
            exit 1
        fi
        echo "Waiting for Pairable state... (Attempt $COUNTER/$MAX_ATTEMPTS)"
        bluetoothctl pairable yes > /dev/null
        sleep 0.3
    done

elif [ "$ACTION" == "off" ]; then
    echo "=========================================="
    echo "DEACTIVATING & SECURING BLUETOOTH..."
    echo "=========================================="
    sudo systemctl restart bluetooth
    sleep 0.5
    bluetoothctl discoverable no > /dev/null
    bluetoothctl pairable no > /dev/null
fi

# ==================================================
# ANALYZE & DUMP STATUS
# ==================================================
RAW_STATUS=$(bluetoothctl show)

POWERED=$(echo "$RAW_STATUS" | grep -q "Powered: yes" && echo "YES" || echo "NO")
DISCOVERABLE=$(echo "$RAW_STATUS" | grep -q "Discoverable: yes" && echo "YES" || echo "NO")
PAIRABLE=$(echo "$RAW_STATUS" | grep -q "Pairable: yes" && echo "YES" || echo "NO")
ADVERTISING=$(echo "$RAW_STATUS" | grep -q "ActiveInstances: 0x01" && echo "YES" || echo "NO")

echo ""
echo "--- LAPTOP BLE STATUS ANALYSIS ---"
echo "Radio Powered On:   $POWERED"
echo "Visible to Phone:   $DISCOVERABLE"
echo "Accepts Pairing:    $PAIRABLE"
echo "BLE Broadcasting:   $ADVERTISING"
echo "----------------------------------"

# Final overall evaluation block
if [ "$POWERED" == "YES" ] && [ "$DISCOVERABLE" == "YES" ] && [ "$PAIRABLE" == "YES" ] && [ "$ADVERTISING" == "YES" ]; then
    echo "RESULT: 👉 Laptop is PERFECTLY WAITING for your phone connection."
elif [ "$DISCOVERABLE" == "NO" ] && [ "$ADVERTISING" == "NO" ]; then
    echo "RESULT: 👉 Laptop is SECURE and invisible to outside devices."
else
    echo "RESULT: ⚠️ Warning: Laptop is in an inconsistent interim state."
fi
echo ""