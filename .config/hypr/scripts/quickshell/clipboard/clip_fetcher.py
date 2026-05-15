#!/usr/bin/env python3
import subprocess
import json
import os
import sys
import threading
from concurrent.futures import ThreadPoolExecutor

def cleanup_cache(all_lines, cache_dir):
    valid_ids = set()
    # Keep top 200 recent IDs to prevent infinite cache bloat
    for line in all_lines[:200]:
        if '\t' in line:
            valid_ids.add(line.split('\t', 1)[0])
            
    try:
        for f in os.listdir(cache_dir):
            if f.endswith('.png'):
                iid = f.replace('.png', '')
                if iid not in valid_ids:
                    try:
                        os.remove(os.path.join(cache_dir, f))
                    except Exception:
                        pass
    except Exception:
        pass

def decode_image(iid, img_path):
    if not os.path.exists(img_path):
        try:
            with open(img_path, "wb") as f:
                subprocess.run(["cliphist", "decode", iid], stdout=f, timeout=2)
        except Exception:
            pass

def get_cliphist():
    # Arguments: offset, limit, cache_dir, [query]
    offset = int(sys.argv[1]) if len(sys.argv) > 1 else 0
    limit = int(sys.argv[2]) if len(sys.argv) > 2 else 24
    cache_dir = sys.argv[3] if len(sys.argv) > 3 else os.environ.get("QS_CACHE_CLIPBOARD", os.path.expanduser("~/.cache/quickshell/clipboard"))
    query = sys.argv[4] if len(sys.argv) > 4 else ""
    
    os.makedirs(cache_dir, exist_ok=True)
    
    try:
        # Fetch the entire list
        result = subprocess.run(["cliphist", "list"], capture_output=True, text=True, errors='replace')
        if result.returncode != 0:
            print("[]")
            return
            
        all_lines = [l for l in result.stdout.strip().split('\n') if l]
        
        # Filtering
        if query:
            # When searching, we only care about text matches and ignore image placeholders
            filtered_lines = [l for l in all_lines if query.lower() in l.lower() and "[[ binary data" not in l]
        else:
            filtered_lines = all_lines
        
        # Pagination
        lines = filtered_lines[offset:offset+limit]
        
        # Background cleanup
        if offset == 0 and not query:
            threading.Thread(target=cleanup_cache, args=(all_lines, cache_dir), daemon=True).start()

    except Exception as e:
        print("[]")
        return

    items = []
    images_to_decode = []
    
    for line in lines:
        parts = line.split('\t', 1)
        if len(parts) != 2: continue
        
        iid, content = parts[0], parts[1]
        item_type = "text"
        display_content = content.strip()

        if "[[ binary data" in content:
            item_type = "image"
            img_path = os.path.join(cache_dir, f"{iid}.png")
            images_to_decode.append((iid, img_path))
            display_content = img_path

        items.append({
            "id": iid,
            "content": display_content,
            "type": item_type
        })

    # Decode images in parallel to avoid blocking
    if images_to_decode:
        with ThreadPoolExecutor(max_workers=8) as executor:
            executor.map(lambda p: decode_image(*p), images_to_decode)

    print(json.dumps(items))

if __name__ == "__main__":
    get_cliphist()
