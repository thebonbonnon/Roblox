"""
Generates src/shared/ModelSpecs.json, the part-by-part definition of every unit model.

Run:  python3 tools/gen_models.py
This also writes tools/model-viewer.html, a 3D preview you can open in any browser.

Coordinates are in studs, relative to the model's ground point (y = 0 is the floor).
Models face -Z (Roblox's LookVector), so +X is the model's right side.

Part fields
  name      unique within the model
  shape     box | ball | cyl | wedge | head
  size      box/wedge: [x, y, z]   ball: [diameter]   cyl: [height, diameter] (vertical axis)
            head: [2, 1, 1], the classic R6 head (a Part with a Head SpecialMesh)
  pos       [x, y, z] center
  rot       optional [x, y, z] degrees, applied as CFrame.Angles (XYZ)
  color     [r, g, b] or one of "team", "teamDark", "teamLight"
  material  Roblox Enum.Material name
  alpha     optional transparency 0..1
  collide   optional, true if players should bump into it
  attach    R6 heroes only: the limb a gear part is welded to (Torso, Head, Left Arm, ...)

Heroes are R6 rigs (model "rig": "R6"): HumanoidRootPart + the six standard R6 body parts at
standard sizes, joined by Motor6Ds, so Roblox's R6 animations play on them and their gear can be
welded onto players' R6 avatars.
"""
import json
import math
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "src", "shared", "ModelSpecs.json")

SKIN = [234, 196, 160]
STEEL = [170, 176, 188]
STEEL_DARK = [88, 92, 104]
BLADE = [222, 228, 238]
GOLD = [232, 188, 74]
LEATHER = [112, 74, 42]
LEATHER_DARK = [70, 46, 28]
WOOD = [120, 82, 48]
BLACK = [22, 22, 26]
WHITE = [236, 236, 236]


class M:
    def __init__(self, root, bar_top, fire=None, rig=None):
        self.parts = []
        self.root = root
        self.bar_top = bar_top
        self.fire = fire
        self.rig = rig
        self.on = None  # R6 limb that following gear parts are welded to

    def add(self, name, shape, size, pos, color, material="SmoothPlastic", rot=None, alpha=None, collide=None, attach=None):
        p = {"name": name, "shape": shape, "size": [round(v, 3) for v in size],
             "pos": [round(v, 3) for v in pos], "color": color, "material": material}
        if rot:
            p["rot"] = [round(v, 2) for v in rot]
        if alpha:
            p["alpha"] = alpha
        if collide:
            p["collide"] = True
        attach = attach or self.on
        if self.rig and name not in R6_BODY:
            assert attach in R6_LIMBS, "gear part %s needs a limb" % name
            p["attach"] = attach
        assert not any(q["name"] == name for q in self.parts), name
        self.parts.append(p)
        return self

    def box(self, name, size, pos, color, material="SmoothPlastic", **kw):
        return self.add(name, "box", size, pos, color, material, **kw)

    def ball(self, name, d, pos, color, material="SmoothPlastic", **kw):
        return self.add(name, "ball", [d], pos, color, material, **kw)

    def cyl(self, name, h, d, pos, color, material="SmoothPlastic", **kw):
        return self.add(name, "cyl", [h, d], pos, color, material, **kw)

    def wedge(self, name, size, pos, color, material="SmoothPlastic", **kw):
        return self.add(name, "wedge", size, pos, color, material, **kw)

    def build(self):
        top = 0
        for p in self.parts:
            s = p["size"]
            if p["shape"] == "head":
                half = 0.625
            elif p["shape"] in ("ball", "cyl"):
                half = s[0] / 2
            else:
                half = s[1] / 2
            top = max(top, p["pos"][1] + half)
        assert any(p["name"] == self.root for p in self.parts), self.root
        out = {"root": self.root, "barTop": self.bar_top, "height": round(top, 2), "parts": self.parts}
        if self.fire:
            out["fire"] = self.fire
        if self.rig:
            out["rig"] = self.rig
        return out


