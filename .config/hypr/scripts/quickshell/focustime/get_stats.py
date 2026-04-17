#!/usr/bin/env python3
import sqlite3
import json
import os
import argparse
import calendar
import re
from datetime import date, timedelta
from collections import defaultdict

DB_PATH = os.path.expanduser("~/.local/share/focustime/focustime.db")

DESKTOP_CACHE_NAME = {}
DESKTOP_CACHE_ICON = {}
CACHE_BUILT = False
SYSTEM_STATES = {"Desktop", "Locked", "Quickshell", "Unknown"}

def get_xdg_search_dirs():
    search_dirs = []
    xdg_data_home = os.environ.get("XDG_DATA_HOME", os.path.expanduser("~/.local/share"))
    search_dirs.append(os.path.join(xdg_data_home, "applications"))
    
    xdg_data_dirs = os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share")
    for d in xdg_data_dirs.split(":"):
        if d.strip():
            search_dirs.append(os.path.join(d, "applications"))

    fallback_dirs = [
        "/var/lib/flatpak/exports/share/applications",
        "/var/lib/snapd/desktop/applications"
    ]
    for d in fallback_dirs:
        if d not in search_dirs:
            search_dirs.append(d)
    return search_dirs

def build_desktop_cache():
    global CACHE_BUILT
    if CACHE_BUILT: return
    
    for directory in get_xdg_search_dirs():
        if not os.path.exists(directory): continue
        try:
            for f in os.listdir(directory):
                if f.endswith(".desktop"):
                    path = os.path.join(directory, f)
                    try:
                        name, icon, wmclass = None, "", None
                        with open(path, 'r', encoding='utf-8') as file:
                            for line in file:
                                line = line.strip()
                                if line.startswith("Name=") and not name:
                                    name = line.split("=", 1)[1].strip()
                                elif line.startswith("Icon=") and not icon:
                                    icon = line.split("=", 1)[1].strip()
                                elif line.startswith("StartupWMClass="):
                                    wmclass = line.split("=", 1)[1].strip().lower()
                        
                        if name:
                            base = f[:-8].lower()
                            DESKTOP_CACHE_NAME[base] = name
                            DESKTOP_CACHE_ICON[base] = icon
                            if wmclass:
                                DESKTOP_CACHE_NAME[wmclass] = name
                                DESKTOP_CACHE_ICON[wmclass] = icon
                    except Exception:
                        pass
        except Exception:
            pass
    CACHE_BUILT = True

def get_app_icon(app_class):
    if not app_class or app_class in SYSTEM_STATES:
        return ""
        
    build_desktop_cache()
    
    app_class_lower = app_class.lower()
    base_class = re.sub(r'[-_ ]?updater$', '', app_class_lower)
    base_class = base_class.replace('.exe', '')

    if app_class_lower in DESKTOP_CACHE_ICON: return DESKTOP_CACHE_ICON[app_class_lower]
    if base_class in DESKTOP_CACHE_ICON: return DESKTOP_CACHE_ICON[base_class]
    return ""

