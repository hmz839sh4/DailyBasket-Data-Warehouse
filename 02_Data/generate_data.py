"""
Makes fake DailyBasket source CSV files in raw_data/. They are dirty on purpose
(duplicates, extra spaces, mixed case, NULLs, bad rows) so the SQL cleaning steps can fix them.
"""
import csv
import os
import random
from datetime import date, timedelta

random.seed(42)

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "raw_data")
os.makedirs(OUT, exist_ok=True)

def write_csv(name, header, rows):
    path = os.path.join(OUT, name)
    with open(path, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(header)
        w.writerows(rows)
    print("%-28s %6d rows" % (name, len(rows)))

def daterange(start, end):
    d = start
    while d <= end:
        yield d
        d += timedelta(days=1)

# REGIONS  (40 cities, 4 duplicates, messy text)
cities = [
    ("Lahore", "Punjab", "Central"), ("Faisalabad", "Punjab", "Central"),
    ("Rawalpindi", "Punjab", "North"), ("Multan", "Punjab", "South"),
    ("Gujranwala", "Punjab", "Central"), ("Sialkot", "Punjab", "Central"),
    ("Bahawalpur", "Punjab", "South"), ("Sargodha", "Punjab", "Central"),
    ("Sahiwal", "Punjab", "Central"), ("Jhang", "Punjab", "Central"),
    ("Okara", "Punjab", "Central"), ("Gujrat", "Punjab", "North"),
    ("Sheikhupura", "Punjab", "Central"), ("Rahim Yar Khan", "Punjab", "South"),
    ("Kasur", "Punjab", "Central"), ("Karachi", "Sindh", "South"),
    ("Hyderabad", "Sindh", "South"), ("Sukkur", "Sindh", "South"),
    ("Larkana", "Sindh", "South"), ("Mirpur Khas", "Sindh", "South"),
    ("Nawabshah", "Sindh", "South"), ("Peshawar", "Khyber Pakhtunkhwa", "North"),
    ("Mardan", "Khyber Pakhtunkhwa", "North"), ("Abbottabad", "Khyber Pakhtunkhwa", "North"),
    ("Swat", "Khyber Pakhtunkhwa", "North"), ("Kohat", "Khyber Pakhtunkhwa", "North"),
    ("Mansehra", "Khyber Pakhtunkhwa", "North"), ("Dera Ismail Khan", "Khyber Pakhtunkhwa", "North"),
    ("Quetta", "Balochistan", "South"), ("Gwadar", "Balochistan", "South"),
    ("Turbat", "Balochistan", "South"), ("Khuzdar", "Balochistan", "South"),
    ("Islamabad", "Islamabad Capital Territory", "North"), ("Muzaffarabad", "Azad Kashmir", "North"),
    ("Mirpur", "Azad Kashmir", "North"), ("Gilgit", "Gilgit-Baltistan", "North"),
    ("Skardu", "Gilgit-Baltistan", "North"), ("Chiniot", "Punjab", "Central"),
    ("Hafizabad", "Punjab", "Central"), ("Narowal", "Punjab", "Central"),
]
regions = []
for i, (c, p, z) in enumerate(cities, 1):
    regions.append(["R-%02d" % i, c, p, "Pakistan", z])
# dirty: change text style of some rows
regions[0][1] = "  lahore "
regions[1][1] = "FAISALABAD"
regions[15][1] = "karachi"
regions[32][1] = " Islamabad  "
regions[20][2] = "SINDH"
# dirty: 4 duplicate rows (same region_id)
for idx in (3, 9, 21, 28):
    r = list(regions[idx])
    r[1] = " " + r[1].upper()
    regions.append(r)
write_csv("source_regions.csv", ["region_id", "city", "province", "country", "region_zone"], regions)

# CHANNELS  (3 real channels, 1 dirty duplicate)
channels = [
    ["CH-01", "In-Store", "Offline"],
    ["CH-02", "Website", "Online"],
    ["CH-03", "Mobile App", "Online"],
    ["CH-02", " website ", "ONLINE"],
]
write_csv("source_channels.csv", ["channel_id", "channel_name", "channel_type"], channels)

# CUSTOMERS  (600 + dirty)
first = ["Ali", "Ahmed", "Hamza", "Usman", "Bilal", "Hassan", "Zain", "Fahad", "Omar", "Saad",
         "Ayesha", "Fatima", "Zainab", "Maryam", "Hira", "Sana", "Noor", "Amna", "Iqra", "Laiba",
         "Talha", "Haris", "Danish", "Waqas", "Kamran", "Rabia", "Sidra", "Mahnoor", "Areeba", "Hina"]
last = ["Khan", "Ahmed", "Raza", "Malik", "Sheikh", "Butt", "Chaudhry", "Qureshi", "Siddiqui", "Iqbal",
        "Hussain", "Abbasi", "Mirza", "Shah", "Javed", "Aslam", "Farooq", "Nawaz", "Rana", "Bhatti"]
segments = ["Regular", "Regular", "Regular", "Loyalty Member", "Loyalty Member", "Wholesale"]
age_groups = ["18-24", "25-34", "25-34", "35-44", "45-54", "55+"]

customers = []
for i in range(1, 601):
    cid = "C-%05d" % i
    name = "%s %s" % (random.choice(first), random.choice(last))
    gender = "Male" if name.split()[0] in ("Ali", "Ahmed", "Hamza", "Usman", "Bilal", "Hassan", "Zain", "Fahad",
                                             "Omar", "Saad", "Talha", "Haris", "Danish", "Waqas", "Kamran") else "Female"
    email = "%s.%s%d@mail.com" % (name.split()[0].lower(), name.split()[1].lower(), i)
    signup = date(2023, 6, 1) + timedelta(days=random.randint(0, 1100))
    customers.append([cid, name, email, gender, random.choice(age_groups),
                      random.choice(segments), signup.isoformat()])

# dirty text on many rows
for r in random.sample(customers, 60):
    r[1] = "  " + r[1] + " "                      # extra spaces
for r in random.sample(customers, 70):
    r[5] = random.choice([r[5].lower(), r[5].upper(), " " + r[5] + " "])   # segment case/space
for r in random.sample(customers, 40):
    r[3] = random.choice(["M", "F", "male", "female", "MALE", "FEMALE"])   # gender styles
for r in random.sample(customers, 14):
    r[2] = ""                                      # missing email
for r in random.sample(customers, 12):
    r[4] = ""                                      # missing age group
for r in random.sample(customers, 6):
    r[6] = "N/A"                                   # bad signup date
# 25 duplicates (same id, small change, arrive later)
dups = []
for r in random.sample(customers, 25):
    d = list(r)
    d[1] = d[1].strip().upper()
    d[2] = "new." + (d[2] if d[2] else "mail@mail.com")
    dups.append(d)
customers += dups
# 6 rows with no customer_id (cannot be used)
for _ in range(6):
    customers.append(["", "Walk In Customer", "", "Male", "25-34", "Regular", "2025-01-01"])
random.shuffle(customers)
write_csv("source_customers.csv",
          ["customer_id", "customer_name", "email", "gender", "age_group", "customer_segment", "signup_date"],
          customers)

# PRODUCTS  (160 + dirty)
catalog = {
    "Grocery": {"Rice": ["Basmati Rice 5kg", "Sella Rice 5kg", "Super Kernel Rice 10kg"],
                "Flour": ["Wheat Flour 10kg", "Fine Flour 5kg", "Gram Flour 1kg"],
                "Cooking Oil": ["Cooking Oil 5L", "Canola Oil 3L", "Ghee 1kg", "Olive Oil 500ml"],
                "Pulses": ["Red Lentils 1kg", "Chickpeas 1kg", "Mung Beans 1kg", "Black Lentils 1kg"],
                "Spices": ["Red Chilli Powder 200g", "Turmeric 200g", "Garam Masala 100g", "Salt 800g", "Sugar 2kg"]},
    "Beverages": {"Tea": ["Black Tea 950g", "Green Tea 25 bags", "Tea Whitener 1kg"],
                  "Juice": ["Mango Juice 1L", "Orange Juice 1L", "Apple Juice 1L", "Mixed Fruit Juice 1L"],
                  "Soft Drinks": ["Cola 1.5L", "Lemon Soda 1.5L", "Orange Soda 1.5L", "Energy Drink 250ml"],
                  "Water": ["Mineral Water 1.5L", "Mineral Water 6 Pack", "Sparkling Water 500ml"]},
    "Dairy": {"Milk": ["Fresh Milk 1L", "Full Cream Milk 1L", "Low Fat Milk 1L", "Milk Powder 900g"],
              "Yogurt": ["Plain Yogurt 1kg", "Fruit Yogurt 150g", "Raita Cup 250g"],
              "Cheese": ["Cheese Slices 200g", "Mozzarella 500g", "Cream Cheese 200g"],
              "Butter": ["Salted Butter 200g", "Unsalted Butter 200g"]},
    "Household": {"Detergent": ["Washing Powder 2kg", "Liquid Detergent 1L", "Fabric Softener 1L"],
                  "Cleaning": ["Dish Soap 750ml", "Floor Cleaner 1L", "Bleach 1L", "Glass Cleaner 500ml"],
                  "Paper": ["Tissue Box 200", "Kitchen Roll 2 Pack", "Toilet Paper 10 Pack"],
                  "Personal Care": ["Bath Soap 3 Pack", "Shampoo 400ml", "Toothpaste 150g", "Hand Wash 250ml"]},
    "Snacks": {"Biscuits": ["Tea Biscuits 12 Pack", "Cream Biscuits 6 Pack", "Digestive Biscuits 400g"],
               "Chips": ["Salted Chips 90g", "Masala Chips 90g", "Chips Family Pack 200g"],
               "Chocolate": ["Milk Chocolate 90g", "Chocolate Wafer 6 Pack", "Hazelnut Spread 350g"],
               "Dry Fruit": ["Almonds 250g", "Cashew 250g", "Mixed Nuts 400g", "Dates 500g"]},
}
brands = ["Sunrise", "GreenField", "PureLife", "Al-Noor", "DailyFresh", "Golden Harvest", "Baraka", "CleanWave"]

products = []
n = 0
for cat, subs in catalog.items():
    for sub, names in subs.items():
        for nm in names:
            n += 1
            lp = random.choice([85, 120, 165, 220, 280, 350, 450, 620, 780, 950, 1200, 1650, 2100, 2800])
            lp = lp + random.choice([0, 5, 10, 25, 40])
            cost = round(lp * random.uniform(0.62, 0.82), 2)
            products.append(["P-%04d" % n, nm, random.choice(brands), sub, cat,
                             "%.2f" % cost, "%.2f" % lp, "Y"])
# top up to 160 by adding pack variants
base_len = len(products)
k = 0
while len(products) < 160:
    b = products[k % base_len]
    n += 1
    lp = float(b[6]) * random.choice([1.1, 1.3, 0.9])
    products.append(["P-%04d" % n, b[1] + " Value Pack", random.choice(brands), b[3], b[4],
                     "%.2f" % (lp * random.uniform(0.62, 0.82)), "%.2f" % lp, "Y"])
    k += 1
PRODUCT_IDS = [p[0] for p in products]
PRICE = {p[0]: float(p[6]) for p in products}

# dirty text
for r in random.sample(products, 40):
    r[4] = random.choice([r[4].upper(), r[4].lower(), " " + r[4] + " "])
for r in random.sample(products, 40):
    r[2] = random.choice([r[2].upper(), " " + r[2], r[2].lower()])
for r in random.sample(products, 25):
    r[1] = "  " + r[1] + "  "
for r in random.sample(products, 5):
    r[5] = ""                                      # missing unit cost
for r in random.sample(products, 12):
    r[7] = random.choice(["yes", "TRUE", "1", "N", "no", "false", "0"])
dup_p = []
for r in random.sample(products, 8):
    d = list(r)
    d[6] = "%.2f" % (float(d[6]) + 10)             # price changed in the later copy
    dup_p.append(d)
products += dup_p
random.shuffle(products)
write_csv("source_products.csv",
          ["product_id", "product_name", "brand", "subcategory", "category", "unit_cost", "list_price", "is_active"],
          products)

# PROMOTIONS  (30 + 2 dirty duplicates) and PROMOTION PRODUCTS
promo_names = ["Ramadan Sale", "Eid Offer", "Independence Day Sale", "Summer Savings", "Back to School",
               "Winter Warm-up", "Weekend Bonanza", "Monthly Saver", "Fresh Start Deal", "Family Pack Fest"]
ptypes = ["Percentage Off", "Percentage Off", "Percentage Off", "Buy 1 Get 1", "Free Delivery"]
promos = []
for i in range(1, 31):
    start = date(2024, 1, 5) + timedelta(days=(i - 1) * 36 + random.randint(0, 10))
    length = random.randint(7, 20)
    ptype = random.choice(ptypes)
    pct = {"Percentage Off": random.choice([5, 10, 15, 20, 25]), "Buy 1 Get 1": 50, "Free Delivery": 0}[ptype]
    promos.append(["PR-%03d" % i, "%s %d" % (random.choice(promo_names), 2024 + (start.year - 2024)),
                   ptype, "%.2f" % pct, start.isoformat(), (start + timedelta(days=length)).isoformat()])
for r in random.sample(promos, 10):
    r[2] = random.choice([r[2].upper(), r[2].lower(), " " + r[2]])
promos_dirty = promos + [list(promos[4]), list(promos[11])]
write_csv("source_promotions.csv",
          ["promotion_id", "promotion_name", "promotion_type", "discount_percent", "start_date", "end_date"],
          promos_dirty)

promo_prod = []
PROMO_BY_PRODUCT = {}
for p in promos:
    chosen = random.sample(PRODUCT_IDS, random.randint(6, 12))
    s, e = date.fromisoformat(p[4]), date.fromisoformat(p[5])
    pct = float(p[3])
    for pid in chosen:
        promo_prod.append([p[0], pid])
        PROMO_BY_PRODUCT.setdefault(pid, []).append((p[0], s, e, pct, p[2].strip().lower()))
promo_prod += [list(r) for r in random.sample(promo_prod, 15)]       # duplicates
write_csv("source_promotion_products.csv", ["promotion_id", "product_id"], promo_prod)

# ORDERS and ORDER LINES  (4,400 orders, ~13k lines)
good_customers = [c[0] for c in customers if c[0]]
good_customers = sorted(set(good_customers))
region_ids = [r[0] for r in regions[:40]]
big_cities = ["R-01", "R-16", "R-33", "R-02", "R-03", "R-04"]
channel_ids = ["CH-01", "CH-02", "CH-03"]
d0, d1 = date(2024, 1, 1), date(2026, 10, 31)
span = (d1 - d0).days

orders, lines = [], []
for i in range(1, 4401):
    oid = "O-%06d" % (100000 + i)
    od = d0 + timedelta(days=int(span * (random.random() ** 0.8)))
    cust = random.choice(good_customers)
    reg = random.choice(big_cities) if random.random() < 0.55 else random.choice(region_ids)
    ch = random.choices(channel_ids, weights=[45, 30, 25])[0]
    orders.append([oid, od.isoformat(), cust, reg, ch])
    for ln in range(1, random.randint(1, 5) + 1):
        pid = random.choice(PRODUCT_IDS)
        qty = random.choice([1, 1, 1, 2, 2, 3, 4, 5, 6])
        promo_id = ""
        for (pr, s, e, pct, ptype) in PROMO_BY_PRODUCT.get(pid, []):
            if s <= od <= e and random.random() < 0.7:
                promo_id = pr
                break
        lines.append([oid, ln, pid, qty, "%.2f" % PRICE[pid], promo_id])

# dirty orders
bad_date = random.sample(range(len(orders)), 6)
for i in bad_date:
    orders[i][1] = ""                              # missing order date
bad_cust = random.sample([i for i in range(len(orders)) if i not in bad_date], 5)
for i in bad_cust:
    orders[i][2] = "C-99999"                       # customer does not exist
for i in random.sample(range(len(orders)), 30):
    orders[i][4] = random.choice(["CH-02", "CH-03", "CH-01"])
write_csv("source_orders.csv", ["order_id", "order_date", "customer_id", "region_id", "channel_id"], orders)

# dirty lines
for i in random.sample(range(len(lines)), 15):
    lines[i][2] = " " + lines[i][2].lower() + " "  # product id in lower case with spaces
for i in random.sample(range(len(lines)), 10):
    lines[i][2] = "P-9999"                         # product does not exist
for i in random.sample(range(len(lines)), 8):
    lines[i][3] = random.choice([0, -1, -2])       # bad quantity
lines += [list(l) for l in random.sample(lines, 40)]   # 40 exact duplicate lines
random.shuffle(lines)
write_csv("source_order_lines.csv",
          ["order_id", "line_number", "product_id", "quantity", "unit_price", "promotion_id"], lines)

# INVENTORY SNAPSHOTS  (26 weekly snapshots, 4 warehouse regions)
wh_regions = ["R-01", "R-16", "R-33", "R-02"]
snap_days = []
d = date(2026, 5, 3)                               # a Sunday
while d <= date(2026, 10, 25):
    snap_days.append(d)
    d += timedelta(days=7)

inv = []
for pid in PRODUCT_IDS:
    for rg in wh_regions:
        on_hand = random.randint(80, 300)
        reorder = random.choice([20, 30, 40, 50, 60])
        for sd in snap_days:
            sold = random.randint(0, 45)
            recv = random.choice([0, 0, 50, 80, 120]) if on_hand < 150 else 0
            on_hand = max(0, on_hand + recv - sold)
            inv.append([sd.isoformat(), pid, rg, on_hand, recv, sold, reorder])
for r in random.sample(inv, 15):
    r[3] = ""                                      # missing on-hand
for r in random.sample(inv, 10):
    r[3] = -5                                      # impossible stock
for r in random.sample(inv, 30):
    r[1] = " " + r[1].lower()                      # product id style
inv += [list(r) for r in random.sample(inv, 20)]   # duplicates
random.shuffle(inv)
write_csv("source_inventory.csv",
          ["snapshot_date", "product_id", "region_id", "quantity_on_hand", "quantity_received",
           "quantity_sold", "reorder_level"], inv)
print("done")
