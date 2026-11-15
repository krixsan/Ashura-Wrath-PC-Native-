import csv

with open('05_LOGS/draw_census_occlusion_test/census_t025s.csv', 'r') as f:
    reader = csv.DictReader(f)
    rows = {r['id']: r for r in reader}

d31 = rows['31']
d32 = rows['32']
d33 = rows['33']

print(f"{'Field':<18} | {'Draw 31 (Cannon)':<30} | {'Draw 32 (Earth)':<30} | {'Draw 33 (Gohma)':<30}")
print("-" * 115)
for k in d31:
    v31 = d31[k][:28] if len(d31[k]) > 28 else d31[k]
    v32 = d32[k][:28] if len(d32[k]) > 28 else d32[k]
    v33 = d33[k][:28] if len(d33[k]) > 28 else d33[k]
    print(f"{k:<18} | {v31:<30} | {v32:<30} | {v33:<30}")
