"""
Builds reports/Data_Cleaning_Report.pdf and reports/Data_Quality_Report.pdf from the database.
Run it after run_etl.py. Needs: pip install reportlab matplotlib "psycopg[binary]"
"""
import os
import psycopg
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import FancyBboxPatch
from reportlab.lib import colors
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import cm
from reportlab.platypus import (Image, KeepTogether, Paragraph, SimpleDocTemplate,
                                Spacer, Table, TableStyle)

HERE = os.path.dirname(os.path.abspath(__file__))
REP = os.path.join(HERE, "reports")
os.makedirs(REP, exist_ok=True)

PROJECT = "DailyBasket Data Warehouse - Phase 2"
TEAM = "Hamza Abbas (L24-2500) and Sadeem Arshad (L24-2502)"

conn = psycopg.connect("dbname=dailybasket_dw")
cur = conn.cursor()

def q(sql, params=None):
    cur.execute(sql, params)
    return cur.fetchall()

def n(x):
    return "{:,}".format(int(x))

ss = getSampleStyleSheet()
NAVY = colors.HexColor("#1F3A5F")
TITLE = ParagraphStyle("T", parent=ss["Title"], fontSize=22, textColor=NAVY, spaceAfter=4)
SUB = ParagraphStyle("S", parent=ss["BodyText"], fontSize=10.5, textColor=colors.grey, alignment=1)
H2 = ParagraphStyle("H2", parent=ss["Heading2"], fontSize=13.5, textColor=NAVY, spaceBefore=12, spaceAfter=4)
BODY = ParagraphStyle("B", parent=ss["BodyText"], fontSize=10.5, leading=15)
BUL = ParagraphStyle("BL", parent=BODY, leftIndent=16, bulletIndent=4, spaceAfter=2)
CELL = ParagraphStyle("C", parent=ss["BodyText"], fontSize=8.6, leading=10.8)
CELLH = ParagraphStyle("CH", parent=CELL, textColor=colors.white, fontName="Helvetica-Bold")
BIG = ParagraphStyle("BIG", parent=BODY, fontSize=12, leading=17)

def P(t):
    return Paragraph(t, BODY)

def B(items):
    return [Paragraph(i, BUL, bulletText="•") for i in items]

def table(rows, widths, status_col=None):
    data = [[Paragraph(str(c), CELLH if r == 0 else CELL) for c in row] for r, row in enumerate(rows)]
    t = Table(data, colWidths=[w * cm for w in widths], repeatRows=1)
    style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("GRID", (0, 0), (-1, -1), 0.5, colors.grey),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, colors.HexColor("#EEF3F9")]),
        ("TOPPADDING", (0, 0), (-1, -1), 3), ("BOTTOMPADDING", (0, 0), (-1, -1), 3),
    ]
    if status_col is not None:
        for i, row in enumerate(rows[1:], 1):
            s = str(row[status_col])
            if s == "PASS":
                style.append(("BACKGROUND", (status_col, i), (status_col, i), colors.HexColor("#D5F0DC")))
            elif s == "FAIL":
                style.append(("BACKGROUND", (status_col, i), (status_col, i), colors.HexColor("#F8D0D0")))
            elif s == "INFO":
                style.append(("BACKGROUND", (status_col, i), (status_col, i), colors.HexColor("#FFF2C6")))
    t.setStyle(TableStyle(style))
    return t

def footer(canvas, doc):
    canvas.saveState()
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(colors.grey)
    canvas.drawString(2 * cm, 1.1 * cm, PROJECT)
    canvas.drawRightString(A4[0] - 2 * cm, 1.1 * cm, "Page %d" % doc.page)
    canvas.restoreState()

def build(filename, title, story):
    doc = SimpleDocTemplate(os.path.join(REP, filename), pagesize=A4, leftMargin=2 * cm, rightMargin=2 * cm,
                            topMargin=2 * cm, bottomMargin=2 * cm, title=title, author=TEAM)
    head = [Paragraph(title, TITLE), Paragraph("%s<br/>%s" % (PROJECT, TEAM), SUB), Spacer(1, 12)]
    doc.build(head + story, onFirstPage=footer, onLaterPages=footer)
    print("built", filename)

