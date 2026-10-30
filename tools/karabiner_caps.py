#!/usr/bin/env python3
"""Karabiner의 Caps Lock 규칙을 OG키보드용으로 바꾼다.

기존: Caps Lock → 순정 세벌식 390 / ABC 입력 소스로 전환 (OG키보드를 밀어냄)
변경: Caps Lock 짧게 → 오른쪽 Command 탭 (= OG키보드 한/영)
      Caps Lock 길게 → 진짜 Caps Lock (대문자 고정)
가상 머신 앱 예외 조건은 기존 규칙의 것을 그대로 쓴다. 바꾸기 전에 백업을 남긴다.
"""
import json, os, shutil, time

path = os.path.expanduser("~/.config/karabiner/karabiner.json")
cfg = json.load(open(path, encoding="utf-8"))

def is_old_caps(m):
    return (m.get("from", {}).get("key_code") == "caps_lock"
            and any("select_input_source" in t for t in m.get("to", [])))

def new_caps(conditions):
    m = {
        "type": "basic",
        "from": {"key_code": "caps_lock", "modifiers": {"optional": ["any"]}},
        "to_if_alone": [{"key_code": "right_command"}],
        "to_if_held_down": [{"key_code": "caps_lock"}],
        "parameters": {
            "basic.to_if_alone_timeout_milliseconds": 400,
            "basic.to_if_held_down_threshold_milliseconds": 400,
        },
    }
    if conditions:
        m["conditions"] = conditions
    return m

removed = 0
for profile in cfg.get("profiles", []):
    for rule in profile.get("complex_modifications", {}).get("rules", []):
        ms = rule.get("manipulators", [])
        old = [m for m in ms if is_old_caps(m)]
        if not old:
            continue
        # 앱 예외 조건만 가져온다 (입력 소스 조건은 버림)
        conds = [c for c in old[0].get("conditions", []) if c.get("type", "").startswith("frontmost_application")]
        keep = [m for m in ms if not is_old_caps(m)]
        idx = ms.index(old[0])
        keep.insert(min(idx, len(keep)), new_caps(conds))
        rule["manipulators"] = keep
        if "description" in rule:
            rule["description"] = "Caps Lock: 짧게 = OG키보드 한/영(오른쪽 Command 탭), 길게 = Caps Lock"
        removed += len(old)

if removed == 0:
    print("바꿀 Caps Lock 입력 소스 규칙을 못 찾았습니다. 아무것도 바꾸지 않았습니다.")
    raise SystemExit(1)

backup = path + time.strftime(".bak-%Y%m%d-%H%M%S")
shutil.copy2(path, backup)
json.dump(cfg, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=4)
print(f"기존 규칙 {removed}개를 새 규칙으로 바꿨습니다.")
print(f"백업: {backup}")
print("되돌리기: cp '%s' '%s'" % (backup, path))
