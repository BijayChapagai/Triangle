import re, xml.etree.ElementTree as ET

data = open("eat the cube.rbxlx", encoding="utf-8", errors="replace").read()
tree = ET.fromstring(data)

# Build name map by class under their parents
def find(parent, name, cls=None):
    for it in parent:
        if it.tag != "Item":
            continue
        nm = it.find("Properties/string[@name='Name']")
        if nm is not None and nm.text == name and (cls is None or it.get("class") == cls):
            return it
    return None

root = tree
# top-level services
def top(name):
    for it in root:
        if it.tag == "Item" and it.get("class") in ("Workspace","ServerScriptService","ReplicatedStorage","StarterGui") :
            nm = it.find("Properties/string[@name='Name']")
            if nm is not None and nm.text == name:
                return it
    return None

sss = top("ServerScriptService")
rs = top("ReplicatedStorage")
sg = top("StarterGui")
ws = top("Workspace")

def children(it):
    return [c for c in it if c.tag == "Item"]

# new server scripts
checks = []
def has_script(parent, name, cls):
    for c in children(parent):
        nm = c.find("Properties/string[@name='Name']")
        if nm is not None and nm.text == name and c.get("class") == cls:
            return True
    return False

checks.append(("ServerScriptService/Progression (ModuleScript)", has_script(sss,"Progression","ModuleScript")))
modules = find(rs,"Modules","Folder")
checks.append(("ReplicatedStorage/Modules/ProgressionConfig (ModuleScript)", has_script(modules,"ProgressionConfig","ModuleScript")))
checks.append(("ServerScriptService/FoodSpawner (Script)", has_script(sss,"FoodSpawner","ModuleScript")))
checks.append(("ServerScriptService/ProgressionServer (Script)", has_script(sss,"ProgressionServer","ModuleScript")))
checks.append(("ServerScriptService/AdminServer (Script)", has_script(sss,"AdminServer","ModuleScript")))

# events
events = find(rs,"Events","Folder")
ev_names = []
for c in children(events):
    nm = c.find("Properties/string[@name='Name']")
    if nm is not None: ev_names.append(nm.text)
for need in ["Rebirth","EquipSkin","SkinList","Leaderboard","QuestFetch","QuestClaim","ZoneTeleport","Admin"]:
    checks.append((f"RemoteEvent {need}", need in ev_names))

# frames + buttons
frames = find(sg,"Frames","ScreenGui")
frame_names = [c.find("Properties/string[@name='Name']").text for c in children(frames) if c.tag=="Item"]
for need in ["Rebirth","Skins","Leaderboard","Quests","Zones","Admin"]:
    checks.append((f"Frame {need}", need in frame_names))

buttons = find(sg,"Buttons","ScreenGui")
btn_names = [c.find("Properties/string[@name='Name']").text for c in children(buttons) if c.tag=="Item"]
for need in ["Rebirth","Skins","Leaderboard","Quests","Zones","Admin"]:
    checks.append((f"Button {need}", need in btn_names))

# zones
zone_names = []
for c in children(ws):
    nm = c.find("Properties/string[@name='Name']")
    if nm is not None and nm.text in ("Greenfield","Crystal Cave","Lava Forge","Frozen Peak","Void Core"):
        zone_names.append(nm.text)
checks.append(("5 zone platforms", len(zone_names)==5))

print("=== VERIFICATION ===")
ok = True
for label, res in checks:
    print(("PASS" if res else "FAIL"), "-", label)
    if not res: ok = False
print("\nEvents present:", sorted(ev_names))
print("Frames:", sorted(frame_names))
print("Buttons:", sorted(btn_names))
print("Zones:", sorted(zone_names))
print("\nALL GOOD" if ok else "\nSOME FAILED")