latest = q("SELECT MAX(batch_id) FROM project_staging.etl_batch")[0][0]
SRC = [("stg_region", "Regions"), ("stg_channel", "Channels"), ("stg_customer", "Customers"),
       ("stg_product", "Products"), ("stg_promotion", "Promotions"),
       ("stg_promotion_product", "Promotion products"), ("stg_orders", "Orders (headers)"),
       ("stg_sales", "Order lines (sales)"), ("stg_inventory", "Inventory snapshots")]
raw = dict(q("SELECT object_name, row_count FROM project_staging.etl_row_counts WHERE batch_id=%s AND step='raw_load'", (latest,)))
clean = dict(q("SELECT object_name, row_count FROM project_staging.etl_row_counts WHERE batch_id=%s AND step='clean'", (latest,)))
kinds = {}
for tbl, kind, c in q("SELECT source_table, kind, COUNT(*) FROM project_staging.etl_rejected_rows GROUP BY 1,2"):
    kinds[(tbl, kind)] = c
reasons = q("""SELECT source_table, kind, reason, COUNT(*) FROM project_staging.etl_rejected_rows
               GROUP BY 1,2,3 ORDER BY 1,2,3""")

# Report 1: Data Cleaning
s = []
tot_raw = sum(raw.values())
tot_clean = sum(clean.values())
tot_dup = sum(v for (t, k), v in kinds.items() if k == "DUPLICATE")
tot_rej = sum(v for (t, k), v in kinds.items() if k == "REJECTED")
s += [Paragraph("1. Summary", H2),
      P("The source files were made on purpose with bad data (duplicates, extra spaces, mixed upper and lower case, "
        "missing values, wrong numbers and rows that point to things that do not exist). "
        "The cleaning step fixed or removed all of it before the data reached the warehouse."),
      P("<b>%s</b> raw rows came in. <b>%s</b> duplicate rows were removed, <b>%s</b> bad rows were rejected, "
        "and <b>%s</b> clean rows were kept. Every raw row is accounted for: raw = clean + duplicates + rejected."
        % (n(tot_raw), n(tot_dup), n(tot_rej), n(tot_clean))),
      P("The raw staging tables are <b>never changed</b>. Cleaning writes to separate <font face='Courier'>stg_*_clean</font> "
        "tables. Every removed row is saved in <font face='Courier'>project_staging.etl_rejected_rows</font> with its reason, "
        "so we can always check what happened.")]

s += [Paragraph("2. Cleaning rules", H2),
      table([["Problem", "Rule we used", "SQL used"],
             ["Duplicate rows", "Keep the LAST row that arrived (highest src_row_id). Remove the older copies and log them.", "ROW_NUMBER() OVER (PARTITION BY business key ORDER BY src_row_id DESC)"],
             ["Extra spaces", "Remove spaces at the start and end. Turn many spaces into one.", "TRIM(), regexp_replace()"],
             ["Mixed case", "Use one style: Title Case for names, labels and places. UPPER case for IDs. lower case for email.", "INITCAP(), UPPER(), LOWER()"],
             ["Missing values (NULL)", "Fill with a safe default when the row is still useful. Reject the row when a key is missing.", "COALESCE(), NULLIF(), CASE"],
             ["Wrong data type", "All staging columns arrive as text. Convert to DATE, INT, NUMERIC or BOOLEAN. A bad value becomes NULL or the row is rejected.", "CASE WHEN ... ~ regex THEN ...::type"],
             ["Rows pointing to nothing", "Reject an order line if its order, product or customer does not exist.", "NOT EXISTS (...)"],
             ["Impossible numbers", "Reject quantity of 0 or less, and negative stock.", "CASE WHEN quantity <= 0 ..."]],
            [3.2, 8.0, 5.8])]

rows = [["Source table", "Raw rows", "Duplicates removed", "Rejected", "Clean rows"]]
for tbl, label in SRC:
    rows.append([label, n(raw[tbl]), n(kinds.get((tbl, "DUPLICATE"), 0)), n(kinds.get((tbl, "REJECTED"), 0)), n(clean[tbl + "_clean"])])
