#!/usr/bin/env python3
import subprocess
import sqlite3
import time
import os
import socket
import json
import threading
import calendar
import re
import signal
import sys
from datetime import date, datetime, timedelta
from collections import defaultdict

current_app_class = "Desktop"
current_app_title = "Desktop"

DB_DIR = os.path.expanduser("~/.local/share/focustime")
os.makedirs(DB_DIR, exist_ok=True)
DB_PATH = os.path.join(DB_DIR, "focustime.db")

# Cache fallback adheres to tmpfs priority but securely falls back
XDG_RUNTIME = os.environ.get("XDG_RUNTIME_DIR")
if not XDG_RUNTIME:
    XDG_RUNTIME = os.path.expanduser("~/.cache/focustime")
    os.makedirs(XDG_RUNTIME, exist_ok=True)
STATE_FILE = os.path.join(XDG_RUNTIME, "focustime_state.json")

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

def resolve_app_name(app_class, raw_title):
    if not app_class or app_class in SYSTEM_STATES:
        return app_class if app_class else "Unknown"
        
    build_desktop_cache()
    app_class_lower = app_class.lower()
    base_class = re.sub(r'[-_ ]?updater$', '', app_class_lower)
    base_class = base_class.replace('.exe', '')

    if app_class_lower in DESKTOP_CACHE_NAME: return DESKTOP_CACHE_NAME[app_class_lower]
    if base_class in DESKTOP_CACHE_NAME: return DESKTOP_CACHE_NAME[base_class]

    clean_title = re.sub(r'^\(\d+\)\s*|^\[\d+\]\s*', '', raw_title)
    clean_title = re.sub(r'\s*\(\d+\)$', '', clean_title)
    parts = re.split(r'\s+[-—|]\s+', clean_title)
    name = parts[-1].strip() if len(parts) > 1 else clean_title.strip()

    if len(name) > 25: name = app_class.capitalize()

    DESKTOP_CACHE_NAME[app_class_lower] = name
    return name

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

def init_db():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute('''CREATE TABLE IF NOT EXISTS focus_log (log_date TEXT, app_class TEXT, seconds INTEGER, app_title TEXT, PRIMARY KEY (log_date, app_class))''')
    c.execute('CREATE INDEX IF NOT EXISTS idx_log_date ON focus_log(log_date)')
    c.execute('''CREATE TABLE IF NOT EXISTS focus_hourly (log_date TEXT, hour INTEGER, app_class TEXT, seconds INTEGER, PRIMARY KEY (log_date, hour, app_class))''')
    c.execute('''CREATE TABLE IF NOT EXISTS focus_intervals (log_date TEXT, interval_idx INTEGER, app_class TEXT, seconds INTEGER, PRIMARY KEY (log_date, interval_idx, app_class))''')
    c.execute('''CREATE TABLE IF NOT EXISTS focus_minutes (log_date TEXT, minute_idx INTEGER, app_class TEXT, seconds INTEGER, PRIMARY KEY (log_date, minute_idx, app_class))''')
    
    c.execute("PRAGMA table_info(focus_log)")
    if 'app_title' not in [row[1] for row in c.fetchall()]:
        c.execute('ALTER TABLE focus_log ADD COLUMN app_title TEXT')
        
    conn.commit()
    return conn

def get_active_window_hyprctl():
    try:
        output = subprocess.check_output(['hyprctl', 'activewindow', '-j'], text=True)
        if output.strip() == "{}": return "Desktop", "Desktop"
        data = json.loads(output)
        
        app_cls = data.get('initialClass') or data.get('class') or ''
        raw_title = data.get('initialTitle') or data.get('title') or ''

        if "quickshell" in app_cls.lower() or "qs-master" in raw_title.lower() or "qs-master" in app_cls.lower():
            return "Quickshell", "Quickshell"
            
        app_cls = app_cls if app_cls else "Unknown"
        raw_title = raw_title if raw_title else app_cls
        clean_name = resolve_app_name(app_cls, raw_title)
        return app_cls, clean_name
    except Exception:
        return "Unknown", "Unknown"

