#!/usr/bin/env python3
"""Karabiner에서 'Caps Lock → 순정 390/ABC 입력 소스 전환' 규칙만 지운다 (다른 규칙은 그대로).
Caps Lock 한/영은 OG키보드가 직접 처리한다. 바꾸기 전에 백업을 남긴다."""
import json, os, shutil, time

path = os.path.expanduser("~/.config/karabiner/karabiner.json")
cfg = json.load(open(path, encoding="utf-8"))

def is_caps_switch(m):
    return (m.get("from", {}).get("key_code") == "caps_lock"
            and any("select_input_source" in t for t in m.get("to", [])))

removed = 0
for profile in cfg.get("profiles", []):
    rules = profile.get("complex_modifications", {}).get("rules", [])
    for rule in rules:
        ms = rule.get("manipulators", [])
        keep = [m for m in ms if not is_caps_switch(m)]
        removed += len(ms) - len(keep)
        rule["manipulators"] = keep
    # 규칙이 통째로 비면 규칙도 지운다
    if rules:
        profile["complex_modifications"]["rules"] = [r for r in rules if r.get("manipulators")]

if removed == 0:
    print("지울 Caps Lock 입력 소스 규칙이 없습니다. 아무것도 바꾸지 않았습니다.")
    raise SystemExit(0)

backup = path + time.strftime(".bak-%Y%m%d-%H%M%S")
shutil.copy2(path, backup)
json.dump(cfg, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=4)
print(f"Caps Lock 규칙 {removed}개를 지웠습니다.")
print(f"되돌리기: cp '{backup}' '{path}'")