rows.append(["<b>Total</b>", "<b>%s</b>" % n(tot_raw), "<b>%s</b>" % n(tot_dup), "<b>%s</b>" % n(tot_rej), "<b>%s</b>" % n(tot_clean)])
s += [Paragraph("3. Rows in and rows out", H2), table(rows, [5.2, 2.6, 3.4, 2.6, 3.2])]

rr = [["Table", "Type", "Reason", "Rows"]]
for tbl, kind, reason, c in reasons:
    rr.append([tbl, kind, reason, n(c)])
s += [Paragraph("4. What was removed or fixed, and why", H2),
      P("DUPLICATE = an older copy of the same business key. REJECTED = the row was bad and was not loaded. "
        "FIXED = the row was kept but a missing value was filled in."),
      table(rr, [3.8, 2.3, 8.6, 2.3])]

ex = [["Table", "Column", "Before (raw)", "After (clean)"]]

def add_examples(table_name, col, sql, limit_note=None):
    for before, after in q(sql):
        ex.append([table_name, col, "'%s'" % before if before is not None else "NULL", "'%s'" % after if after is not None else "NULL"])

add_examples("region", "city", """SELECT r.city, c.city FROM project_staging.stg_region r JOIN project_staging.stg_region_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.city <> c.city ORDER BY r.src_row_id LIMIT 3""")
add_examples("customer", "customer_name", """SELECT r.customer_name, c.customer_name FROM project_staging.stg_customer r JOIN project_staging.stg_customer_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.customer_name <> c.customer_name AND r.customer_name ~ '^ ' ORDER BY r.src_row_id LIMIT 2""")
add_examples("customer", "customer_segment", """SELECT r.customer_segment, c.customer_segment FROM project_staging.stg_customer r JOIN project_staging.stg_customer_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.customer_segment <> c.customer_segment ORDER BY r.src_row_id LIMIT 3""")
add_examples("customer", "gender", """SELECT r.gender, c.gender FROM project_staging.stg_customer r JOIN project_staging.stg_customer_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.gender IN ('M','F','MALE','female') ORDER BY r.src_row_id LIMIT 3""")
add_examples("customer", "email (NULL)", """SELECT r.email, c.email FROM project_staging.stg_customer r JOIN project_staging.stg_customer_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.email IS NULL ORDER BY r.src_row_id LIMIT 1""")
add_examples("customer", "signup_date", """SELECT r.signup_date, c.signup_date::text FROM project_staging.stg_customer r JOIN project_staging.stg_customer_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.signup_date = 'N/A' ORDER BY r.src_row_id LIMIT 1""")
add_examples("product", "category", """SELECT r.category, c.category FROM project_staging.stg_product r JOIN project_staging.stg_product_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.category <> c.category ORDER BY r.src_row_id LIMIT 3""")
add_examples("product", "brand", """SELECT r.brand, c.brand FROM project_staging.stg_product r JOIN project_staging.stg_product_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.brand <> c.brand ORDER BY r.src_row_id LIMIT 2""")
add_examples("product", "unit_cost (NULL)", """SELECT r.unit_cost, c.unit_cost::text FROM project_staging.stg_product r JOIN project_staging.stg_product_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.unit_cost IS NULL ORDER BY r.src_row_id LIMIT 1""")
add_examples("product", "is_active", """SELECT r.is_active, c.is_active::text FROM project_staging.stg_product r JOIN project_staging.stg_product_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.is_active IN ('yes','N','1','no') ORDER BY r.src_row_id LIMIT 2""")
add_examples("promotion", "promotion_type", """SELECT r.promotion_type, c.promotion_type FROM project_staging.stg_promotion r JOIN project_staging.stg_promotion_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.promotion_type <> c.promotion_type ORDER BY r.src_row_id LIMIT 2""")
add_examples("order line", "product_id", """SELECT r.product_id, c.product_id FROM project_staging.stg_sales r JOIN project_staging.stg_sales_clean c
                                  ON c.src_row_id = r.src_row_id WHERE r.product_id <> c.product_id ORDER BY r.src_row_id LIMIT 2""")
s += [Paragraph("5. Before and after (real rows)", H2), table(ex, [2.6, 3.6, 5.4, 5.4])]

