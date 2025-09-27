#!/bin/bash -e
# S-Curve Approximation using Piecewise Linear Functions

CONFIG_FILE="/etc/fan.json"
FAN_PATH="/sys/devices/pwm-fan/target_pwm"
TEMP_PATH="/sys/devices/virtual/thermal/thermal_zone0/temp"

# Piecewise Curve Constants
PWM_BREAKPOINT_1=$(( 255 * 10 / 100 ))	# Zone 1 ends at 10% PWM
PWM_BREAKPOINT_2=$(( 255 * 80 / 100 ))	# Zone 2 ends at 80% PWM (80% to 100% is the final steep zone)

if ! command -v jq &> /dev/null; then
	echo "ERROR: jq is required but not installed!  please run 'sudo apt install jq'." >&2
	exit 1
fi

# extract values using jq, storing them directly into variables
FAN_OFF_TEMP=$(jq .FAN_OFF_TEMP "$CONFIG_FILE":=40)
FAN_MAX_TEMP=$(jq .FAN_MAX_TEMP "$CONFIG_FILE":=70)
UPDATE_INTERVAL=$(jq .UPDATE_INTERVAL "$CONFIG_FILE":=1)

# pre-calculate constants in milli-degrees Celsius (mC)
T_OFF_mC=$(( FAN_OFF_TEMP * 1000 ))
T_MAX_mC=$(( FAN_MAX_TEMP * 1000 ))
TEMP_RANGE_mC=$(( T_MAX_mC - T_OFF_mC ))

# calculate temperature breakpoints for the three zones (1/3rd and 2/3rds of the total range)
T_MID_1=$(( T_OFF_mC + TEMP_RANGE_mC / 3 ))
T_MID_2=$(( T_OFF_mC + 2 * TEMP_RANGE_mC / 3 ))




echo "automatic fan control service running"

last_spd=-1

while true; do
	temp_raw=$(cat "$TEMP_PATH" 2>/dev/null)
	current_spd=0

	# S-Curve Logic (Piecewise Linear)
	if [[ "$TEMP_RANGE_mC" -gt 0 ]] && [[ "$temp_raw" -gt "$T_OFF_mC" ]]; then

		# T_MID_2 to T_MAX
		if [[ "$temp_raw" -ge "$T_MID_2" ]]; then
			T_ZONE3=$(( T_MAX_mC - T_MID_2 ))

			if [[ "$T_ZONE3" -gt 0 ]]; then
				PWM_RANGE=$(( 255 - PWM_BREAKPOINT_2 ))
				numerator=$(( PWM_RANGE * (temp_raw - T_MID_2) ))
				current_spd=$(( PWM_BREAKPOINT_2 + numerator / T_ZONE3 ))
			else
				current_spd=$255
			fi

		# T_MID_1 to T_MID_2
		elif [[ "$temp_raw" -ge "$T_MID_1" ]]; then
			T_ZONE2=$(( T_MID_2 - T_MID_1 ))

			if [[ "$T_ZONE2" -gt 0 ]]; then
				PWM_RANGE=$(( PWM_BREAKPOINT_2 - PWM_BREAKPOINT_1 ))
				numerator=$(( PWM_RANGE * (temp_raw - T_MID_1) ))
				current_spd=$(( PWM_BREAKPOINT_1 + numerator / T_ZONE2 ))
			else
				current_spd=$PWM_BREAKPOINT_2
			fi

		# T_OFF to T_MID_1
		else
			T_ZONE1=$(( T_MID_1 - T_OFF_mC ))

			if [[ "$T_ZONE1" -gt 0 ]]; then
				PWM_RANGE=$PWM_BREAKPOINT_1
				numerator=$(( PWM_RANGE * (temp_raw - T_OFF_mC) ))
				current_spd=$(( numerator / T_ZONE1 ))
			else
				current_spd=0
			fi
		fi
	fi

	# final clamping
	if [[ "$current_spd" -lt 0 ]]; then
		current_spd=0
	elif [[ "$current_spd" -gt 255 ]]; then
		current_spd=255
	fi

	# only write if speed has changed
	if [[ "$current_spd" -ne "$last_spd" ]]; then
		echo "$current_spd" > "$FAN_PATH"
		last_spd="$current_spd"
	fi

	sleep "$UPDATE_INTERVAL"
done
