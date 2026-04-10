#!/usr/bin/env bash

# Paths
cache_dir="$HOME/.cache/quickshell/weather"
json_file="${cache_dir}/weather.json"
view_file="${cache_dir}/view_id"
daily_cache_file="${cache_dir}/daily_weather_cache.json"
next_day_cache_file="${cache_dir}/next_day_precache.json"
env_tracker_file="${cache_dir}/.env_tracker"
ENV_FILE="$(dirname "$0")/.env"

# API Settings
# Load environment variables silently
if [ -f "$ENV_FILE" ]; then
    export $(grep -v '^#' "$ENV_FILE" | xargs)
fi

# API Settings from .env
LAT="$OPENMETEO_LAT"
LON="$OPENMETEO_LON"
UNIT="${OPENMETEO_UNIT:-celsius}" # Default to celsius if not set

mkdir -p "${cache_dir}"

get_icon() {
    case $1 in
        0)             icon=""; quote="Sunny" ;;
        1|2|3)         icon=""; quote="Cloudy" ;;
        45|48)         icon=""; quote="Mist" ;;
        51|53|55|61|63|65|80|81|82) icon=""; quote="Rainy" ;;
        71|73|75|77)   icon=""; quote="Snow" ;;
        95|96|99)      icon=""; quote="Storm" ;;
        *)             icon=""; quote="Unknown" ;;
    esac
    echo "$icon|$quote"
}

get_hex() {
    case $1 in
        0) echo "#f9e2af" ;;
        1|2|3) echo "#bac2de" ;;
        45|48) echo "#84afdb" ;;
        51|53|55|61|63|65|80|81|82) echo "#74c7ec" ;;
        71|73|75|77) echo "#cdd6f4" ;;
        95|96|99) echo "#f9e2af" ;;
        *) echo "#cdd6f4" ;;
    esac
}

write_dummy_data() {
    final_json="["
    for i in {0..4}; do
        future_date=$(date -d "+$i days")
        f_day=$(date -d "$future_date" "+%a")
        f_full_day=$(date -d "$future_date" "+%A")
        f_date_num=$(date -d "$future_date" "+%d %b")
        
        final_json="${final_json} {
            \"id\": \"${i}\",
            \"day\": \"${f_day}\",
            \"day_full\": \"${f_full_day}\",
            \"date\": \"${f_date_num}\",
            \"max\": \"0.0\",
            \"min\": \"0.0\",
            \"feels_like\": \"0.0\",
            \"wind\": \"0\",
            \"humidity\": \"0\",
            \"pop\": \"0\",
            \"icon\": \"\",
            \"hex\": \"#cdd6f4\",
            \"desc\": \"No Coordinates\",
            \"hourly\": [{\"time\": \"00:00\", \"temp\": \"0.0\", \"icon\": \"\", \"hex\": \"#cdd6f4\"}]
        },"
    done
    final_json="${final_json%,}]"
    echo "{ \"forecast\": ${final_json} }" > "${json_file}"
}