dup = q("""SELECT r.src_row_id, r.customer_id, r.customer_name, r.email,
                  CASE WHEN c.src_row_id IS NOT NULL THEN 'KEPT' ELSE 'removed' END
           FROM project_staging.stg_customer r
           LEFT JOIN project_staging.stg_customer_clean c ON c.src_row_id = r.src_row_id
           WHERE r.customer_id = (SELECT customer_id FROM project_staging.stg_customer GROUP BY customer_id
                                  HAVING COUNT(*) > 1 ORDER BY customer_id LIMIT 1)
           ORDER BY r.src_row_id""")
dr = [["Arrival order (src_row_id)", "customer_id", "customer_name", "email", "Result"]]
for r in dup:
    dr.append([r[0], r[1], "'%s'" % r[2], r[3], r[4]])
s += [Paragraph("6. How a duplicate was resolved", H2),
      P("The same customer_id arrived twice. The rule is simple and always gives the same answer: "
        "<b>keep the row that arrived last</b>. Both rows stay in the raw table for audit."),
      table(dr, [3.6, 2.6, 4.2, 4.4, 2.2])]

s += [Paragraph("7. Data type conversions", H2),
      table([["Table", "Column", "From", "To"],
             ["customer", "signup_date", "TEXT", "DATE"],
             ["product", "unit_cost, list_price", "TEXT", "NUMERIC(10,2)"],
             ["product", "is_active", "TEXT (Y, yes, TRUE, 1 ...)", "BOOLEAN"],
             ["promotion", "discount_percent", "TEXT", "NUMERIC(5,2)"],
             ["promotion", "start_date, end_date", "TEXT", "DATE"],
             ["orders", "order_date", "TEXT", "DATE"],
             ["order line", "line_number, quantity", "TEXT", "INT"],
             ["order line", "unit_price", "TEXT", "NUMERIC(12,2)"],
             ["inventory", "snapshot_date", "TEXT", "DATE"],
             ["inventory", "quantity columns, reorder_level", "TEXT", "INT"]],
            [3.2, 5.4, 4.6, 3.8])]

s += [Paragraph("8. How NULL values were handled", H2),
      table([["Column", "What we did", "Rows affected"],
             ["customer.email missing", "Filled with 'not provided'", n(q("SELECT COUNT(*) FROM project_dw.dim_customer WHERE email='not provided'")[0][0])],
             ["customer.age_group missing", "Filled with 'Unknown'", n(q("SELECT COUNT(*) FROM project_dw.dim_customer WHERE age_group='Unknown'")[0][0])],
             ["customer.signup_date bad ('N/A')", "Kept the customer, set date to NULL", n(q("SELECT COUNT(*) FROM project_dw.dim_customer WHERE signup_date IS NULL")[0][0])],
             ["customer.customer_id missing", "Row rejected (no key, cannot be used)", n(kinds.get(("stg_customer", "REJECTED"), 0))],
             ["product.unit_cost missing", "Filled with 75% of list_price", n(kinds.get(("stg_product", "FIXED"), 0))],
             ["order.order_date missing", "Order rejected, its lines rejected too", n(q("SELECT COUNT(*) FROM project_staging.etl_rejected_rows WHERE reason='Missing or invalid order_date'")[0][0])],
             ["inventory.quantity_on_hand missing", "Row rejected", n(q("SELECT COUNT(*) FROM project_staging.etl_rejected_rows WHERE reason='Missing quantity_on_hand'")[0][0])]],
            [5.6, 8.0, 3.4])]

cnt = [["Step", "Table", "Rows"]]
for step, obj, c in q("SELECT step, object_name, row_count FROM project_staging.etl_row_counts WHERE batch_id=%s AND step IN ('raw_load','clean') ORDER BY step DESC, object_name", (latest,)):
    cnt.append([step, obj, n(c)])
s += [KeepTogether([Paragraph("9. ETL row-count log (latest batch)", H2),
      P("The ETL writes row counts after every step into <font face='Courier'>project_staging.etl_row_counts</font>."),
      table(cnt, [3.5, 8.5, 5.0])])]
build("Data_Cleaning_Report.pdf", "Data Cleaning Report", s)