# --------------------------------------------------------------------------- R6 rig
# Standard R6 body: every hero uses these exact sizes so Roblox's R6 animations line up and the
# gear fits any player's R6 avatar. Bulk (bigger armor, robes) is added as gear on top.
R6_LIMBS = ("Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg")
R6_BODY = ("HumanoidRootPart",) + R6_LIMBS


def r6(bar_top, torso, arms, legs, torso_mat="SmoothPlastic", arm_mat=None, leg_mat=None, skin=SKIN):
    m = M("HumanoidRootPart", bar_top=bar_top, rig="R6")
    m.box("HumanoidRootPart", [2, 2, 1], [0, 3, 0], [163, 162, 165], alpha=1)
    m.box("Torso", [2, 2, 1], [0, 3, 0], torso, torso_mat)
    m.add("Head", "head", [2, 1, 1], [0, 4.5, 0], skin)
    m.box("Left Arm", [1, 2, 1], [-1.5, 3, 0], arms, arm_mat or torso_mat)
    m.box("Right Arm", [1, 2, 1], [1.5, 3, 0], arms, arm_mat or torso_mat)
    m.box("Left Leg", [1, 2, 1], [-0.5, 1, 0], legs, leg_mat or torso_mat)
    m.box("Right Leg", [1, 2, 1], [0.5, 1, 0], legs, leg_mat or torso_mat)
    return m


def face(m, y=4.6, z=-0.64, eye=BLACK):
    m.on = "Head"
    m.box("EyeL", [0.18, 0.22, 0.05], [-0.28, y, z], eye)
    m.box("EyeR", [0.18, 0.22, 0.05], [0.28, y, z], eye)


ARM = {"L": "Left Arm", "R": "Right Arm"}
LEG = {"L": "Left Leg", "R": "Right Leg"}


# --------------------------------------------------------------------------- heroes
def knight():
    m = r6(7.3, STEEL, STEEL, STEEL, "Metal")
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.box("Boot" + side, [1.06, 0.55, 1.16], [x, 0.28, -0.04], STEEL_DARK, "Metal")
        m.box("Knee" + side, [0.6, 0.4, 0.12], [x, 1.25, -0.53], STEEL_DARK, "Metal")
    m.on = "Torso"
    m.box("Tabard", [1.5, 1.95, 0.08], [0, 2.95, -0.54], "team", "Fabric")
    m.box("TabardCross", [0.3, 1.2, 0.04], [0, 3.15, -0.6], WHITE, "Fabric")
    m.box("TabardCrossBar", [0.9, 0.3, 0.04], [0, 3.35, -0.6], WHITE, "Fabric")
    m.box("Belt", [2.06, 0.3, 1.06], [0, 2.15, 0], LEATHER, "Fabric")
    m.box("Buckle", [0.35, 0.3, 0.08], [0, 2.15, -0.57], GOLD, "Metal")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.box("Pauldron" + side, [1.4, 0.55, 1.4], [x * 1.04, 4.05, 0], STEEL, "Metal")
        m.box("PauldronTrim" + side, [1.46, 0.16, 1.46], [x * 1.04, 3.75, 0], "team", "Metal")
        m.box("Gauntlet" + side, [1.08, 0.6, 1.08], [x, 2.25, 0], STEEL_DARK, "Metal")
    m.on = "Head"
    m.cyl("Helmet", 1.4, 1.48, [0, 4.58, 0], STEEL, "Metal")
    m.ball("HelmetDome", 1.48, [0, 5.2, 0], STEEL, "Metal")
    m.box("Visor", [1.0, 0.14, 0.08], [0, 4.62, -0.74], BLACK)
    m.box("VisorRidge", [0.14, 0.9, 0.1], [0, 4.45, -0.74], STEEL_DARK, "Metal")
    m.box("Plume", [0.22, 0.75, 1.3], [0, 6.0, 0.1], "team", "Fabric")
    m.on = "Right Arm"  # sword held forward
    m.box("SwordGrip", [0.24, 0.24, 0.8], [1.5, 2.0, -0.45], LEATHER_DARK)
    m.ball("SwordPommel", 0.36, [1.5, 2.0, -0.02], GOLD, "Metal")
    m.box("SwordGuard", [0.95, 0.2, 0.22], [1.5, 2.0, -0.92], GOLD, "Metal")
    m.box("SwordBlade", [0.32, 0.1, 3.2], [1.5, 2.0, -2.6], BLADE, "Metal")
    m.wedge("SwordTip", [0.1, 0.32, 0.45], [1.5, 2.0, -4.42], BLADE, "Metal", rot=[0, 0, 90])
    m.on = "Left Arm"  # kite shield
    m.box("Shield", [0.25, 2.2, 1.7], [-2.15, 3.1, -0.1], "team", "Metal")
    m.wedge("ShieldPointA", [0.25, 0.8, 0.85], [-2.15, 1.6, -0.525], "team", "Metal", rot=[0, 0, 180])
    m.wedge("ShieldPointB", [0.25, 0.8, 0.85], [-2.15, 1.6, 0.325], "team", "Metal", rot=[180, 0, 0])
    m.box("ShieldRim", [0.28, 0.16, 1.78], [-2.15, 4.18, -0.1], GOLD, "Metal")
    m.box("ShieldBandV", [0.28, 2.0, 0.24], [-2.17, 3.0, -0.1], WHITE, "Metal")
    m.box("ShieldBandH", [0.28, 0.24, 1.5], [-2.17, 3.4, -0.1], WHITE, "Metal")
    return m.build()


