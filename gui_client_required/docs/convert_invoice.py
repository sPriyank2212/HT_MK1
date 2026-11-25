"""
SELLER  : Vimtex Synthetics (ALL original details UNCHANGED)
BUYER   : INFINITY INTEGRATIONS PRIVATE LIMITED, Hyderabad, Telangana
PRODUCT : 3 line items per image
AMOUNT  : Rs 1,53,000  +  IGST 18% (Rs 27,540)  =  Rs 1,80,540
"""
import zipfile, re

SRC = "CHETANBHAI TAX INVOICE.xlsm"
DST = "Harness_Tester_Tax_Invoice.xlsm"

with zipfile.ZipFile(SRC, "r") as z:
    files = {name: z.read(name) for name in z.namelist()}

# ── shared strings ─────────────────────────────────────────────────────────
ss = files["xl/sharedStrings.xml"].decode("utf-8")

si_count   = ss.count("<si>")   # actual total before we add
prod2_idx  = si_count            # new string: product 2
prod3_idx  = si_count + 1        # new string: product 3

TEXT = [
    # buyer (longest first to avoid substring collisions)
    ("Infinity Integrations Private Limited",
     "INFINITY INTEGRATIONS PRIVATE LIMITED"),
    ("E-14/2207/1, Dying Complex, Bahadur Ke Road, Ludhiana,",
     "3 Floor, 1-118/1/14/C Jayabheri Silicon Towers"),
    ("Punjab - 141008, India",
     "Hitech City Road, Hyderabad, 500084"),
    ("03AIUPJ3600M2Z5",     "36AAICI3401Q1ZB"),   # GSTIN first …
    ("AIUPJ3600M",          "AAICI3401Q1"),        # … then PAN (capital A fix)
    ("PUNJAB, Code : 03",   "TELANGANA, Code : 36"),
    ("PUNJAB",              "TELANGANA"),
    # invoice details
    ("INV/001/26-27",       "INV/003/26-27"),
    ("Opp Cozy Hotel,Narol","IMMEDIATE"),           # Mode/Terms of Payment
    # product 1 description (SOW already caps)
    ("NuPrint RT-60 Kg",
     "I2PL-IHT-MK0 (M1,M2,M3 And M4 as per SOW)"),
    # per-unit column: kg -> Cover
    ("<t>kg</t>",           "<t>Cover</t>"),
    ("<t>1*60 KG</t>",      "<t> </t>"),
    # HSN
    ("58063120",            "9998314"),
    # GST rate
    ("Output IGST@5%",      "Output IGST@18%"),
    ("<t>5%</t>",           "<t>18%</t>"),
    # amount in words: LAKH (not Lac) + Forty (not Fourty)
    ("Nineteen Thousand Seven Hundred Fifty Four Indian Rupees Only",
     "One Lakh Eighty Thousand Five Hundred Forty Rupees Only"),
    ("Three Thousand Fourteen Indian Rupees Only",
     "Twenty Seven Thousand Five Hundred Forty Rupees Only"),
]

for old, new in TEXT:
    ss = ss.replace(old, new)

# append two new shared strings for products 2 and 3
new_si = (
    '<si><t xml:space="preserve">'
    'I2PL-UNV-PI-MK0 (M1 And M2 as per SOW)'
    '</t></si>'
    '<si><t xml:space="preserve">'
    'I2PL-IHT-MKI (M1 And M2 as per SOW)'
    '</t></si>'
)
new_total = si_count + 2
ss = re.sub(r'count="\d+"',       f'count="{new_total}"',       ss)
ss = re.sub(r'uniqueCount="\d+"', f'uniqueCount="{new_total}"', ss)
ss = ss.replace("</sst>", new_si + "</sst>")

files["xl/sharedStrings.xml"] = ss.encode("utf-8")

# ── sheet1.xml ─────────────────────────────────────────────────────────────
sheet = files["xl/worksheets/sheet1.xml"].decode("utf-8")

# Row 22 – product 1: qty 1/1, rate 38000, amount 38000
sheet = sheet.replace('<c r="G22" s="73"><v>60</v></c>',
                      '<c r="G22" s="73"><v>1</v></c>')
sheet = sheet.replace('<c r="H22" s="74"><v>60</v></c>',
                      '<c r="H22" s="74"><v>1</v></c>')
sheet = sheet.replace('<c r="I22" s="75"><v>279</v></c>',
                      '<c r="I22" s="75"><v>38000</v></c>')
sheet = sheet.replace('<c r="L22" s="78"><f>H22*I22</f><v>16740</v></c>',
                      '<c r="L22" s="78"><f>H22*I22</f><v>38000</v></c>')