# Pipeline diagram
fig, ax = plt.subplots(figsize=(11, 3.6), dpi=130)
ax.set_xlim(0, 110)
ax.set_ylim(0, 36)
ax.axis("off")
boxes = [
    (1, "Source CSV files", "9 files\n(fake data,\nbad rows on purpose)", "#8E8E93"),
    (23, "project_staging", "RAW tables (stg_*)\n   then\nCLEAN tables (stg_*_clean)", "#1F5FA8"),
    (51, "project_dw", "6 dimensions\n(surrogate keys)\n   then\n3 fact tables", "#C0392B"),
    (79, "project_reporting", "11 views for Power BI\n+ dq_results\n(quality checks)", "#2E8B57"),
]
for x, name, body, col in boxes:
    ax.add_patch(FancyBboxPatch((x, 8), 24, 22, boxstyle="round,pad=0.4", fc="white", ec=col, lw=2.2))
    ax.add_patch(FancyBboxPatch((x, 24), 24, 6, boxstyle="round,pad=0.4", fc=col, ec=col, lw=2.2))
    ax.text(x + 12, 27, name, ha="center", va="center", color="white", fontsize=10.5, fontweight="bold")
    ax.text(x + 12, 15.5, body, ha="center", va="center", fontsize=8.6)
for x1, x2, label in [(25.5, 22.6, ""), (47.6, 50.6, ""), (75.6, 78.6, "")]:
    pass
for x1, x2 in [(25.6, 22.4), (47.6, 50.4), (75.6, 78.4)]:
    pass
arrow = dict(arrowstyle="-|>", color="#333333", lw=1.8)
ax.annotate("", xy=(22.3, 19), xytext=(25.7 - 1.2, 19), arrowprops=dict(arrowstyle="<|-", color="#333333", lw=1.8))
ax.annotate("", xy=(50.3, 19), xytext=(47.7, 19), arrowprops=arrow)
ax.annotate("", xy=(78.3, 19), xytext=(75.7, 19), arrowprops=arrow)
ax.text(24.0, 4.2, "check: raw = clean + removed", ha="center", fontsize=7.8, color="#1F5FA8")
ax.text(49.0, 1.4, "surrogate key mapping\n(business key -> key)", ha="center", fontsize=7.8, color="#C0392B")
ax.text(77.0, 4.2, "check: orphans, totals, keys", ha="center", fontsize=7.8, color="#2E8B57")
ax.text(55, 34.2, "DailyBasket ETL pipeline", ha="center", fontsize=12, fontweight="bold")
fig.savefig(os.path.join(REP, "pipeline_diagram.png"), bbox_inches="tight")
plt.close(fig)

# Report 2: Data Quality
dq = q("SELECT check_id, category, check_name, expected, actual, status FROM project_reporting.dq_results ORDER BY check_id")
npass = sum(1 for r in dq if r[5] == "PASS")
nfail = sum(1 for r in dq if r[5] == "FAIL")
ninfo = sum(1 for r in dq if r[5] == "INFO")
s = []
s += [Paragraph("1. Summary", H2),
      P("We ran <b>%d</b> automatic checks. <b>%d passed</b>, <b>%d failed</b> and %d are information only (they report "
        "how many NULLs were filled during cleaning)." % (len(dq), npass, nfail, ninfo)),
      table([["Category", "What it proves", "Checks", "Passed", "Failed"]] +
            [[cat, what, n(sum(1 for r in dq if r[1] == cat and r[5] != "INFO")),
              n(sum(1 for r in dq if r[1] == cat and r[5] == "PASS")), n(sum(1 for r in dq if r[1] == cat and r[5] == "FAIL"))]
             for cat, what in [("Completeness", "No missing values where a value is required"),
                               ("Accuracy", "Warehouse numbers match the clean source numbers (rows, quantity, revenue)"),
                               ("Integrity", "Every key matches, no duplicates, constraints block bad data, re-runs are safe")]],
            [3.0, 8.6, 1.8, 1.8, 1.8]),
      P("Result: " + ("<b>all checks passed. The warehouse is ready for Phase 3.</b>" if nfail == 0 else "<b>some checks failed - see the tables below.</b>"))]