def mage():
    robe, robe_dark, robe_light = [104, 58, 176], [70, 36, 128], [168, 120, 232]
    orb = [196, 130, 255]
    m = r6(7.9, robe, robe, robe_dark, "Fabric")
    m.on = "Torso"  # long robe hangs from the waist over the legs
    m.box("Skirt", [2.15, 2.0, 1.3], [0, 1.1, 0], robe, "Fabric")
    m.box("SkirtFlare", [2.45, 0.7, 1.55], [0, 0.4, 0], robe, "Fabric")
    m.box("Hem", [2.5, 0.2, 1.6], [0, 0.12, 0], "team", "Fabric")
    m.box("Sash", [0.4, 2.7, 1.04], [0, 3.0, 0], "team", "Fabric", rot=[0, 0, 35])
    m.box("Belt", [2.06, 0.26, 1.06], [0, 2.1, 0], GOLD, "Metal")
    m.box("Collar", [2.1, 0.3, 1.1], [0, 3.95, 0], robe_light, "Fabric")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.box("Cuff" + side, [1.24, 0.55, 1.24], [x, 2.25, 0], robe_light, "Fabric")
        m.box("Hand" + side, [0.8, 0.5, 0.8], [x, 1.75, 0], SKIN)
    face(m)
    m.box("Beard", [1.0, 0.9, 0.3], [0, 4.0, -0.66], WHITE, "Fabric")
    m.box("BeardTip", [0.6, 0.45, 0.28], [0, 3.35, -0.66], WHITE, "Fabric")
    m.cyl("HatBrim", 0.16, 2.8, [0, 5.15, 0], robe_dark, "Fabric")
    m.cyl("HatBand", 0.24, 1.66, [0, 5.34, 0], "team", "Fabric")
    m.cyl("HatLow", 0.55, 1.6, [0, 5.5, 0], robe_dark, "Fabric")
    m.cyl("HatMid", 0.6, 1.2, [0.05, 6.05, 0.05], robe_dark, "Fabric", rot=[6, 0, -6])
    m.cyl("HatHigh", 0.55, 0.8, [0.15, 6.55, 0.12], robe_dark, "Fabric", rot=[12, 0, -14])
    m.ball("HatStar", 0.42, [0.3, 6.92, 0.22], GOLD, "Neon")
    m.on = "Right Arm"
    m.box("Staff", [0.24, 5.4, 0.24], [1.5, 2.6, -0.55], WOOD, "Wood")
    m.cyl("StaffRing", 0.14, 1.05, [1.5, 5.4, -0.55], GOLD, "Metal", rot=[90, 0, 0])
    m.box("StaffClawL", [0.14, 0.6, 0.14], [1.15, 5.55, -0.55], GOLD, "Metal", rot=[0, 0, 25])
    m.box("StaffClawR", [0.14, 0.6, 0.14], [1.85, 5.55, -0.55], GOLD, "Metal", rot=[0, 0, -25])
    m.ball("StaffOrb", 0.8, [1.5, 5.45, -0.55], orb, "Neon")
    m.on = "Left Arm"
    m.ball("HandOrb", 0.55, [-1.5, 1.25, -0.25], orb, "Neon", alpha=0.25)
    return m.build()