# Row 23 – product 2: qty 1/1, rate 50000, amount 50000
old23 = (
    '<c r="A23" s="16" t="s"><v>0</v></c>'
    '<c r="B23" s="42" t="s"><v>0</v></c>'
    '<c r="C23" s="95"/>'
    '<c r="D23" s="96"/>'
    '<c r="E23" s="36" t="s"><v>0</v></c>'
    '<c r="F23" s="8"/>'
    '<c r="G23" s="17"/>'
    '<c r="H23" s="18"/>'
    '<c r="I23" s="19"/>'
    '<c r="J23" s="19"/>'
    '<c r="K23" s="19"/>'
    '<c r="L23" s="17"/>'
)
new23 = (
    f'<c r="A23" s="72" t="s"><v>{prod2_idx}</v></c>'
    '<c r="B23" s="86" t="s"><v>37</v></c>'
    '<c r="C23" s="95"/>'
    '<c r="D23" s="96"/>'
    '<c r="E23" s="47" t="s"><v>88</v></c>'
    '<c r="F23" s="8"/>'
    '<c r="G23" s="73"><v>1</v></c>'
    '<c r="H23" s="74"><v>1</v></c>'
    '<c r="I23" s="75"><v>50000</v></c>'
    '<c r="J23" s="76" t="s"><v>38</v></c>'
    '<c r="K23" s="77"/>'
    '<c r="L23" s="78"><f>H23*I23</f><v>50000</v></c>'
)
sheet = sheet.replace(old23, new23)

# Row 24 – product 3: qty 1/1, rate 65000, amount 65000
old24 = (
    '<c r="A24" s="20" t="s"><v>0</v></c>'
    '<c r="B24" s="21" t="s"><v>0</v></c>'
    '<c r="C24" s="59"/>'
    '<c r="D24" s="97"/>'
    '<c r="E24" s="36" t="s"><v>0</v></c>'
    '<c r="F24" s="44" t="s"><v>84</v></c>'
    '<c r="G24" s="18"/>'
    '<c r="H24" s="22"/>'
    '<c r="I24" s="23"/>'
    '<c r="J24" s="24"/>'
    '<c r="K24" s="25"/>'
    '<c r="L24" s="91"/>'
)
new24 = (
    f'<c r="A24" s="72" t="s"><v>{prod3_idx}</v></c>'
    '<c r="B24" s="86" t="s"><v>37</v></c>'
    '<c r="C24" s="59"/>'
    '<c r="D24" s="97"/>'
    '<c r="E24" s="47" t="s"><v>88</v></c>'
    '<c r="F24" s="44" t="s"><v>84</v></c>'
    '<c r="G24" s="73"><v>1</v></c>'
    '<c r="H24" s="74"><v>1</v></c>'
    '<c r="I24" s="75"><v>65000</v></c>'
    '<c r="J24" s="76" t="s"><v>38</v></c>'
    '<c r="K24" s="77"/>'
    '<c r="L24" s="78"><f>H24*I24</f><v>65000</v></c>'
)
sheet = sheet.replace(old24, new24)

# Row 25 – IGST 18% on sum of 3 products
sheet = sheet.replace(
    '<c r="L25" s="92"><f>L22*5%</f><v>837</v></c>',
    '<c r="L25" s="92"><f>(L22+L23+L24)*18%</f><v>27540</v></c>'
)

# Row 26 – grand total
sheet = sheet.replace(
    '<c r="L26" s="27"><f>L22+L25</f><v>17577</v></c>',
    '<c r="L26" s="27"><f>L22+L23+L24+L25</f><v>180540</v></c>'
)
sheet = sheet.replace(
    '<c r="G26" s="79"><f>SUM(G22:G25)</f><v>60</v></c>',
    '<c r="G26" s="79"><f>SUM(G22:G25)</f><v>3</v></c>'
)
sheet = sheet.replace(
    '<c r="H26" s="79"><f>SUM(H22:H25)</f><v>60</v></c>',
    '<c r="H26" s="79"><f>SUM(H22:H25)</f><v>3</v></c>'
)

# GST summary (rows 31-32)
sheet = sheet.replace(
    '<c r="G31" s="90"><f>L22</f><v>16740</v></c>',
    '<c r="G31" s="90"><f>L22+L23+L24</f><v>153000</v></c>'
)
sheet = sheet.replace(
    '<c r="J31" s="123"><f>G31*5%</f><v>837</v></c>',
    '<c r="J31" s="123"><f>G31*18%</f><v>27540</v></c>'
)
sheet = sheet.replace(
    '<c r="L31" s="45"><f>J31</f><v>837</v></c>',
    '<c r="L31" s="45"><f>J31</f><v>27540</v></c>'
)
sheet = sheet.replace(
    '<c r="G32" s="89"><f>SUM(G31)</f><v>16740</v></c>',
    '<c r="G32" s="89"><f>SUM(G31)</f><v>153000</v></c>'
)
sheet = sheet.replace(
    '<c r="J32" s="149"><f>SUM(J31)</f><v>837</v></c>',
    '<c r="J32" s="149"><f>SUM(J31)</f><v>27540</v></c>'
)
sheet = sheet.replace(
    '<c r="L32" s="46"><f>SUM(L31)</f><v>837</v></c>',
    '<c r="L32" s="46"><f>SUM(L31)</f><v>27540</v></c>'
)
# HSN cached value in formula cell
sheet = sheet.replace(
    '<c r="A31" s="109" t="str"><f>E22</f><v>58063120</v></c>',
    '<c r="A31" s="109" t="str"><f>E22</f><v>9998314</v></c>'
)

files["xl/worksheets/sheet1.xml"] = sheet.encode("utf-8")

files.pop("xl/calcChain.xml", None)

with zipfile.ZipFile(DST, "w", zipfile.ZIP_DEFLATED) as zout:
    for name, data in files.items():
        zout.writestr(name, data)

print("Created: " + DST)