get_data() {
    # ---------------------------------------------------------
    # DUMMY DATA FALLBACK (If coordinates are missing or skipped)
    # ---------------------------------------------------------
    if [[ -z "$LAT" || -z "$LON" || "$LAT" == "OPENMETEO_LAT" ]]; then
        write_dummy_data
        return
    fi

    # ---------------------------------------------------------
    # STANDARD API FETCH LOGIC
    # ---------------------------------------------------------
    forecast_url="https://api.open-meteo.com/v1/forecast?latitude=${LAT}&longitude=${LON}&hourly=temperature_2m,apparent_temperature,precipitation_probability,windspeed_10m,relativehumidity_2m,weathercode&daily=weathercode,temperature_2m_max,temperature_2m_min,precipitation_probability_max,windspeed_10m_max&temperature_unit=${UNIT}&windspeed_unit=kmh&forecast_days=5&timezone=auto"
    raw_api=$(curl -sf "$forecast_url")

    # Check if curl failed OR if Open-Meteo returned an error
    if [ -z "$raw_api" ] || echo "$raw_api" | jq -e '.error' &>/dev/null; then
        write_dummy_data
        return
    fi

    current_date=$(date +%Y-%m-%d)
    tomorrow_date=$(date -d "tomorrow" +%Y-%m-%d)

    # 1. ROLLOVER CHECK
    if [ -f "$next_day_cache_file" ]; then
        precache_date=$(cat "$next_day_cache_file" | jq -r '.[0].time' | cut -dT -f1)
        if [ "$precache_date" == "$current_date" ]; then
            mv "$next_day_cache_file" "$daily_cache_file"
        fi
    fi

    # 2. PROCESS TODAY
    api_today_items=$(echo "$raw_api" | jq -c ". as \$root | [
        range(.hourly.time | length) | . as \$i |
        select(\$root.hourly.time[\$i] | startswith(\"$current_date\")) |
        {
            time: \$root.hourly.time[\$i],
            temp: \$root.hourly.temperature_2m[\$i],
            feels_like: \$root.hourly.apparent_temperature[\$i],
            wind: \$root.hourly.windspeed_10m[\$i],
            humidity: \$root.hourly.relativehumidity_2m[\$i],
            pop: \$root.hourly.precipitation_probability[\$i],
            weathercode: \$root.hourly.weathercode[\$i]
        }
    ]")

    if [ -f "$daily_cache_file" ]; then
        cached_date=$(cat "$daily_cache_file" | jq -r '.[0].time' | cut -dT -f1)
        if [ "$cached_date" == "$current_date" ]; then
            merged_today=$(echo "$api_today_items" | jq --slurpfile cache "$daily_cache_file" \
                '($cache[0] + .) | unique_by(.time) | sort_by(.time)')
        else
            merged_today="$api_today_items"
        fi
    else
        merged_today="$api_today_items"
    fi

    echo "$merged_today" > "$daily_cache_file"

    # 3. PRE-CACHE TOMORROW
    api_tomorrow_items=$(echo "$raw_api" | jq -c ". as \$root | [
        range(.hourly.time | length) | . as \$i |
        select(\$root.hourly.time[\$i] | startswith(\"$tomorrow_date\")) |
        {
            time: \$root.hourly.time[\$i],
            temp: \$root.hourly.temperature_2m[\$i],
            feels_like: \$root.hourly.apparent_temperature[\$i],
            wind: \$root.hourly.windspeed_10m[\$i],
            humidity: \$root.hourly.relativehumidity_2m[\$i],
            pop: \$root.hourly.precipitation_probability[\$i],
            weathercode: \$root.hourly.weathercode[\$i]
        }
    ]")
    echo "$api_tomorrow_items" > "$next_day_cache_file"

    # 4. BUILD FINAL JSON
    if [ ! -z "$raw_api" ]; then
        final_json="["
        counter=0

        for i in $(seq 0 4); do
            d=$(echo "$raw_api" | jq -r ".daily.time[$i]")
            [ "$d" == "null" ] && continue

            wmo_code=$(echo "$raw_api" | jq -r ".daily.weathercode[$i]")

            raw_max=$(echo "$raw_api" | jq -r ".daily.temperature_2m_max[$i]")
            f_max_temp=$(printf "%.1f" "$raw_max")

            raw_min=$(echo "$raw_api" | jq -r ".daily.temperature_2m_min[$i]")
            f_min_temp=$(printf "%.1f" "$raw_min")

            # Use today's merged hourly cache for feels_like, otherwise pull from hourly array
            if [ "$d" == "$current_date" ] && [ -f "$daily_cache_file" ]; then
                raw_feels=$(cat "$daily_cache_file" | jq '[.[].feels_like] | max')
            else
                raw_feels=$(echo "$raw_api" | jq ". as \$root | [
                    range(.hourly.time | length) | . as \$i |
                    select(\$root.hourly.time[\$i] | startswith(\"$d\")) |
                    \$root.hourly.apparent_temperature[\$i]
                ] | max")
            fi
            f_feels_like=$(printf "%.1f" "$raw_feels")

            f_pop_pct=$(echo "$raw_api" | jq -r ".daily.precipitation_probability_max[$i]")
            f_wind=$(echo "$raw_api" | jq -r ".daily.windspeed_10m_max[$i] | round")

            # Humidity comes from hourly — average across the day
            f_hum=$(echo "$raw_api" | jq ". as \$root | [
                range(.hourly.time | length) | . as \$i |
                select(\$root.hourly.time[\$i] | startswith(\"$d\")) |
                \$root.hourly.relativehumidity_2m[\$i]
            ] | add / length | round")

            f_icon_data=$(get_icon "$wmo_code")
            f_icon=$(echo "$f_icon_data" | cut -d'|' -f1)
            f_desc=$(echo "$f_icon_data" | cut -d'|' -f2)
            f_hex=$(get_hex "$wmo_code")

            f_day=$(date -d "$d" "+%a")
            f_full_day=$(date -d "$d" "+%A")
            f_date_num=$(date -d "$d" "+%d %b")

            # Build hourly slots — use merged cache for today, raw API for other days
            if [ "$d" == "$current_date" ] && [ -f "$daily_cache_file" ]; then
                hourly_source=$(cat "$daily_cache_file")
                count_slots=$(echo "$hourly_source" | jq '. | length - 1')
                hourly_json="["
                for j in $(seq 0 1 $count_slots); do
                    slot_item=$(echo "$hourly_source" | jq ".[$j]")
                    raw_s_temp=$(echo "$slot_item" | jq ".temp")
                    s_temp=$(printf "%.1f" "$raw_s_temp")
                    s_time=$(echo "$slot_item" | jq -r ".time" | cut -dT -f2 | cut -d: -f1,2)
                    s_code=$(echo "$slot_item" | jq -r ".weathercode")
                    s_hex=$(get_hex "$s_code")
                    s_icon=$(get_icon "$s_code" | cut -d'|' -f1)
                    hourly_json="${hourly_json} {\"time\": \"${s_time}\", \"temp\": \"${s_temp}\", \"icon\": \"${s_icon}\", \"hex\": \"${s_hex}\"},"
                done
            else
                hourly_indices=$(echo "$raw_api" | jq -r ". as \$root | [
                    range(.hourly.time | length) | . as \$i |
                    select(\$root.hourly.time[\$i] | startswith(\"$d\")) |
                    \$i
                ][]")
                hourly_json="["
                for j in $hourly_indices; do
                    raw_s_temp=$(echo "$raw_api" | jq -r ".hourly.temperature_2m[$j]")
                    s_temp=$(printf "%.1f" "$raw_s_temp")
                    s_time=$(echo "$raw_api" | jq -r ".hourly.time[$j]" | cut -dT -f2 | cut -d: -f1,2)
                    s_code=$(echo "$raw_api" | jq -r ".hourly.weathercode[$j]")
                    s_hex=$(get_hex "$s_code")
                    s_icon=$(get_icon "$s_code" | cut -d'|' -f1)
                    hourly_json="${hourly_json} {\"time\": \"${s_time}\", \"temp\": \"${s_temp}\", \"icon\": \"${s_icon}\", \"hex\": \"${s_hex}\"},"
                done
            fi
            hourly_json="${hourly_json%,}]"

            final_json="${final_json} {
                \"id\": \"${counter}\",
                \"day\": \"${f_day}\",
                \"day_full\": \"${f_full_day}\",
                \"date\": \"${f_date_num}\",
                \"max\": \"${f_max_temp}\",
                \"min\": \"${f_min_temp}\",
                \"feels_like\": \"${f_feels_like}\",
                \"wind\": \"${f_wind}\",
                \"humidity\": \"${f_hum}\",
                \"pop\": \"${f_pop_pct}\",
                \"icon\": \"${f_icon}\",
                \"hex\": \"${f_hex}\",
                \"desc\": \"${f_desc}\",
                \"hourly\": ${hourly_json}
            },"
            ((counter++))
        done
        final_json="${final_json%,}]"

        echo "{ \"forecast\": ${final_json} }" > "${json_file}"
    fi
}

# --- MODE HANDLING ---
if [[ "$1" == "--getdata" ]]; then
    get_data

elif [[ "$1" == "--json" ]]; then
    CACHE_LIMIT=900          # 15 minutes for valid working data

    # Check if .env file has been modified since we last checked
    env_changed=0
    if [ -f "$ENV_FILE" ]; then
        env_mtime=$(stat -c %Y "$ENV_FILE")
        last_env_mtime=$(cat "$env_tracker_file" 2>/dev/null || echo "0")
        
        if [ "$env_mtime" -gt "$last_env_mtime" ]; then
            env_changed=1
            echo "$env_mtime" > "$env_tracker_file"
        fi
    fi

    if [ -f "$json_file" ]; then
        file_time=$(stat -c %Y "$json_file")
        current_time=$(date +%s)
        diff=$((current_time - file_time))
        
        if [ "$env_changed" -eq 1 ]; then
            # The user just modified the .env file. Bypass cache entirely.
            touch "$json_file"
            get_data &
        else
            # Open-Meteo needs no key activation wait. Check every 15 mins.
            if [ $diff -gt $CACHE_LIMIT ]; then
                touch "$json_file"
                get_data &
            fi
        fi
        cat "$json_file"
    else
        get_data
        cat "$json_file"
    fi

elif [[ "$1" == "--view-listener" ]]; then
    if [ ! -f "$view_file" ]; then echo "0" > "$view_file"; fi
    tail -F "$view_file"

elif [[ "$1" == "--nav" ]]; then
    if [ ! -f "$view_file" ]; then echo "0" > "$view_file"; fi
    current=$(cat "$view_file")
    direction=$2
    max_idx=4
    if [[ "$direction" == "next" ]]; then
        if [ "$current" -lt "$max_idx" ]; then
            new=$((current + 1))
            echo "$new" > "$view_file"
        fi
    elif [[ "$direction" == "prev" ]]; then
        if [ "$current" -gt 0 ]; then
            new=$((current - 1))
            echo "$new" > "$view_file"
        fi
    fi

elif [[ "$1" == "--icon" ]]; then
    [ ! -f "$json_file" ] && get_data
    cat "$json_file" | jq -r '.forecast[0].icon'

elif [[ "$1" == "--temp" ]]; then 
    [ ! -f "$json_file" ] && get_data
    t=$(cat "$json_file" | jq -r '.forecast[0].max')
    echo "${t}°C"

elif [[ "$1" == "--hex" ]]; then 
    [ ! -f "$json_file" ] && get_data
    cat "$json_file" | jq -r '.forecast[0].hex'

# --- NEW HOURLY MODES FOR TOPBAR ---
elif [[ "$1" == "--current-icon" ]]; then
    [ ! -f "$json_file" ] && get_data
    curr_time=$(date +%H:%M)
    cat "$json_file" | jq -r --arg ct "$curr_time" '(.forecast[0].hourly | map(select(.time <= $ct)) | last) // .forecast[0].hourly[0] | .icon'

elif [[ "$1" == "--current-temp" ]]; then 
    [ ! -f "$json_file" ] && get_data
    curr_time=$(date +%H:%M)
    t=$(cat "$json_file" | jq -r --arg ct "$curr_time" '(.forecast[0].hourly | map(select(.time <= $ct)) | last) // .forecast[0].hourly[0] | .temp')
    echo "${t}°C"

elif [[ "$1" == "--current-hex" ]]; then
    [ ! -f "$json_file" ] && get_data
    curr_time=$(date +%H:%M)
    cat "$json_file" | jq -r --arg ct "$curr_time" '(.forecast[0].hourly | map(select(.time <= $ct)) | last) // .forecast[0].hourly[0] | .hex'
fi