def ranger():
    tunic, tunic_dark = [64, 122, 62], [36, 78, 42]
    m = r6(6.9, tunic, tunic, [96, 72, 46], "Fabric")
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.box("Boot" + side, [1.06, 0.8, 1.12], [x, 0.4, -0.03], LEATHER_DARK, "Fabric")
    m.on = "Torso"
    m.box("TunicSkirt", [2.08, 0.5, 1.08], [0, 1.85, 0], tunic, "Fabric")
    m.box("Belt", [2.08, 0.25, 1.08], [0, 2.15, 0], LEATHER, "Fabric")
    m.box("Strap", [0.3, 2.6, 1.06], [0, 3.0, 0], LEATHER, "Fabric", rot=[0, 0, -38])
    m.box("Cape", [1.9, 2.8, 0.1], [0, 2.75, 0.68], "team", "Fabric", rot=[7, 0, 0])
    m.cyl("Quiver", 2.3, 0.7, [0.55, 3.4, 0.82], LEATHER, "Fabric", rot=[0, 0, -18])
    for i, dx in enumerate((-0.12, 0.08, 0.26)):
        m.box("Arrow%d" % i, [0.08, 0.9, 0.08], [0.98 + dx, 4.8, 0.82 + dx * 0.4], WOOD, "Wood", rot=[0, 0, -18])
        m.box("Fletch%d" % i, [0.06, 0.4, 0.26], [1.12 + dx, 5.2, 0.82 + dx * 0.4], "team", "Fabric", rot=[0, 0, -18])
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.box("Bracer" + side, [1.08, 0.7, 1.08], [x, 2.3, 0], LEATHER, "Fabric")
        m.box("Hand" + side, [0.8, 0.4, 0.8], [x, 1.8, 0], SKIN)
    face(m)
    m.cyl("Hood", 1.45, 1.6, [0, 4.62, 0.2], tunic_dark, "Fabric")
    m.wedge("HoodPeak", [1.1, 0.7, 1.0], [0, 5.6, 0.55], tunic_dark, "Fabric")
    m.box("HoodRim", [1.62, 0.2, 0.5], [0, 5.25, -0.4], tunic_dark, "Fabric")
    m.on = "Left Arm"  # bow, string toward the archer
    a = math.radians(20)
    m.box("BowGrip", [0.22, 0.8, 0.28], [-1.5, 2.2, -0.7], LEATHER_DARK)
    m.box("BowUpper", [0.18, 1.9, 0.2], [-1.5, 2.6 + 0.95 * math.cos(a), -0.7 + 0.95 * math.sin(a)], WOOD, "Wood", rot=[20, 0, 0])
    m.box("BowLower", [0.18, 1.9, 0.2], [-1.5, 1.8 - 0.95 * math.cos(a), -0.7 + 0.95 * math.sin(a)], WOOD, "Wood", rot=[-20, 0, 0])
    m.box("BowString", [0.04, 3.6, 0.04], [-1.5, 2.2, -0.7 + 1.9 * math.sin(a)], WHITE)
    return m.build()