def is_locked():
    try:
        subprocess.check_output(['pgrep', '-x', 'hyprlock'])
        return True
    except subprocess.CalledProcessError:
        return False

def listen_hyprland_ipc():
    global current_app_class, current_app_title
    hypr_sig = os.environ.get("HYPRLAND_INSTANCE_SIGNATURE")
    if not hypr_sig: return

    sock_path = f"{XDG_RUNTIME}/hypr/{hypr_sig}/.socket2.sock"
    if not os.path.exists(sock_path):
        sock_path = f"/tmp/hypr/{hypr_sig}/.socket2.sock"

    while True:
        try:
            client = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            client.connect(sock_path)
            buffer = ""
            while True:
                data = client.recv(4096).decode('utf-8')
                if not data: break
                buffer += data
                while '\n' in buffer:
                    line, buffer = buffer.split('\n', 1)
                    if line.startswith('activewindow>>'):
                        cls, clean_title = get_active_window_hyprctl()
                        if is_locked() or cls == "hyprlock":
                            current_app_class, current_app_title = "Locked", "Locked"
                        else:
                            current_app_class, current_app_title = cls, clean_title
        except Exception:
            time.sleep(2) 


class DaemonTracker:
    def __init__(self):
        self.conn = init_db()
        self.buffer = []
        self.cached_json = None
        self.last_sync = 0
        self.last_date = date.today()
        
    def full_sync(self, target_date):
        c = self.conn.cursor()
        
        yesterday = target_date - timedelta(days=1)
        c.execute('SELECT SUM(seconds) FROM focus_log WHERE log_date = ?', (yesterday.isoformat(),))
        yesterday_seconds = c.fetchone()[0] or 0

        monday = target_date - timedelta(days=target_date.weekday())
        sunday = monday + timedelta(days=6)
        week_range_str = f"{monday.strftime('%b')} {monday.day} - {sunday.strftime('%b')} {sunday.day}"

        c.execute('''SELECT COUNT(DISTINCT log_date), SUM(seconds) FROM focus_log 
                     WHERE log_date >= ? AND log_date <= ? AND seconds > 0''', (monday.isoformat(), sunday.isoformat()))
        row = c.fetchone()
        days_count = row[0] or 0
        total_week = row[1] or 0
        average_seconds = total_week // days_count if days_count > 0 else 0
        
        c.execute('SELECT SUM(seconds) FROM focus_log WHERE log_date = ?', (target_date.isoformat(),))
        total_seconds = c.fetchone()[0] or 0

        c.execute('''SELECT app_class, COALESCE(app_title, app_class), SUM(seconds) as secs 
                     FROM focus_log WHERE log_date = ? GROUP BY app_class ORDER BY secs DESC''', (target_date.isoformat(),))
        all_apps = []
        for row in c.fetchall():
            app_class, app_title, secs = row
            all_apps.append({
                "class": app_class, "name": app_title, "icon": get_app_icon(app_class),
                "seconds": secs, "percent": round((secs / total_seconds) * 100, 1) if total_seconds > 0 else 0
            })

        c.execute('''SELECT app_class, COALESCE(app_title, app_class), SUM(seconds) as secs FROM focus_log 
                     WHERE log_date >= ? AND log_date <= ? GROUP BY app_class ORDER BY secs DESC LIMIT 50''', 
                  (monday.isoformat(), sunday.isoformat()))
        week_apps_rows = c.fetchall()
        week_apps_total = sum([r[2] for r in week_apps_rows])
        week_apps = []
        for r in week_apps_rows:
            cls, title, secs = r
            week_apps.append({
                "class": cls, "name": title, "icon": get_app_icon(cls),
                "seconds": secs, "percent": round((secs / week_apps_total) * 100, 1) if week_apps_total > 0 else 0
            })

        c.execute('SELECT log_date, SUM(seconds) FROM focus_log WHERE log_date >= ? AND log_date <= ? GROUP BY log_date', 
                 (monday.isoformat(), sunday.isoformat()))
        week_map = {r[0]: r[1] for r in c.fetchall()}
        days_str = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        week_data = []
        for i in range(7):
            d_str = (monday + timedelta(days=i)).isoformat()
            week_data.append({"date": d_str, "day": days_str[i], "total": week_map.get(d_str, 0), "is_target": d_str == target_date.isoformat()})

        first_day = target_date.replace(day=1)
        _, num_days = calendar.monthrange(target_date.year, target_date.month)
        last_day = target_date.replace(day=num_days)
        c.execute('SELECT log_date, SUM(seconds) FROM focus_log WHERE log_date >= ? AND log_date <= ? GROUP BY log_date', 
                 (first_day.isoformat(), last_day.isoformat()))
        month_map = {r[0]: r[1] for r in c.fetchall()}
        
        month_data = [{"date": "", "total": -1, "is_target": False} for _ in range(first_day.weekday())]
        for i in range(1, num_days + 1):
            d_str = target_date.replace(day=i).isoformat()
            month_data.append({"date": d_str, "total": month_map.get(d_str, 0), "is_target": d_str == target_date.isoformat()})

        hourly_data = [0] * 48
        try:
            c.execute('SELECT hour, SUM(seconds) FROM focus_hourly WHERE log_date = ? GROUP BY hour', (target_date.isoformat(),))
            for hr, secs in c.fetchall():
                if 0 <= hr <= 23: hourly_data[hr * 2] += secs
            c.execute('SELECT interval_idx, SUM(seconds) FROM focus_intervals WHERE log_date = ? GROUP BY interval_idx', (target_date.isoformat(),))
            for idx, secs in c.fetchall():
                if 0 <= idx < 96: hourly_data[idx // 2] += secs
        except sqlite3.OperationalError:
            pass 

        week_heatmap = [[0]*24 for _ in range(7)]
        try:
            c.execute('''SELECT log_date, hour, SUM(seconds) FROM focus_hourly WHERE log_date >= ? AND log_date <= ? GROUP BY log_date, hour''', 
                      (monday.isoformat(), sunday.isoformat()))
            for ldate, hr, secs in c.fetchall():
                day_idx = date.fromisoformat(ldate).weekday()
                if 0 <= hr <= 23: week_heatmap[day_idx][hr] += secs
        except sqlite3.OperationalError:
            pass

        minute_data = [0] * 1440
        try:
            c.execute('''SELECT minute_idx, SUM(seconds) FROM focus_minutes WHERE log_date >= ? AND log_date <= ? GROUP BY minute_idx''', 
                      (monday.isoformat(), sunday.isoformat()))
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

        self.cached_json = {
            "selected_date": target_date.isoformat(), "total": total_seconds, "average": average_seconds,
            "week_range": week_range_str, "yesterday": yesterday_seconds, "current": current_app_title,
            "apps": all_apps, "week_apps": week_apps, "week": week_data, "month": month_data,
            "hourly": hourly_data, "week_heatmap": week_heatmap, "peak_usage_str": peak_str
        }
        self.last_sync = time.time()
        self.last_date = target_date
        
    def fast_tick(self, app_class, app_title, write_to_disk=True):
        now = datetime.now()
        target_date = now.date()
        
        self.buffer.append((target_date.isoformat(), app_class, app_title, now))
        
        if self.cached_json is None or target_date != self.last_date or (time.time() - self.last_sync > 60):
            self.flush()
            self.full_sync(target_date)
        else:
            d = self.cached_json
            d["total"] += 1
            d["current"] = app_title
            
            found = False
            for app in d["apps"]:
                if app["class"] == app_class:
                    app["seconds"] += 1
                    found = True
                    break
            if not found:
                d["apps"].append({
                    "class": app_class, "name": app_title, 
                    "icon": get_app_icon(app_class), "seconds": 1, "percent": 0
                })
                
            for app in d["apps"]:
                app["percent"] = round((app["seconds"] / d["total"]) * 100, 1) if d["total"] > 0 else 0
            d["apps"].sort(key=lambda x: x["seconds"], reverse=True)
            
            for w in d["week"]:
                if w["is_target"]: w["total"] += 1
            for m in d["month"]:
                if m["is_target"]: m["total"] += 1
                
            hr = now.hour
            idx = hr * 2 + (1 if now.minute >= 30 else 0)
            if 0 <= idx < 48: d["hourly"][idx] += 1
                
            day_idx = now.weekday()
            if 0 <= hr < 24: d["week_heatmap"][day_idx][hr] += 1
                
        # Conditionally write to tmpfs
        if write_to_disk:
            temp_file = STATE_FILE + ".tmp"
            try:
                with open(temp_file, "w") as f:
                    json.dump(self.cached_json, f)
                os.rename(temp_file, STATE_FILE)
            except Exception:
                pass
            
        if len(self.buffer) >= 15:
            self.flush()
            
    def flush(self):
        if not self.buffer: return
        c = self.conn.cursor()
        
        logs = defaultdict(int)
        titles = {}
        hours = defaultdict(int)
        intervals = defaultdict(int)
        minutes = defaultdict(int)
        
        for d_str, cls, title, dt in self.buffer:
            logs[(d_str, cls)] += 1
            titles[cls] = title
            hr = dt.hour
            hours[(d_str, hr, cls)] += 1
            minute = hr * 60 + dt.minute
            intervals[(d_str, minute // 15, cls)] += 1
            minutes[(d_str, minute, cls)] += 1
            
        for (d_str, cls), secs in logs.items():
            c.execute('''INSERT INTO focus_log (log_date, app_class, seconds, app_title) VALUES (?, ?, ?, ?)
                         ON CONFLICT(log_date, app_class) DO UPDATE SET seconds = seconds + ?, app_title = ?''',
                      (d_str, cls, secs, titles[cls], secs, titles[cls]))
                      
        for (d_str, hr, cls), secs in hours.items():
            c.execute('''INSERT INTO focus_hourly (log_date, hour, app_class, seconds) VALUES (?, ?, ?, ?)
                         ON CONFLICT(log_date, hour, app_class) DO UPDATE SET seconds = seconds + ?''',
                      (d_str, hr, cls, secs, secs))
                      
        for (d_str, itv, cls), secs in intervals.items():
            c.execute('''INSERT INTO focus_intervals (log_date, interval_idx, app_class, seconds) VALUES (?, ?, ?, ?)
                         ON CONFLICT(log_date, interval_idx, app_class) DO UPDATE SET seconds = seconds + ?''',
                      (d_str, itv, cls, secs, secs))
                      
        for (d_str, min_idx, cls), secs in minutes.items():
            c.execute('''INSERT INTO focus_minutes (log_date, minute_idx, app_class, seconds) VALUES (?, ?, ?, ?)
                         ON CONFLICT(log_date, minute_idx, app_class) DO UPDATE SET seconds = seconds + ?''',
                      (d_str, min_idx, cls, secs, secs))
                      
        self.conn.commit()
        self.buffer.clear()

tracker = DaemonTracker()

def exit_handler(sig, frame):
    tracker.flush()
    sys.exit(0)

def main():
    global current_app_class, current_app_title
    signal.signal(signal.SIGINT, exit_handler)
    signal.signal(signal.SIGTERM, exit_handler)

    current_app_class, current_app_title = get_active_window_hyprctl()
    
    ipc_thread = threading.Thread(target=listen_hyprland_ipc, daemon=True)
    ipc_thread.start()

    tick_counter = 0
    while True:
        time.sleep(1)
        tick_counter += 1
        if current_app_class and current_app_class not in [""]:
            # Only dump JSON to memory/disk every 5 seconds
            tracker.fast_tick(current_app_class, current_app_title, write_to_disk=(tick_counter % 5 == 0))

if __name__ == "__main__":
    main()
