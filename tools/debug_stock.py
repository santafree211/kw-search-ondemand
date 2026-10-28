import json

with open("workflow/data/shelved_stock_female.json", "r", encoding="utf-8-sig") as f:
    stock = json.load(f)

print(f"Type: {type(stock)}, Length: {len(stock)}")
for item in stock[:10]:
    print(type(item), item)