def guardian():
    gold, bronze, bone = [212, 170, 72], [150, 108, 48], [236, 226, 200]
    m = r6(7.7, gold, bronze, bronze, "Metal")
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.box("Greave" + side, [1.2, 1.3, 1.2], [x, 0.95, 0], bronze, "Metal")
        m.box("Boot" + side, [1.3, 0.6, 1.4], [x, 0.3, -0.06], gold, "Metal")
    m.on = "Torso"  # heavy breastplate makes him look bigger than the R6 body underneath
    m.box("Breastplate", [2.5, 2.2, 1.5], [0, 3.1, 0], gold, "Metal")
    m.box("Chest", [2.1, 1.1, 0.1], [0, 3.55, -0.77], bronze, "Metal")
    m.box("Emblem", [0.85, 0.85, 0.1], [0, 3.4, -0.84], "team", "Neon", rot=[0, 0, 45])
    m.box("Belt", [2.56, 0.35, 1.56], [0, 2.15, 0], bronze, "Metal")
    m.box("Fauld", [1.6, 0.7, 0.12], [0, 1.8, -0.76], "team", "Fabric")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.ball("Pauldron" + side, 1.75, [x * 1.1, 4.1, 0], gold, "Metal")
        m.wedge("Spike" + side, [0.3, 0.7, 0.5], [x * 1.16, 5.1, 0], bone, rot=[0, 90 if x > 0 else -90, 0])
        m.box("Gauntlet" + side, [1.3, 0.7, 1.3], [x, 2.3, 0], gold, "Metal")
    m.on = "Head"
    m.box("Helmet", [1.7, 1.55, 1.7], [0, 4.6, 0], bronze, "Metal")
    m.box("HelmetCrest", [0.3, 0.35, 1.8], [0, 5.52, 0], gold, "Metal")
    m.box("VisorSlit", [1.2, 0.16, 0.08], [0, 4.7, -0.86], "team", "Neon")
    m.box("HornL", [0.3, 1.2, 0.3], [-1.05, 5.45, 0], bone, rot=[0, 0, 30])
    m.box("HornR", [0.3, 1.2, 0.3], [1.05, 5.45, 0], bone, rot=[0, 0, -30])
    m.on = "Left Arm"  # tower shield
    m.box("Shield", [0.4, 3.6, 2.4], [-2.35, 3.0, -0.5], "team", "Metal", rot=[0, -10, 0])
    m.box("ShieldFrameTop", [0.44, 0.25, 2.5], [-2.35, 4.85, -0.5], gold, "Metal", rot=[0, -10, 0])
    m.box("ShieldFrameBot", [0.44, 0.25, 2.5], [-2.35, 1.15, -0.5], gold, "Metal", rot=[0, -10, 0])
    m.ball("ShieldBoss", 0.9, [-2.58, 3.0, -0.55], gold, "Metal")
    m.on = "Right Arm"  # war hammer
    m.box("HammerHandle", [0.3, 3.4, 0.3], [1.5, 2.4, -0.75], WOOD, "Wood")
    m.box("HammerHead", [0.9, 1.0, 1.8], [1.5, 4.1, -0.75], STEEL_DARK, "Metal")
    m.box("HammerBand", [0.95, 1.05, 0.3], [1.5, 4.1, -0.75], gold, "Metal")
    return m.build()


def assassin():
    cloth, dark = [48, 48, 60], [26, 26, 32]
    m = r6(6.9, cloth, cloth, cloth, "Fabric")
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.box("Wrap" + side, [1.04, 0.25, 1.04], [x, 1.2, 0], "teamDark", "Fabric")
        m.box("Boot" + side, [1.06, 0.6, 1.1], [x, 0.3, -0.03], dark, "Fabric")
    m.on = "Torso"
    m.box("Vest", [1.7, 1.6, 0.08], [0, 3.1, -0.53], dark, "Fabric")
    m.box("Belt", [2.06, 0.25, 1.06], [0, 2.1, 0], dark, "Fabric")
    m.box("PouchL", [0.4, 0.4, 0.3], [-0.6, 2.0, -0.6], LEATHER)
    m.box("PouchR", [0.4, 0.4, 0.3], [0.6, 2.0, -0.6], LEATHER)
    m.box("Scarf", [1.6, 0.4, 1.15], [0, 3.95, 0], "team", "Fabric")
    m.box("ScarfTail", [0.4, 1.6, 0.08], [0.45, 3.3, 0.62], "team", "Fabric", rot=[18, 0, -8])
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]  # reverse-grip daggers pointing forward
        m.box("Bracer" + side, [1.06, 0.6, 1.06], [x, 2.3, 0], dark, "Fabric")
        m.box("Grip" + side, [0.2, 0.2, 0.6], [x, 1.95, -0.35], LEATHER_DARK)
        m.box("Guard" + side, [0.55, 0.15, 0.15], [x, 1.95, -0.7], STEEL_DARK, "Metal")
        m.box("Dagger" + side, [0.22, 0.08, 1.6], [x, 1.95, -1.55], BLADE, "Metal")
    m.on = "Head"
    m.cyl("Hood", 1.45, 1.5, [0, 4.62, 0.15], dark, "Fabric")
    m.wedge("HoodPeak", [1.0, 0.75, 1.0], [0, 5.65, 0.45], dark, "Fabric")
    m.box("Mask", [1.3, 0.6, 0.08], [0, 4.25, -0.66], BLACK, "Fabric")
    m.box("EyeL", [0.3, 0.1, 0.05], [-0.28, 4.7, -0.66], "team", "Neon")
    m.box("EyeR", [0.3, 0.1, 0.05], [0.28, 4.7, -0.66], "team", "Neon")
    return m.build()


