import csv

with open(r'05_LOGS\draw_census_occlusion_test\census_t025s.csv', mode='r', encoding='utf-8') as f:
    draws = list(csv.DictReader(f))

for d in draws:
    if d['id'] == '33':
        for k, v in d.items():
            print(f"{k}: {v}")