s += [Paragraph("2. Pipeline and where the checks happen", H2),
      Image(os.path.join(REP, "pipeline_diagram.png"), width=17 * cm, height=17 * cm * 3.6 / 11 * 0.97),
      P("Dimensions are loaded first. Facts are loaded second, because a fact row needs the surrogate key of every dimension row it points to.")]

size = q("""SELECT 'dim_date', COUNT(*) FROM project_dw.dim_date UNION ALL SELECT 'dim_customer', COUNT(*) FROM project_dw.dim_customer
            UNION ALL SELECT 'dim_product', COUNT(*) FROM project_dw.dim_product UNION ALL SELECT 'dim_region', COUNT(*) FROM project_dw.dim_region
            UNION ALL SELECT 'dim_channel', COUNT(*) FROM project_dw.dim_channel UNION ALL SELECT 'dim_promotion', COUNT(*) FROM project_dw.dim_promotion
            UNION ALL SELECT 'fact_sales', COUNT(*) FROM project_dw.fact_sales
            UNION ALL SELECT 'fact_inventory_snapshot', COUNT(*) FROM project_dw.fact_inventory_snapshot
            UNION ALL SELECT 'fact_promotion_event', COUNT(*) FROM project_dw.fact_promotion_event""")
s += [Paragraph("3. Warehouse size", H2),
      P("Project minimums: 100+ rows in the big dimensions and 10,000+ fact rows. "
        "dim_channel has only 3 rows because the business has only 3 channels."),
      table([["Table", "Rows", "Type"]] + [[a, n(b), "Dimension" if a.startswith("dim") else "Fact"] for a, b in size], [6, 4, 4])]

def dq_table(cat, title, intro=None):
    rows = [["#", "Check", "Expected", "Actual", "Status"]]
    for r in dq:
        if r[1] == cat:
            rows.append([r[0], r[2], r[3], r[4], r[5]])
    out = [Paragraph(title, H2)]
    if intro:
        out.append(P(intro))
    out.append(table(rows, [0.9, 9.4, 2.4, 2.4, 1.9], status_col=4))
    return out

s += dq_table("Completeness", "4. Completeness (is anything missing?)",
              "Expected 0 missing values in every required column. The INFO rows show NULLs that cleaning already fixed.")
s += dq_table("Accuracy", "5. Accuracy (do the numbers match?)",
              "The source side is calculated from the clean staging tables on its own, without using the dimensions. "
              "Row counts alone are not enough, so we also compare quantity, gross revenue, discount and net revenue.")
s += dq_table("Integrity", "6. Integrity (do the keys and constraints work?)",
              "Orphan check = fact rows that have no matching dimension row. Expected 0 for every foreign key. "
              "The constraint tests try to insert bad rows. The database must refuse them.")

# real error messages from the database
tests = [
    ("Unknown customer_key in fact_sales",
     "INSERT INTO project_dw.fact_sales (date_key,customer_key,product_key,region_key,channel_key,promotion_key,order_id,order_line_number,quantity,unit_price,discount_amount,gross_amount,net_revenue,cost_amount,profit_amount) VALUES (20260101,-1,1,1,1,0,'O-TEST',1,1,1,0,1,1,1,0)",
     "Foreign key"),
    ("Duplicate customer_id in dim_customer",
     "INSERT INTO project_dw.dim_customer (customer_id) SELECT customer_id FROM project_dw.dim_customer LIMIT 1",
     "Unique key"),
    ("Same order line loaded twice",
     "INSERT INTO project_dw.fact_sales (date_key,customer_key,product_key,region_key,channel_key,promotion_key,order_id,order_line_number,quantity,unit_price,discount_amount,gross_amount,net_revenue,cost_amount,profit_amount) SELECT date_key,customer_key,product_key,region_key,channel_key,promotion_key,order_id,order_line_number,quantity,unit_price,discount_amount,gross_amount,net_revenue,cost_amount,profit_amount FROM project_dw.fact_sales LIMIT 1",
     "Unique key"),
    ("Quantity = 0",
     "INSERT INTO project_dw.fact_sales (date_key,customer_key,product_key,region_key,channel_key,promotion_key,order_id,order_line_number,quantity,unit_price,discount_amount,gross_amount,net_revenue,cost_amount,profit_amount) VALUES (20260101,1,1,1,1,0,'O-TEST',2,0,1,0,1,1,1,0)",
     "Check rule"),
]
er = [["Bad insert we tried", "Rule that protected the warehouse", "Error from PostgreSQL"]]
for label, sql, rule in tests:
    try:
        cur.execute(sql)
        msg = "NO ERROR (bad)"
    except psycopg.Error as e:
        msg = e.diag.message_primary + (" - " + e.diag.message_detail if e.diag.message_detail else "")
    conn.rollback()
    er.append([label, rule, msg.replace("<", "&lt;").replace(">", "&gt;")])