# --------------------------------------------------------------------------- minions
def melee_minion():
    m = M("Body", bar_top=4.0)
    for side, x in (("L", -0.32), ("R", 0.32)):
        m.box("Leg" + side, [0.5, 0.9, 0.55], [x, 0.45, 0], "teamDark", "SmoothPlastic")
    m.box("Body", [1.4, 1.2, 0.95], [0, 1.5, 0], "team", "SmoothPlastic")
    m.box("Belt", [1.44, 0.2, 1.0], [0, 1.0, 0], LEATHER)
    m.box("Chest", [1.0, 0.7, 0.08], [0, 1.6, -0.5], STEEL, "Metal")
    m.ball("Head", 1.05, [0, 2.55, 0], STEEL, "Metal")
    m.box("Visor", [0.7, 0.14, 0.1], [0, 2.55, -0.48], "teamLight", "Neon")
    m.box("Crest", [0.15, 0.4, 0.8], [0, 3.15, 0.05], "team", "Fabric")
    for side, x in (("L", -0.88), ("R", 0.88)):
        m.box("Arm" + side, [0.4, 1.0, 0.45], [x, 1.55, 0], "team")
    m.box("Sword", [0.16, 0.1, 1.5], [0.88, 1.1, -0.85], BLADE, "Metal")
    m.box("SwordGuard", [0.4, 0.1, 0.12], [0.88, 1.1, -0.15], GOLD, "Metal")
    m.cyl("Shield", 0.16, 1.25, [-1.15, 1.6, -0.1], "team", "Metal", rot=[0, 0, 90])
    m.ball("ShieldBoss", 0.4, [-1.25, 1.6, -0.1], STEEL, "Metal")
    return m.build()


def caster_minion():
    orb = "teamLight"
    m = M("Body", bar_top=3.8)
    m.cyl("RobeLow", 0.8, 1.7, [0, 0.4, 0], "teamDark", "Fabric")
    m.cyl("Body", 0.9, 1.35, [0, 1.2, 0], "team", "Fabric")
    m.cyl("Collar", 0.2, 1.1, [0, 1.72, 0], GOLD, "Metal")
    m.ball("Head", 0.95, [0, 2.2, 0], "teamDark", "Fabric")
    m.wedge("Hood", [0.8, 0.6, 0.7], [0, 2.8, 0.15], "teamDark", "Fabric")
    m.box("EyeL", [0.16, 0.12, 0.05], [-0.18, 2.25, -0.46], orb, "Neon")
    m.box("EyeR", [0.16, 0.12, 0.05], [0.18, 2.25, -0.46], orb, "Neon")
    m.box("Wand", [0.12, 1.6, 0.12], [0.75, 1.4, -0.35], WOOD, "Wood")
    m.ball("Orb", 0.55, [0.75, 2.35, -0.35], orb, "Neon")
    m.ball("OrbGlow", 0.95, [0.75, 2.35, -0.35], orb, "Neon", alpha=0.7)
    return m.build()


