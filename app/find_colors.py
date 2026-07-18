import re

file_path = r"e:\Perpova\hotel-pos\app\lib\screens\users_screen.dart"

with open(file_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

patterns = {
    "Colors.white": r"\bColors\.white\b",
    "0xFFF8FAFC": r"0xFFF8FAFC",
    "0xFF1E293B": r"0xFF1E293B",
    "0xFF64748B": r"0xFF64748B",
    "0xFFE2E8F0": r"0xFFE2E8F0",
    "0xFFCBD5E1": r"0xFFCBD5E1",
    "0xFFF1F5F9": r"0xFFF1F5F9",
}

for name, pattern in patterns.items():
    print(f"=== Matches for {name} ===")
    matches_count = 0
    for idx, line in enumerate(lines):
        if re.search(pattern, line):
            print(f"Line {idx+1}: {line.strip()}")
            matches_count += 1
            if matches_count >= 15:
                print("... truncated")
                break
