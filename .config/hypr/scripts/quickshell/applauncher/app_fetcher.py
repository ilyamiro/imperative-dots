#!/usr/bin/env python3
import os
import glob
import json
import sys

CACHE_DIR = os.path.expanduser("~/.cache/quickshell/applauncher")
USAGE_FILE = os.path.join(CACHE_DIR, "usage.json")

def load_usage():
    if os.path.exists(USAGE_FILE):
        try:
            with open(USAGE_FILE, 'r') as f:
                return json.load(f)
        except Exception:
            pass
    return {}

def save_usage(usage):
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        with open(USAGE_FILE, 'w') as f:
            json.dump(usage, f)
    except Exception:
        pass

def increment_usage(name):
    usage = load_usage()
    usage[name] = usage.get(name, 0) + 1
    save_usage(usage)

def fetch_apps():
    usage = load_usage()
    apps = {}
    home = os.path.expanduser('~')
    
    dirs = [
        '/usr/share/applications',
        '/usr/local/share/applications',
        f'{home}/.local/share/applications',
        '/var/lib/flatpak/exports/share/applications',
        f'{home}/.local/share/flatpak/exports/share/applications',
        f'{home}/.nix-profile/share/applications',
        '/run/current-system/sw/share/applications'
    ]
    
    for d in dirs:
        if not os.path.exists(d):
            continue
            
        for f in glob.glob(os.path.join(d, '**/*.desktop'), recursive=True):
            try:
                with open(f, 'r', encoding='utf-8') as file:
                    app = {'name': '', 'exec': '', 'icon': ''}
                    is_desktop = False
                    no_display = False
                    
                    for line in file:
                        line = line.strip()
                        if line == '[Desktop Entry]':
                            is_desktop = True
                        elif line.startswith('['):
                            is_desktop = False
                            
                        if is_desktop:
                            if line.startswith('Name=') and not app['name']:
                                app['name'] = line[5:]
                            elif line.startswith('Exec=') and not app['exec']:
                                app['exec'] = line[5:].split(' %')[0].split(' @@')[0]
                            elif line.startswith('Icon=') and not app['icon']:
                                app['icon'] = line[5:]
                            elif line.startswith('NoDisplay=true') or line.startswith('NoDisplay=1'):
                                no_display = True
                                
                    if app['name'] and app['exec'] and not no_display:
                        app['usage'] = usage.get(app['name'], 0)
                        # Keep only the first occurrence or prioritize one with higher usage if already exists?
                        # Usually, duplicates are the same app in different paths.
                        if app['name'] not in apps or app['usage'] > apps[app['name']]['usage']:
                            apps[app['name']] = app
            except Exception:
                pass
                
    res = list(apps.values())
    # Sort by usage (descending) and then name (ascending)
    res.sort(key=lambda x: (-x.get('usage', 0), x['name'].lower()))
    print(json.dumps(res))

if __name__ == "__main__":
    if len(sys.argv) > 2 and sys.argv[1] == "--increment":
        increment_usage(sys.argv[2])
    else:
        fetch_apps()