def siege_minion():
    m = M("Body", bar_top=4.6)
    m.box("Body", [2.4, 0.7, 3.6], [0, 1.2, 0], WOOD, "Wood")
    m.box("Deck", [2.2, 0.2, 3.4], [0, 1.65, 0], [100, 68, 40], "Wood")
    for side, x in (("L", -1.26), ("R", 1.26)):
        m.box("Armor" + side, [0.1, 0.65, 3.2], [x, 1.25, 0], "team", "Metal")
        for end, z in (("F", -1.15), ("B", 1.15)):
            m.cyl("Wheel" + side + end, 0.4, 1.5, [x * 1.13, 0.75, z], [64, 46, 30], "Wood", rot=[0, 0, 90])
            m.cyl("Hub" + side + end, 0.5, 0.45, [x * 1.13, 0.75, z], STEEL_DARK, "Metal", rot=[0, 0, 90])
    m.box("Mount", [1.2, 0.6, 1.2], [0, 2.0, 0.3], STEEL_DARK, "Metal")
    m.cyl("Barrel", 2.8, 0.85, [0, 2.45, -0.9], [60, 62, 70], "Metal", rot=[90, 0, 0])
    m.cyl("Muzzle", 0.35, 1.1, [0, 2.45, -2.25], [60, 62, 70], "Metal", rot=[90, 0, 0])
    m.cyl("BarrelBand", 0.25, 1.0, [0, 2.45, -0.6], "team", "Metal", rot=[90, 0, 0])
    m.ball("Breech", 1.05, [0, 2.45, 0.55], [60, 62, 70], "Metal")
    m.box("FlagPole", [0.12, 2.4, 0.12], [0.95, 2.85, 1.55], WOOD, "Wood")
    m.box("Flag", [0.05, 0.75, 1.0], [0.95, 3.6, 2.05], "team", "Fabric")
    return m.build()


# --------------------------------------------------------------------------- structures
def tower():
    stone, stone_dark, stone_light = [128, 128, 138], [92, 92, 102], [158, 158, 166]
    m = M("Base", bar_top=21, fire="Crystal")
    m.box("Base", [9, 1.5, 9], [0, 0.75, 0], stone_dark, "Cobblestone", collide=True)
    m.box("Step", [7.4, 1.0, 7.4], [0, 2.0, 0], stone, "Cobblestone", collide=True)
    m.cyl("Shaft", 10.5, 6, [0, 7.75, 0], stone, "Slate", collide=True)
    m.cyl("BandLow", 0.6, 6.4, [0, 3.9, 0], stone_light, "Slate")
    m.cyl("BandHigh", 0.6, 6.4, [0, 10.4, 0], stone_light, "Slate")
    for i, (x, z, ry) in enumerate(((0, -3.05, 0), (0, 3.05, 180), (3.05, 0, 90), (-3.05, 0, -90))):
        m.box("Banner%d" % i, [1.7, 4.2, 0.1], [x, 7.5, z], "team", "Fabric", rot=[0, ry, 0])
        dx, dz = (0, -0.06) if i == 0 else (0, 0.06) if i == 1 else (0.06, 0) if i == 2 else (-0.06, 0)
        m.box("BannerRod%d" % i, [2.0, 0.18, 0.18], [x + dx, 9.65, z + dz], GOLD, "Metal", rot=[0, ry, 0])
    m.cyl("Corbel", 0.8, 7.0, [0, 12.8, 0], stone_dark, "Slate")
    m.cyl("Platform", 0.8, 8.2, [0, 13.6, 0], stone, "Slate")
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        m.box("Merlon%d" % i, [1.5, 1.3, 1.1], [3.55 * math.sin(a), 14.65, 3.55 * math.cos(a)], stone_light, "Slate", rot=[0, i * 45 + 22.5, 0])
    m.cyl("Pedestal", 1.2, 1.7, [0, 14.6, 0], GOLD, "Metal")
    m.cyl("Bowl", 0.4, 2.6, [0, 15.35, 0], GOLD, "Metal")
    m.box("Crystal", [1.9, 1.9, 1.9], [0, 17.4, 0], "team", "Neon", rot=[45, 0, 35])
    m.cyl("Halo", 0.12, 4.2, [0, 17.4, 0], "teamLight", "Neon", rot=[18, 0, 8], alpha=0.45)
    return m.build()