def build_query(base_query, date_params, app_filter):
    if app_filter: return base_query + " AND app_class = ?", date_params + (app_filter,)
    return base_query, date_params

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("date", nargs="?", default=date.today().isoformat())
    parser.add_argument("--app", type=str, default=None, help="Filter stats by app_class")
    args = parser.parse_args()

    target_date_str = args.date
    app_filter = args.app

    try:
        target_date = date.fromisoformat(target_date_str)
    except ValueError:
        target_date = date.today()

    if not os.path.exists(DB_PATH):
        print(json.dumps({
            "total": 0, "average": 0, "week_range": "", "yesterday": 0, "current": "History", 
            "apps": [], "week_apps": [], "week": [], "month": [], "hourly": [0]*48, "week_heatmap": [[0]*24 for _ in range(7)], "peak_usage_str": "N/A"
        }))
        return

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    yesterday = target_date - timedelta(days=1)
    q, p = build_query('SELECT SUM(seconds) FROM focus_log WHERE log_date = ?', (yesterday.isoformat(),), app_filter)
    c.execute(q, p)
    yesterday_seconds = c.fetchone()[0] or 0

    monday = target_date - timedelta(days=target_date.weekday())
    sunday = monday + timedelta(days=6)
    week_range_str = f"{monday.strftime('%b')} {monday.day} - {sunday.strftime('%b')} {sunday.day}"

    q, p = build_query('''SELECT COUNT(DISTINCT log_date), SUM(seconds) FROM focus_log 
                          WHERE log_date >= ? AND log_date <= ? AND seconds > 0''', (monday.isoformat(), sunday.isoformat()), app_filter)
    c.execute(q, p)
    row = c.fetchone()
    days_count = row[0] or 0
    total_week = row[1] or 0
    average_seconds = total_week // days_count if days_count > 0 else 0

    q, p = build_query('SELECT SUM(seconds) FROM focus_log WHERE log_date = ?', (target_date.isoformat(),), app_filter)
    c.execute(q, p)
    total_seconds = c.fetchone()[0] or 0

    q, p = build_query('''SELECT app_class, COALESCE(app_title, app_class), SUM(seconds) as secs 
                          FROM focus_log WHERE log_date = ?''', (target_date.isoformat(),), app_filter)
    c.execute(q + " GROUP BY app_class ORDER BY secs DESC", p)
    
    all_apps = []
    for row in c.fetchall():
        app_class, app_title, secs = row
        all_apps.append({
            "class": app_class, "name": app_title, "icon": get_app_icon(app_class),
            "seconds": secs, "percent": round((secs / total_seconds) * 100, 1) if total_seconds > 0 else 0
        })

    q, p = build_query('''SELECT app_class, COALESCE(app_title, app_class), SUM(seconds) as secs 
                          FROM focus_log WHERE log_date >= ? AND log_date <= ?''', (monday.isoformat(), sunday.isoformat()), app_filter)
    c.execute(q + " GROUP BY app_class ORDER BY secs DESC LIMIT 50", p)
    week_apps_rows = c.fetchall()
    week_apps_total = sum([r[2] for r in week_apps_rows])
    week_apps = []
    for r in week_apps_rows:
        cls, title, secs = r
        week_apps.append({
            "class": cls, "name": title, "icon": get_app_icon(cls),
            "seconds": secs, "percent": round((secs / week_apps_total) * 100, 1) if week_apps_total > 0 else 0
        })

    # BULK QUERY FOR WEEK
    q, p = build_query('SELECT log_date, SUM(seconds) FROM focus_log WHERE log_date >= ? AND log_date <= ?', 
                       (monday.isoformat(), sunday.isoformat()), app_filter)
    c.execute(q + " GROUP BY log_date", p)
    week_map = {r[0]: r[1] for r in c.fetchall()}
    
    week_data = []
    days_str = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
    for i in range(7):
        d_str = (monday + timedelta(days=i)).isoformat()
        week_data.append({"date": d_str, "day": days_str[i], "total": week_map.get(d_str, 0), "is_target": d_str == target_date_str})

    # BULK QUERY FOR MONTH
    first_day = target_date.replace(day=1)
    _, num_days = calendar.monthrange(target_date.year, target_date.month)
    last_day = target_date.replace(day=num_days)

    q, p = build_query('SELECT log_date, SUM(seconds) FROM focus_log WHERE log_date >= ? AND log_date <= ?', 
                       (first_day.isoformat(), last_day.isoformat()), app_filter)
    c.execute(q + " GROUP BY log_date", p)
    month_map = {r[0]: r[1] for r in c.fetchall()}
    
    month_data = [{"date": "", "total": -1, "is_target": False} for _ in range(first_day.weekday())]
    for i in range(1, num_days + 1):
        d_str = target_date.replace(day=i).isoformat()
        month_data.append({"date": d_str, "total": month_map.get(d_str, 0), "is_target": d_str == target_date_str})

    hourly_data = [0] * 48
    try:
        q, p = build_query('SELECT hour, SUM(seconds) FROM focus_hourly WHERE log_date = ?', (target_date.isoformat(),), app_filter)
        c.execute(q + " GROUP BY hour", p)
        for hr, secs in c.fetchall():
            if 0 <= hr <= 23: hourly_data[hr * 2] += secs
            
        q, p = build_query('SELECT interval_idx, SUM(seconds) FROM focus_intervals WHERE log_date = ?', (target_date.isoformat(),), app_filter)
        c.execute(q + " GROUP BY interval_idx", p)
        for idx, secs in c.fetchall():
            if 0 <= idx < 96: hourly_data[idx // 2] += secs
    except sqlite3.OperationalError:
        pass

    week_heatmap = [[0]*24 for _ in range(7)]
    try:
        q, p = build_query('''SELECT log_date, hour, SUM(seconds) FROM focus_hourly 
                              WHERE log_date >= ? AND log_date <= ?''', (monday.isoformat(), sunday.isoformat()), app_filter)
        c.execute(q + " GROUP BY log_date, hour", p)
        for ldate, hr, secs in c.fetchall():
            day_idx = date.fromisoformat(ldate).weekday()
            if 0 <= hr <= 23: week_heatmap[day_idx][hr] += secs
    except sqlite3.OperationalError:
        pass

    minute_data = [0] * 1440
    try:
        q, p = build_query('''SELECT minute_idx, SUM(seconds) FROM focus_minutes 
                              WHERE log_date >= ? AND log_date <= ?''', (monday.isoformat(), sunday.isoformat()), app_filter)
        c.execute(q + " GROUP BY minute_idx", p)
        for idx, secs in c.fetchall():
            if 0 <= idx < 1440: minute_data[idx] += secs
    except sqlite3.OperationalError:
        pass

    peak_str = "N/A"
    max_sum = 0
    best_window = None
    for i in range(1440 - 60):
        w_sum = sum(minute_data[i:i+60])
        if w_sum > max_sum and w_sum > 0:
            max_sum = w_sum
            best_window = (i, i+60)

    if best_window:
        start_idx, end_idx = best_window
        while start_idx < end_idx and minute_data[start_idx] == 0: start_idx += 1
        actual_end = end_idx - 1
        while actual_end > start_idx and minute_data[actual_end] == 0: actual_end -= 1
        s_h, s_m = divmod(start_idx, 60)
        e_h, e_m = divmod(actual_end, 60)
        peak_str = f"{s_h:02d}:{s_m:02d} - {e_h:02d}:{e_m:02d}"

    result = {
        "selected_date": target_date.isoformat(), "total": total_seconds, "average": average_seconds,
        "week_range": week_range_str, "yesterday": yesterday_seconds, "current": app_filter if app_filter else "History",
        "apps": all_apps, "week_apps": week_apps, "week": week_data, "month": month_data,
        "hourly": hourly_data, "week_heatmap": week_heatmap, "peak_usage_str": peak_str
    }
    
    print(json.dumps(result))

if __name__ == "__main__":
    main()
