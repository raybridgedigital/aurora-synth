#!/usr/bin/env python3
"""Assemble reviewed recipes into Aurora's bundled and individually importable bank."""
from collections import Counter
from pathlib import Path
import hashlib
import json
import math
import zipfile

ROOT = Path(__file__).resolve().parent.parent
CATEGORIES = ["Pads", "Bass", "Leads", "Keys", "Plucks", "Arps", "Textures", "Organs", "Brass & Strings", "Splits"]
DEFAULTS = [1,2,1,.35,7,.12,0,2600,.15,.025,.35,.75,.7,.65,0,0,.4,.12,0,0,.15,.08,0,2,0,1,.65,0,127,.16,.06,2,0]
RANGES = [(0,1),(0,4),(0,4),(0,1),(0,30),(0,1),(0,1),(30,18000),(0,.9),(.001,8),(.01,8),(0,1),(.01,12),(0,1),(-1,1),(-48,48),(.03,20),(0,1),(0,3),(0,4),(-1,1),(0,1),(0,1),(0,3),(0,3),(1,4),(.1,.95),(0,127),(0,127),(.03,20),(0,1),(0,3),(0,2)]
INTEGER = {0,1,2,15,18,19,22,23,24,25,27,28,31,32}
GLOBAL_RANGES = [(0,.75),(30,240),(0,.6),(0,.75),(0,.75),(0,.6)]

def checked(value, bounds, label, integer=False):
    assert isinstance(value,(int,float)) and not isinstance(value,bool) and math.isfinite(value), f"{label}: invalid number"
    assert bounds[0] <= value <= bounds[1], f"{label}: {value} outside {bounds}"
    assert not integer or value == int(value), f"{label}: integer required"
    return value

def assemble():
    recipes = []
    for name in ["Tonal.json", "Character.json"]:
        recipes.extend(json.loads((ROOT / "Resources/PatchRecipes" / name).read_text()))
    assert len(recipes)==100, f"Expected 100 recipes, found {len(recipes)}"
    assert Counter(p["category"] for p in recipes)==Counter({c:10 for c in CATEGORIES})
    assert len({p["id"] for p in recipes})==100
    assert len({p["name"].casefold() for p in recipes})==100
    result=[]
    signatures=set()
    for recipe in recipes:
        name=recipe["name"]
        assert recipe["id"].startswith("a100-") and all(c.isalnum() or c=="-" for c in recipe["id"])
        assert 1<=len(recipe["layers"])<=4
        layers=[]
        for i in range(4):
            values={str(p):v for p,v in enumerate(DEFAULTS)}
            if i < len(recipe["layers"]):
                for p,v in recipe["layers"][i].items():
                    assert p.isdigit() and 0<=int(p)<33, f"{name}: unknown parameter {p}"
                    values[p]=checked(v,RANGES[int(p)],f"{name}/layer{i}/{p}",int(p) in INTEGER)
                values["0"]=1
            else:
                values["0"]=0
            assert values["27"]<=values["28"], f"{name}: reversed key range"
            layers.append({"values":values})
        globals_=recipe["globals"]
        assert len(globals_)==6
        for i,v in enumerate(globals_): checked(v,GLOBAL_RANGES[i],f"{name}/global{i}")
        assert globals_[0]==.25, f"{name}: factory reference master must stay at 25%"
        active=[l for l in layers if l["values"]["0"]]
        signature=hashlib.sha256(json.dumps([active,globals_[1:]],sort_keys=True).encode()).hexdigest()
        assert signature not in signatures, f"{name}: duplicate sound settings"
        signatures.add(signature)
        if recipe["category"]=="Arps": assert any(l["values"]["22"] for l in active)
        if recipe["category"]=="Splits":
            assert any(l["values"]["28"]==59 for l in active)
            assert any(l["values"]["27"]==60 for l in active)
        result.append({"id":recipe["id"],"name":name,"category":recipe["category"],"detail":recipe["detail"],"layers":layers,"globals":globals_,"macros":[.5]*8})
    result.sort(key=lambda p:(CATEGORIES.index(p["category"]),p["name"]))
    (ROOT/"Resources/Aurora100.json").write_text(json.dumps(result,indent=2,ensure_ascii=False)+"\n")
    # An archive with one full preset per file works with the app's existing import.
    output=ROOT/"Patch Banks"
    output.mkdir(exist_ok=True)
    with zipfile.ZipFile(output/"Aurora 100 Patches.zip","w",zipfile.ZIP_DEFLATED) as archive:
        for p in result:
            info=zipfile.ZipInfo(f"Aurora 100/{p['category']}/{p['id']}.aurora.json",date_time=(2026,9,17,0,0,0));info.compress_type=zipfile.ZIP_DEFLATED
            archive.writestr(info,json.dumps(p,indent=2,ensure_ascii=False)+"\n")
    lines=["# Aurora 100 — patch catalog","","100 new performances in ten categories. The original 12 starter sounds are also retained in the app.","","Select **Aurora 100** in the sound library, then choose a category. Use the same moderate Master setting when comparing sounds; loading a patch preserves your listening level.","","Each patch uses Aurora's actual oscillators, filters, two LFOs, envelopes, arpeggiator, and shared effects. Keys, organs, brass, and strings are synthesized interpretations, not sampled acoustic instruments.","","The grouped ZIP contains individual `.aurora.json` files. Extract it and use **Sound library → More → Import preset** for an individual sound. The updated app includes all 100 automatically.",""]
    for category in CATEGORIES:
        lines.extend([f"## {category} · 10 patches","","| Patch | Character and playing suggestion |","|---|---|"])
        for p in result:
            if p["category"]==category: lines.append(f"| {p['name']} | {p['detail']} |")
        lines.append("")
    (output/"Aurora 100 Catalog.md").write_text("\n".join(lines))
    print("Assembled 100 unique patches: "+", ".join(f"{c} (10)" for c in CATEGORIES))

if __name__=="__main__":
    raise SystemExit("Retired: this generator writes the classic factory banks, which are archived in archive/factory-banks and no longer ship. The module stays importable because live generators reuse its tables; build the current bank with scripts/assemble_modx_bank.py.")