def nexus():
    marble, marble_dark = [214, 214, 222], [170, 170, 182]
    m = M("Base", bar_top=15.5)
    m.box("Base", [16, 1.5, 16], [0, 0.75, 0], marble_dark, "Marble", collide=True)
    m.box("Step", [12.5, 1.2, 12.5], [0, 2.1, 0], marble, "Marble", collide=True)
    m.box("Dais", [9, 1.0, 9], [0, 3.2, 0], marble_dark, "Marble", collide=True)
    m.box("Inlay", [9.1, 0.25, 9.1], [0, 3.6, 0], "team", "Neon")
    for i, (x, z) in enumerate(((-6.4, -6.4), (6.4, -6.4), (-6.4, 6.4), (6.4, 6.4))):
        m.box("Pillar%d" % i, [1.2, 6.0, 1.2], [x, 4.5, z], marble, "Marble", collide=True)
        m.box("PillarCap%d" % i, [1.6, 0.4, 1.6], [x, 7.7, z], GOLD, "Metal")
        m.ball("PillarGem%d" % i, 1.0, [x, 8.4, z], "team", "Neon")
    m.cyl("Pedestal", 1.6, 3.2, [0, 4.5, 0], GOLD, "Metal")
    m.box("Core", [5, 5, 5], [0, 9.0, 0], "team", "Neon", rot=[45, 45, 0])
    m.box("CoreShell", [6.2, 6.2, 6.2], [0, 9.0, 0], "teamLight", "Glass", rot=[45, 45, 0], alpha=0.75)
    m.cyl("RingA", 0.2, 11, [0, 9.0, 0], "teamLight", "Neon", rot=[22, 0, 10], alpha=0.55)
    m.cyl("RingB", 0.2, 9, [0, 9.0, 0], "teamLight", "Neon", rot=[-18, 0, -22], alpha=0.55)
    return m.build()


def tree():
    m = M("Trunk", bar_top=0)
    m.box("Trunk", [1.4, 5.2, 1.4], [0, 2.6, 0], [104, 70, 42], "Wood", collide=True)
    m.box("Root1", [0.6, 0.6, 2.4], [0, 0.3, 0], [96, 64, 38], "Wood")
    m.box("Root2", [2.4, 0.6, 0.6], [0, 0.3, 0], [96, 64, 38], "Wood")
    m.box("Branch", [0.5, 2.0, 0.5], [0.8, 5.2, 0], [104, 70, 42], "Wood", rot=[0, 0, -35])
    m.ball("LeavesMain", 6.2, [0, 6.4, 0], [46, 112, 50], "Grass")
    m.ball("LeavesSide", 4.6, [1.9, 6.0, 1.0], [52, 124, 54], "Grass")
    m.ball("LeavesBack", 4.2, [-1.6, 7.2, -0.9], [40, 100, 46], "Grass")
    m.ball("LeavesTop", 3.4, [0.2, 9.0, 0.3], [58, 132, 58], "Grass")
    return m.build()


SPECS = {
    "Hero_Knight": knight(),
    "Hero_Mage": mage(),
    "Hero_Ranger": ranger(),
    "Hero_Guardian": guardian(),
    "Hero_Assassin": assassin(),
    "Minion_melee": melee_minion(),
    "Minion_caster": caster_minion(),
    "Minion_siege": siege_minion(),
    "Tower": tower(),
    "Nexus": nexus(),
    "Tree": tree(),
}

if __name__ == "__main__":
    with open(OUT, "w") as f:
        json.dump(SPECS, f, separators=(",", ":"))
        f.write("\n")
    here = os.path.dirname(__file__)
    template = os.path.join(here, "model-viewer.template.html")
    if os.path.exists(template):
        with open(template) as f:
            html = f.read().replace("/*SPECS*/null", json.dumps(SPECS, separators=(",", ":")))
        with open(os.path.join(here, "model-viewer.html"), "w") as f:
            f.write("<!doctype html>\n<meta charset=\"utf-8\">\n<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n" + html)
    total = sum(len(s["parts"]) for s in SPECS.values())
    print("wrote %s: %d models, %d parts" % (os.path.normpath(OUT), len(SPECS), total))