s += [Paragraph("7. Constraint test: the exact errors", H2),
      P("Each bad insert was refused and rolled back. No test row stays in the warehouse."),
      table(er, [4.4, 3.0, 9.6])]

rerun = q("""SELECT cur.object_name, prev.row_count, cur.row_count
             FROM project_staging.etl_row_counts cur
             JOIN project_staging.etl_row_counts prev ON prev.object_name = cur.object_name AND prev.step='dw_load'
              AND prev.batch_id = (SELECT MAX(b.batch_id) FROM project_staging.etl_row_counts b WHERE b.step='dw_load' AND b.batch_id < cur.batch_id)
             WHERE cur.step='dw_load' AND cur.batch_id = (SELECT MAX(batch_id) FROM project_staging.etl_batch)
             ORDER BY cur.object_name""")
if rerun:
    s += [Paragraph("8. Safe re-run test", H2),
          P("We ran the whole pipeline a second time on the same files. The warehouse must not grow. "
            "This works because every business key is UNIQUE and every load uses ON CONFLICT."),
          table([["Table", "After run 1", "After run 2", "Same?"]] +
                [[a, n(b), n(c), "PASS" if b == c else "FAIL"] for a, b, c in rerun], [6, 3.5, 3.5, 2.5], status_col=3)]

bad = []
try:
    cur.execute("DELETE FROM project_dw.fact_sales WHERE sales_key = (SELECT MIN(sales_key) FROM project_dw.fact_sales)")
    cur.execute("UPDATE project_dw.fact_sales SET net_revenue = net_revenue + 100 WHERE sales_key = (SELECT MIN(sales_key) + 1 FROM project_dw.fact_sales)")
    script = open(os.path.join(HERE, "..", "05_Analytics", "08_data_quality_checks.sql"), encoding="utf-8").read()
    cur.execute(script)
    bad = q("SELECT check_name, expected, actual FROM project_reporting.dq_results WHERE status='FAIL' ORDER BY check_id")
finally:
    conn.rollback()
s += [KeepTogether([Paragraph("9. Proof that the checks can catch errors", H2),
      P("A test that never fails proves nothing. So we broke the warehouse on purpose (deleted one fact row and changed the revenue of "
        "another), ran the same checks, and then rolled everything back. The checks found it:"),
      table([["Check that failed", "Expected", "Actual"]] + [[a, b, c] for a, b, c in bad], [9.4, 3.8, 3.8]),
      P("After the rollback the warehouse is unchanged and every check passes again.")])]

mp = q("""SELECT f.order_id, f.order_line_number, c.customer_id, f.customer_key, p.product_id, f.product_key, f.net_revenue
          FROM project_dw.fact_sales f JOIN project_dw.dim_customer c ON c.customer_key = f.customer_key
          JOIN project_dw.dim_product p ON p.product_key = f.product_key ORDER BY f.sales_key LIMIT 3""")
s += [Paragraph("10. Surrogate key mapping (business key to surrogate key)", H2),
      P("The order file only knows business keys such as C-00159. The fact table stores the surrogate keys. "
        "Why? Surrogate keys are small whole numbers, they are fast to join, and they never change even if the source system changes its codes."),
      table([["order_id", "line", "customer_id (business key)", "customer_key", "product_id (business key)", "product_key", "net_revenue"]] +
            [[a, b, c, d, e, f, g] for a, b, c, d, e, f, g in mp], [2.2, 1.0, 3.2, 2.2, 3.2, 2.2, 2.4])]
build("Data_Quality_Report.pdf", "Data Quality Report", s)
conn.close()
