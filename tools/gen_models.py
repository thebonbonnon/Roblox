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
  skin      R6 heroes only: part of the bot's visible rounded body. Players keep their own
            avatar body, so skin parts are skipped when gear is put on a player.

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

    def add(self, name, shape, size, pos, color, material="SmoothPlastic", rot=None, alpha=None, collide=None, attach=None, skin=False):
        p = {"name": name, "shape": shape, "size": [round(v, 3) for v in size],
             "pos": [round(v, 3) for v in pos], "color": color, "material": material}
        if rot:
            p["rot"] = [round(v, 2) for v in rot]
        if alpha:
            p["alpha"] = alpha
        if collide:
            p["collide"] = True
        if skin:
            p["skin"] = True
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


# --------------------------------------------------------------------------- smooth shapes
def capsule(m, name, length, d, pos, color, material="SmoothPlastic", skin=False):
    """Vertical pill: a cylinder with a ball on each end. `length` is the total height."""
    x, y, z = pos
    h = max(length - d, 0.05)
    m.cyl(name, h, d, [x, y, z], color, material, skin=skin)
    m.ball(name + "Top", d, [x, y + h / 2, z], color, material, skin=skin)
    m.ball(name + "Bottom", d, [x, y - h / 2, z], color, material, skin=skin)


def stadium(m, name, w, h, d, pos, color, material="SmoothPlastic", skin=False, rot=None):
    """A block whose left and right sides are rounded (half-cylinders). w along X, d along Z."""
    x, y, z = pos
    core = max(w - d, 0.05)
    m.box(name, [core, h, d], [x, y, z], color, material, skin=skin, rot=rot)
    m.cyl(name + "L", h, d, [x - core / 2, y, z], color, material, skin=skin)
    m.cyl(name + "R", h, d, [x + core / 2, y, z], color, material, skin=skin)


def disc(m, name, thickness, d, pos, color, material="SmoothPlastic", axis="x", **kw):
    """A flat round plate facing along `axis` (x: shields on the side, z: facing forward)."""
    rot = kw.pop("rot", None) or ([0, 0, 90] if axis == "x" else [90, 0, 0] if axis == "z" else None)
    m.cyl(name, thickness, d, pos, color, material, rot=rot, **kw)


# --------------------------------------------------------------------------- R6 rig
# Every hero is a standard R6 rig: HumanoidRootPart + six body parts at standard R6 sizes, so
# Roblox's R6 animations line up and gear fits any player's R6 avatar. The six body parts are
# invisible "bones"; the visible body is made of rounded "skin" parts welded to them.
R6_LIMBS = ("Torso", "Head", "Left Arm", "Right Arm", "Left Leg", "Right Leg")
R6_BODY = ("HumanoidRootPart",) + R6_LIMBS
BONE = [163, 162, 165]
ARM = {"L": "Left Arm", "R": "Right Arm"}
LEG = {"L": "Left Leg", "R": "Right Leg"}


def r6(bar_top, torso, arms, legs, mats=("SmoothPlastic", "SmoothPlastic", "SmoothPlastic"),
       hands=SKIN, skin=SKIN, chest_w=2.0):
    m = M("HumanoidRootPart", bar_top=bar_top, rig="R6")
    m.box("HumanoidRootPart", [2, 2, 1], [0, 3, 0], BONE, alpha=1)
    m.box("Torso", [2, 2, 1], [0, 3, 0], BONE, alpha=1)
    m.add("Head", "head", [2, 1, 1], [0, 4.5, 0], skin)
    m.box("Left Arm", [1, 2, 1], [-1.5, 3, 0], BONE, alpha=1)
    m.box("Right Arm", [1, 2, 1], [1.5, 3, 0], BONE, alpha=1)
    m.box("Left Leg", [1, 2, 1], [-0.5, 1, 0], BONE, alpha=1)
    m.box("Right Leg", [1, 2, 1], [0.5, 1, 0], BONE, alpha=1)
    tm, am, lm = mats
    m.on = "Torso"
    stadium(m, "Chest", chest_w, 1.9, 1.0, [0, 3.05, 0], torso, tm, skin=True)
    stadium(m, "Hips", chest_w - 0.1, 0.45, 0.95, [0, 2.1, 0], legs, lm, skin=True)
    m.cyl("Neck", 0.4, 0.6, [0, 4.1, 0], skin, skin=True)
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        capsule(m, "Arm" + side, 2.0, 0.95, [x, 3.0, 0], arms, am, skin=True)
        m.ball("Hand" + side, 0.78, [x, 1.95, 0], hands, skin=True)
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        capsule(m, "Leg" + side, 2.0, 0.95, [x, 1.0, 0], legs, lm, skin=True)
    return m


def face(m, y=4.6, z=-0.62, eye=BLACK):
    m.on = "Head"
    m.ball("EyeL", 0.2, [-0.25, y, z], eye)
    m.ball("EyeR", 0.2, [0.25, y, z], eye)


def boots(m, color, material="SmoothPlastic", d=1.08, h=0.62):
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.cyl("Boot" + side, h, d, [x, h / 2, -0.03], color, material)
        m.ball("Toe" + side, d * 0.8, [x, 0.3, -0.38], color, material)


# --------------------------------------------------------------------------- heroes
def knight():
    m = r6(7.3, STEEL, STEEL, STEEL, ("Metal", "Metal", "Metal"), hands=STEEL_DARK)
    boots(m, STEEL_DARK, "Metal")
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.ball("Knee" + side, 0.55, [x, 1.2, -0.42], STEEL_DARK, "Metal")
    m.on = "Torso"
    m.box("Tabard", [1.25, 1.75, 0.08], [0, 2.9, -0.53], "team", "Fabric")
    m.box("TabardCross", [0.28, 1.1, 0.04], [0, 3.1, -0.59], WHITE, "Fabric")
    m.box("TabardCrossBar", [0.85, 0.28, 0.04], [0, 3.3, -0.59], WHITE, "Fabric")
    stadium(m, "Belt", 2.1, 0.3, 1.1, [0, 2.2, 0], LEATHER, "Fabric")
    m.ball("Buckle", 0.36, [0, 2.2, -0.54], GOLD, "Metal")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.ball("Pauldron" + side, 1.4, [x * 1.02, 3.8, 0], STEEL, "Metal")
        m.cyl("PauldronTrim" + side, 0.16, 1.42, [x * 1.02, 3.55, 0], "team", "Metal")
        m.cyl("Gauntlet" + side, 0.55, 1.08, [x, 2.25, 0], STEEL_DARK, "Metal")
    m.on = "Head"
    m.cyl("Helmet", 1.3, 1.48, [0, 4.6, 0], STEEL, "Metal")
    m.ball("HelmetDome", 1.48, [0, 5.2, 0], STEEL, "Metal")
    m.box("Visor", [1.0, 0.13, 0.08], [0, 4.62, -0.73], BLACK)
    m.box("VisorRidge", [0.13, 0.85, 0.1], [0, 4.45, -0.73], STEEL_DARK, "Metal")
    for i, (z, y) in enumerate(((-0.35, 5.95), (0.05, 6.1), (0.45, 6.0), (0.8, 5.75))):
        m.ball("Plume%d" % i, 0.55, [0, y, z], "team", "Fabric")
    m.on = "Right Arm"  # sword held forward
    m.cyl("SwordGrip", 0.8, 0.24, [1.5, 2.0, -0.45], LEATHER_DARK, rot=[90, 0, 0])
    m.ball("SwordPommel", 0.36, [1.5, 2.0, -0.02], GOLD, "Metal")
    m.box("SwordGuard", [0.95, 0.18, 0.2], [1.5, 2.0, -0.92], GOLD, "Metal")
    m.ball("SwordGuardL", 0.26, [1.03, 2.0, -0.92], GOLD, "Metal")
    m.ball("SwordGuardR", 0.26, [1.97, 2.0, -0.92], GOLD, "Metal")
    m.box("SwordBlade", [0.32, 0.1, 3.2], [1.5, 2.0, -2.6], BLADE, "Metal")
    m.wedge("SwordTip", [0.1, 0.32, 0.45], [1.5, 2.0, -4.42], BLADE, "Metal", rot=[0, 0, 90])
    m.on = "Left Arm"  # kite shield
    m.box("Shield", [0.25, 2.0, 1.7], [-2.15, 3.15, -0.1], "team", "Metal")
    disc(m, "ShieldTop", 0.25, 1.7, [-2.15, 4.15, -0.1], "team", "Metal")
    m.wedge("ShieldPointA", [0.25, 0.8, 0.85], [-2.15, 1.75, -0.525], "team", "Metal", rot=[0, 0, 180])
    m.wedge("ShieldPointB", [0.25, 0.8, 0.85], [-2.15, 1.75, 0.325], "team", "Metal", rot=[180, 0, 0])
    m.box("ShieldBandV", [0.28, 2.4, 0.22], [-2.17, 3.15, -0.1], WHITE, "Metal")
    m.box("ShieldBandH", [0.28, 0.22, 1.5], [-2.17, 3.45, -0.1], WHITE, "Metal")
    disc(m, "ShieldBoss", 0.2, 0.6, [-2.31, 3.45, -0.1], GOLD, "Metal")
    return m.build()


def mage():
    robe, robe_dark, robe_light = [104, 58, 176], [70, 36, 128], [168, 120, 232]
    orb = [196, 130, 255]
    m = r6(7.9, robe, robe, robe_dark, ("Fabric", "Fabric", "Fabric"))
    m.on = "Torso"  # long robe hangs from the waist over the legs
    stadium(m, "Skirt", 2.2, 1.9, 1.3, [0, 1.15, 0], robe, "Fabric")
    stadium(m, "SkirtFlare", 2.5, 0.6, 1.6, [0, 0.4, 0], robe, "Fabric")
    stadium(m, "Hem", 2.6, 0.18, 1.7, [0, 0.1, 0], "team", "Fabric")
    m.box("Sash", [0.36, 2.6, 1.06], [0, 3.0, 0], "team", "Fabric", rot=[0, 0, 35])
    stadium(m, "Belt", 2.1, 0.26, 1.1, [0, 2.15, 0], GOLD, "Metal")
    stadium(m, "Collar", 2.0, 0.3, 1.15, [0, 3.95, 0], robe_light, "Fabric")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.cyl("Cuff" + side, 0.55, 1.22, [x, 2.3, 0], robe_light, "Fabric")
    face(m)
    m.ball("Beard", 1.0, [0, 4.05, -0.48], WHITE, "Fabric")
    m.ball("BeardTip", 0.62, [0, 3.55, -0.55], WHITE, "Fabric")
    m.cyl("HatBrim", 0.16, 2.8, [0, 5.15, 0], robe_dark, "Fabric")
    m.cyl("HatBand", 0.24, 1.66, [0, 5.34, 0], "team", "Fabric")
    m.cyl("HatLow", 0.55, 1.6, [0, 5.5, 0], robe_dark, "Fabric")
    m.cyl("HatMid", 0.6, 1.2, [0.05, 6.05, 0.05], robe_dark, "Fabric", rot=[6, 0, -6])
    m.cyl("HatHigh", 0.55, 0.8, [0.15, 6.55, 0.12], robe_dark, "Fabric", rot=[12, 0, -14])
    m.ball("HatTip", 0.5, [0.22, 6.85, 0.18], robe_dark, "Fabric")
    m.ball("HatStar", 0.42, [0.3, 7.05, 0.22], GOLD, "Neon")
    m.on = "Right Arm"
    m.cyl("Staff", 5.4, 0.24, [1.5, 2.6, -0.55], WOOD, "Wood")
    m.cyl("StaffRing", 0.14, 1.05, [1.5, 5.4, -0.55], GOLD, "Metal", rot=[90, 0, 0])
    m.box("StaffClawL", [0.14, 0.6, 0.14], [1.15, 5.55, -0.55], GOLD, "Metal", rot=[0, 0, 25])
    m.box("StaffClawR", [0.14, 0.6, 0.14], [1.85, 5.55, -0.55], GOLD, "Metal", rot=[0, 0, -25])
    m.ball("StaffOrb", 0.8, [1.5, 5.45, -0.55], orb, "Neon")
    m.on = "Left Arm"
    m.ball("HandOrb", 0.55, [-1.5, 1.4, -0.3], orb, "Neon", alpha=0.25)
    return m.build()


def ranger():
    tunic, tunic_dark, pants = [64, 122, 62], [36, 78, 42], [96, 72, 46]
    m = r6(6.9, tunic, tunic, pants, ("Fabric", "Fabric", "Fabric"))
    boots(m, LEATHER_DARK, "Fabric", h=0.8)
    m.on = "Torso"
    stadium(m, "TunicSkirt", 2.1, 0.55, 1.1, [0, 1.9, 0], tunic, "Fabric")
    stadium(m, "Belt", 2.12, 0.25, 1.12, [0, 2.2, 0], LEATHER, "Fabric")
    m.box("Strap", [0.3, 2.6, 1.08], [0, 3.0, 0], LEATHER, "Fabric", rot=[0, 0, -38])
    m.box("Cape", [1.8, 2.7, 0.1], [0, 2.8, 0.66], "team", "Fabric", rot=[7, 0, 0])
    m.cyl("Quiver", 2.3, 0.7, [0.55, 3.4, 0.82], LEATHER, "Fabric", rot=[0, 0, -18])
    for i, dx in enumerate((-0.12, 0.08, 0.26)):
        m.cyl("Arrow%d" % i, 0.9, 0.08, [0.98 + dx, 4.8, 0.82 + dx * 0.4], WOOD, "Wood", rot=[0, 0, -18])
        m.box("Fletch%d" % i, [0.06, 0.4, 0.26], [1.12 + dx, 5.2, 0.82 + dx * 0.4], "team", "Fabric", rot=[0, 0, -18])
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.cyl("Bracer" + side, 0.7, 1.08, [x, 2.35, 0], LEATHER, "Fabric")
    face(m)
    m.cyl("Hood", 1.45, 1.6, [0, 4.62, 0.2], tunic_dark, "Fabric")
    m.ball("HoodBack", 1.6, [0, 5.25, 0.25], tunic_dark, "Fabric")
    m.ball("HoodPeak", 0.8, [0, 5.75, 0.6], tunic_dark, "Fabric")
    m.on = "Left Arm"  # bow, string toward the archer
    a = math.radians(20)
    m.cyl("BowGrip", 0.8, 0.26, [-1.5, 2.2, -0.7], LEATHER_DARK)
    m.cyl("BowUpper", 1.9, 0.18, [-1.5, 2.6 + 0.95 * math.cos(a), -0.7 + 0.95 * math.sin(a)], WOOD, "Wood", rot=[20, 0, 0])
    m.cyl("BowLower", 1.9, 0.18, [-1.5, 1.8 - 0.95 * math.cos(a), -0.7 + 0.95 * math.sin(a)], WOOD, "Wood", rot=[-20, 0, 0])
    m.cyl("BowString", 3.6, 0.04, [-1.5, 2.2, -0.7 + 1.9 * math.sin(a)], WHITE)
    return m.build()


def guardian():
    gold, bronze, bone = [212, 170, 72], [150, 108, 48], [236, 226, 200]
    m = r6(7.7, gold, bronze, bronze, ("Metal", "Metal", "Metal"), hands=gold)
    boots(m, gold, "Metal", d=1.32, h=0.65)
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.cyl("Greave" + side, 1.2, 1.22, [x, 1.15, 0], bronze, "Metal")
    m.on = "Torso"  # heavy breastplate makes him look bigger than the R6 body underneath
    stadium(m, "Breastplate", 2.65, 2.2, 1.55, [0, 3.1, 0], gold, "Metal")
    stadium(m, "ChestPlate", 2.0, 1.0, 1.62, [0, 3.55, 0], bronze, "Metal")
    m.box("Emblem", [0.8, 0.8, 0.1], [0, 3.45, -0.84], "team", "Neon", rot=[0, 0, 45])
    stadium(m, "Belt", 2.6, 0.38, 1.6, [0, 2.15, 0], bronze, "Metal")
    m.box("Fauld", [1.5, 0.7, 0.12], [0, 1.8, -0.78], "team", "Fabric")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.ball("Pauldron" + side, 1.8, [x * 1.1, 4.05, 0], gold, "Metal")
        m.cyl("Spike" + side, 0.75, 0.3, [x * 1.18, 5.0, 0], bone, rot=[0, 0, -20 if x > 0 else 20])
        m.ball("SpikeTip" + side, 0.3, [x * 1.18 + (0.13 if x > 0 else -0.13), 5.35, 0], bone)
        m.cyl("Gauntlet" + side, 0.7, 1.3, [x, 2.3, 0], gold, "Metal")
    m.on = "Head"
    m.cyl("Helmet", 1.4, 1.75, [0, 4.55, 0], bronze, "Metal")
    m.ball("HelmetDome", 1.75, [0, 5.2, 0], bronze, "Metal")
    m.cyl("HelmetCrest", 1.75, 0.3, [0, 5.95, 0.05], gold, "Metal", rot=[90, 0, 0])
    m.box("VisorSlit", [1.2, 0.15, 0.08], [0, 4.7, -0.86], "team", "Neon")
    for side, x in (("L", -1), ("R", 1)):
        m.cyl("Horn" + side, 1.0, 0.32, [x * 1.0, 5.55, 0], bone, rot=[0, 0, -30 * x])
        m.ball("HornTip" + side, 0.32, [x * 1.25, 5.98, 0], bone)
    m.on = "Left Arm"  # tower shield with rounded ends
    m.box("Shield", [0.4, 2.6, 2.4], [-2.35, 3.0, -0.5], "team", "Metal", rot=[0, -10, 0])
    disc(m, "ShieldTop", 0.4, 2.4, [-2.35, 4.3, -0.5], "team", "Metal", rot=[0, -10, 90])
    disc(m, "ShieldBottom", 0.4, 2.4, [-2.35, 1.7, -0.5], "team", "Metal", rot=[0, -10, 90])
    m.box("ShieldBand", [0.44, 3.8, 0.35], [-2.36, 3.0, -0.5], gold, "Metal", rot=[0, -10, 0])
    m.ball("ShieldBoss", 0.9, [-2.6, 3.0, -0.55], gold, "Metal")
    m.on = "Right Arm"  # war hammer with a round head
    m.cyl("HammerHandle", 3.4, 0.3, [1.5, 2.4, -0.75], WOOD, "Wood")
    m.cyl("HammerHead", 1.8, 1.0, [1.5, 4.1, -0.75], STEEL_DARK, "Metal", rot=[90, 0, 0])
    m.cyl("HammerBand", 0.3, 1.08, [1.5, 4.1, -0.75], gold, "Metal", rot=[90, 0, 0])
    return m.build()


def assassin():
    cloth, dark = [48, 48, 60], [26, 26, 32]
    m = r6(6.9, cloth, cloth, cloth, ("Fabric", "Fabric", "Fabric"), hands=dark, chest_w=1.85)
    boots(m, dark, "Fabric", d=1.02)
    for side, x in (("L", -0.5), ("R", 0.5)):
        m.on = LEG[side]
        m.cyl("Wrap" + side, 0.25, 1.0, [x, 1.2, 0], "teamDark", "Fabric")
    m.on = "Torso"
    m.box("Vest", [1.4, 1.6, 0.08], [0, 3.1, -0.52], dark, "Fabric")
    stadium(m, "Belt", 1.95, 0.25, 1.06, [0, 2.15, 0], dark, "Fabric")
    m.ball("PouchL", 0.45, [-0.6, 2.05, -0.5], LEATHER)
    m.ball("PouchR", 0.45, [0.6, 2.05, -0.5], LEATHER)
    stadium(m, "Scarf", 1.6, 0.42, 1.18, [0, 3.95, 0], "team", "Fabric")
    m.box("ScarfTail", [0.4, 1.6, 0.08], [0.45, 3.3, 0.64], "team", "Fabric", rot=[18, 0, -8])
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]  # reverse-grip daggers pointing forward
        m.cyl("Bracer" + side, 0.6, 1.04, [x, 2.35, 0], dark, "Fabric")
        m.cyl("Grip" + side, 0.6, 0.2, [x, 1.95, -0.35], LEATHER_DARK, rot=[90, 0, 0])
        m.box("Guard" + side, [0.55, 0.14, 0.14], [x, 1.95, -0.7], STEEL_DARK, "Metal")
        m.box("Dagger" + side, [0.22, 0.08, 1.4], [x, 1.95, -1.45], BLADE, "Metal")
        m.wedge("DaggerTip" + side, [0.08, 0.22, 0.35], [x, 1.95, -2.32], BLADE, "Metal", rot=[0, 0, 90])
    m.on = "Head"
    m.cyl("Hood", 1.45, 1.5, [0, 4.62, 0.15], dark, "Fabric")
    m.ball("HoodBack", 1.5, [0, 5.25, 0.2], dark, "Fabric")
    m.ball("HoodPeak", 0.75, [0, 5.75, 0.5], dark, "Fabric")
    m.box("Mask", [1.25, 0.55, 0.08], [0, 4.25, -0.64], BLACK, "Fabric")
    m.box("EyeL", [0.3, 0.1, 0.05], [-0.26, 4.68, -0.65], "team", "Neon")
    m.box("EyeR", [0.3, 0.1, 0.05], [0.26, 4.68, -0.65], "team", "Neon")
    return m.build()


def gunslinger():
    coat, coat_dark, shirt, pants = [140, 92, 56], [92, 58, 34], [218, 208, 190], [62, 58, 70]
    gun, gun_dark = [74, 76, 86], [40, 42, 48]
    m = r6(7.4, shirt, coat, pants, ("Fabric", "Fabric", "Fabric"), hands=LEATHER_DARK)
    boots(m, LEATHER_DARK, "Fabric", h=0.75)
    m.on = "Torso"  # long duster coat over a light shirt
    stadium(m, "CoatBack", 2.12, 1.95, 0.5, [0, 3.05, 0.3], coat, "Fabric")
    m.box("CoatSideL", [0.38, 1.95, 1.08], [-0.86, 3.05, 0], coat, "Fabric")
    m.box("CoatSideR", [0.38, 1.95, 1.08], [0.86, 3.05, 0], coat, "Fabric")
    m.box("LapelL", [0.2, 1.3, 0.06], [-0.55, 3.35, -0.55], "team", "Fabric", rot=[0, 0, -12])
    m.box("LapelR", [0.2, 1.3, 0.06], [0.55, 3.35, -0.55], "team", "Fabric", rot=[0, 0, 12])
    m.box("CoatTailL", [0.95, 1.5, 0.1], [-0.5, 1.45, 0.55], coat, "Fabric", rot=[6, 0, 0])
    m.box("CoatTailR", [0.95, 1.5, 0.1], [0.5, 1.45, 0.55], coat, "Fabric", rot=[6, 0, 0])
    stadium(m, "Belt", 2.14, 0.28, 1.14, [0, 2.2, 0], LEATHER_DARK, "Fabric")
    m.ball("Buckle", 0.34, [0, 2.2, -0.56], GOLD, "Metal")
    for i, x in enumerate((-0.75, -0.45)):
        m.cyl("Shell%d" % i, 0.3, 0.16, [x, 2.2, -0.56], GOLD, "Metal")
    m.ball("Grenade", 0.42, [0.78, 2.05, -0.45], [70, 90, 60], "Metal")
    for side, x in (("L", -1.5), ("R", 1.5)):
        m.on = ARM[side]
        m.cyl("Cuff" + side, 0.45, 1.1, [x, 2.3, 0], coat_dark, "Fabric")
    face(m)
    stadium(m, "Bandana", 1.3, 0.5, 1.32, [0, 4.2, 0], "team", "Fabric")
    m.cyl("HatBrim", 0.14, 3.0, [0, 5.15, 0], coat_dark, "Fabric")
    m.cyl("HatCrown", 0.8, 1.45, [0, 5.55, 0], coat_dark, "Fabric")
    m.ball("HatTop", 1.45, [0, 5.85, 0], coat_dark, "Fabric")
    m.cyl("HatBand", 0.18, 1.5, [0, 5.28, 0], "team", "Fabric")
    m.on = "Right Arm"  # lever-action carbine pointing forward
    m.box("GunStock", [0.32, 0.5, 1.0], [1.5, 2.15, 0.15], WOOD, "Wood")
    m.box("GunBody", [0.38, 0.5, 1.4], [1.5, 2.2, -0.95], gun, "Metal")
    m.cyl("GunBarrel", 2.4, 0.26, [1.5, 2.35, -2.8], gun_dark, "Metal", rot=[90, 0, 0])
    m.cyl("GunTube", 1.9, 0.2, [1.5, 2.13, -2.5], gun_dark, "Metal", rot=[90, 0, 0])
    m.cyl("GunMuzzle", 0.25, 0.34, [1.5, 2.35, -4.0], "team", "Metal", rot=[90, 0, 0])
    m.cyl("GunScope", 0.9, 0.3, [1.5, 2.62, -1.1], gun_dark, "Metal", rot=[90, 0, 0])
    m.box("GunLever", [0.12, 0.35, 0.5], [1.5, 1.85, -0.75], gun_dark, "Metal")
    return m.build()


# --------------------------------------------------------------------------- minions
def melee_minion():
    m = M("Body", bar_top=4.0)
    for side, x in (("L", -0.32), ("R", 0.32)):
        capsule(m, "Leg" + side, 1.0, 0.5, [x, 0.5, 0], "teamDark")
    m.cyl("Body", 0.75, 1.35, [0, 1.45, 0], "team")
    m.ball("BodyTop", 1.35, [0, 1.82, 0], "team")
    m.ball("BodyBottom", 1.2, [0, 1.15, 0], "team")
    m.cyl("Belt", 0.2, 1.4, [0, 1.12, 0], LEATHER)
    m.ball("Head", 1.05, [0, 2.65, 0], STEEL, "Metal")
    m.box("Visor", [0.7, 0.13, 0.1], [0, 2.65, -0.49], "teamLight", "Neon")
    m.ball("Crest", 0.4, [0, 3.2, 0.05], "team", "Fabric")
    for side, x in (("L", -0.85), ("R", 0.85)):
        capsule(m, "Arm" + side, 0.95, 0.42, [x, 1.55, 0], "team")
    m.box("Sword", [0.15, 0.08, 1.4], [0.85, 1.1, -0.85], BLADE, "Metal")
    m.box("SwordGuard", [0.4, 0.1, 0.12], [0.85, 1.1, -0.15], GOLD, "Metal")
    disc(m, "Shield", 0.16, 1.25, [-1.12, 1.6, -0.1], "team", "Metal")
    disc(m, "ShieldRim", 0.12, 1.36, [-1.08, 1.6, -0.1], STEEL, "Metal")
    m.ball("ShieldBoss", 0.4, [-1.22, 1.6, -0.1], STEEL, "Metal")
    return m.build()


def caster_minion():
    orb = "teamLight"
    m = M("Body", bar_top=3.8)
    m.cyl("RobeLow", 0.8, 1.7, [0, 0.4, 0], "teamDark", "Fabric")
    m.cyl("Body", 0.9, 1.35, [0, 1.2, 0], "team", "Fabric")
    m.cyl("Collar", 0.2, 1.1, [0, 1.72, 0], GOLD, "Metal")
    m.ball("Head", 0.95, [0, 2.2, 0], "teamDark", "Fabric")
    m.ball("Hood", 0.75, [0, 2.6, 0.2], "teamDark", "Fabric")
    m.ball("EyeL", 0.16, [-0.18, 2.25, -0.44], orb, "Neon")
    m.ball("EyeR", 0.16, [0.18, 2.25, -0.44], orb, "Neon")
    m.ball("HandR", 0.32, [0.72, 1.45, -0.3], "teamDark", "Fabric")
    m.cyl("Wand", 1.6, 0.12, [0.75, 1.4, -0.35], WOOD, "Wood")
    m.ball("Orb", 0.55, [0.75, 2.35, -0.35], orb, "Neon")
    m.ball("OrbGlow", 0.95, [0.75, 2.35, -0.35], orb, "Neon", alpha=0.7)
    return m.build()


def siege_minion():
    m = M("Body", bar_top=4.6)
    m.box("Body", [2.4, 0.7, 3.6], [0, 1.2, 0], WOOD, "Wood")
    m.cyl("BumperF", 2.4, 0.7, [0, 1.2, -1.8], [100, 68, 40], "Wood", rot=[0, 0, 90])
    m.cyl("BumperB", 2.4, 0.7, [0, 1.2, 1.8], [100, 68, 40], "Wood", rot=[0, 0, 90])
    m.box("Deck", [2.2, 0.2, 3.4], [0, 1.65, 0], [100, 68, 40], "Wood")
    for side, x in (("L", -1.26), ("R", 1.26)):
        m.box("Armor" + side, [0.1, 0.65, 3.2], [x, 1.25, 0], "team", "Metal")
        for end, z in (("F", -1.15), ("B", 1.15)):
            disc(m, "Wheel" + side + end, 0.4, 1.5, [x * 1.13, 0.75, z], [64, 46, 30], "Wood")
            disc(m, "Hub" + side + end, 0.5, 0.45, [x * 1.13, 0.75, z], STEEL_DARK, "Metal")
    m.cyl("Mount", 1.2, 1.2, [0, 2.0, 0.3], STEEL_DARK, "Metal", rot=[0, 0, 90])
    m.cyl("Barrel", 2.8, 0.85, [0, 2.45, -0.9], [60, 62, 70], "Metal", rot=[90, 0, 0])
    m.cyl("Muzzle", 0.35, 1.1, [0, 2.45, -2.25], [60, 62, 70], "Metal", rot=[90, 0, 0])
    m.cyl("BarrelBand", 0.25, 1.0, [0, 2.45, -0.6], "team", "Metal", rot=[90, 0, 0])
    m.ball("Breech", 1.05, [0, 2.45, 0.55], [60, 62, 70], "Metal")
    m.cyl("FlagPole", 2.4, 0.12, [0.95, 2.85, 1.55], WOOD, "Wood")
    m.box("Flag", [0.05, 0.75, 1.0], [0.95, 3.6, 2.05], "team", "Fabric")
    return m.build()


# --------------------------------------------------------------------------- structures
def tower():
    stone, stone_dark, stone_light = [128, 128, 138], [92, 92, 102], [158, 158, 166]
    m = M("Base", bar_top=21, fire="Crystal")
    m.cyl("Base", 1.5, 10, [0, 0.75, 0], stone_dark, "Cobblestone", collide=True)
    m.cyl("Step", 1.0, 8, [0, 2.0, 0], stone, "Cobblestone", collide=True)
    m.cyl("Shaft", 10.5, 6, [0, 7.75, 0], stone, "Slate", collide=True)
    m.cyl("BandLow", 0.6, 6.4, [0, 3.9, 0], stone_light, "Slate")
    m.cyl("BandHigh", 0.6, 6.4, [0, 10.4, 0], stone_light, "Slate")
    for i, (x, z, ry) in enumerate(((0, -3.02, 0), (0, 3.02, 180), (3.02, 0, 90), (-3.02, 0, -90))):
        m.box("Banner%d" % i, [1.7, 4.2, 0.1], [x, 7.5, z], "team", "Fabric", rot=[0, ry, 0])
        m.cyl("BannerRod%d" % i, 2.0, 0.18, [x * 1.02, 9.65, z * 1.02], GOLD, "Metal", rot=[0, ry, 90])
    m.cyl("Corbel", 0.8, 7.0, [0, 12.8, 0], stone_dark, "Slate")
    m.cyl("Platform", 0.8, 8.2, [0, 13.6, 0], stone, "Slate")
    for i in range(8):
        a = math.radians(i * 45 + 22.5)
        m.cyl("Merlon%d" % i, 1.3, 1.35, [3.5 * math.sin(a), 14.65, 3.5 * math.cos(a)], stone_light, "Slate")
        m.ball("MerlonCap%d" % i, 1.35, [3.5 * math.sin(a), 15.3, 3.5 * math.cos(a)], stone_light, "Slate")
    m.cyl("Pedestal", 1.2, 1.7, [0, 14.6, 0], GOLD, "Metal")
    m.cyl("Bowl", 0.4, 2.6, [0, 15.35, 0], GOLD, "Metal")
    m.box("Crystal", [1.9, 1.9, 1.9], [0, 17.4, 0], "team", "Neon", rot=[45, 0, 35])
    m.box("CrystalB", [1.7, 1.7, 1.7], [0, 17.4, 0], "teamLight", "Neon", rot=[0, 45, 45])
    m.ball("CrystalGlow", 3.4, [0, 17.4, 0], "teamLight", "Neon", alpha=0.8)
    m.cyl("Halo", 0.12, 4.4, [0, 17.4, 0], "teamLight", "Neon", rot=[18, 0, 8], alpha=0.45)
    return m.build()


def nexus():
    marble, marble_dark = [214, 214, 222], [170, 170, 182]
    m = M("Base", bar_top=15.5)
    m.cyl("Base", 1.5, 17, [0, 0.75, 0], marble_dark, "Marble", collide=True)
    m.cyl("Step", 1.2, 13.5, [0, 2.1, 0], marble, "Marble", collide=True)
    m.cyl("Dais", 1.0, 10, [0, 3.2, 0], marble_dark, "Marble", collide=True)
    m.cyl("Inlay", 0.25, 10.1, [0, 3.6, 0], "team", "Neon")
    for i in range(4):
        a = math.radians(45 + i * 90)
        x, z = 6.9 * math.sin(a), 6.9 * math.cos(a)
        m.cyl("Pillar%d" % i, 6.0, 1.3, [x, 4.5, z], marble, "Marble", collide=True)
        m.cyl("PillarCap%d" % i, 0.4, 1.7, [x, 7.7, z], GOLD, "Metal")
        m.ball("PillarGem%d" % i, 1.0, [x, 8.4, z], "team", "Neon")
    m.cyl("Pedestal", 1.6, 3.2, [0, 4.5, 0], GOLD, "Metal")
    m.ball("PedestalTop", 2.4, [0, 5.3, 0], GOLD, "Metal")
    m.box("Core", [4.6, 4.6, 4.6], [0, 9.0, 0], "team", "Neon", rot=[45, 45, 0])
    m.box("CoreB", [4.2, 4.2, 4.2], [0, 9.0, 0], "teamLight", "Neon", rot=[0, 45, 45])
    m.ball("CoreShell", 7.0, [0, 9.0, 0], "teamLight", "Glass", alpha=0.78)
    m.cyl("RingA", 0.2, 11, [0, 9.0, 0], "teamLight", "Neon", rot=[22, 0, 10], alpha=0.55)
    m.cyl("RingB", 0.2, 9, [0, 9.0, 0], "teamLight", "Neon", rot=[-18, 0, -22], alpha=0.55)
    return m.build()


def tree():
    m = M("Trunk", bar_top=0)
    m.cyl("Trunk", 5.2, 1.5, [0, 2.6, 0], [104, 70, 42], "Wood", collide=True)
    m.cyl("Root1", 2.4, 0.55, [0, 0.3, 0], [96, 64, 38], "Wood", rot=[90, 0, 0])
    m.cyl("Root2", 2.4, 0.55, [0, 0.3, 0], [96, 64, 38], "Wood", rot=[0, 0, 90])
    m.cyl("Branch", 2.0, 0.5, [0.8, 5.2, 0], [104, 70, 42], "Wood", rot=[0, 0, -35])
    leaves = [(6.2, 0, 6.4, 0, [46, 112, 50]), (4.6, 1.9, 6.0, 1.0, [52, 124, 54]),
              (4.2, -1.6, 7.2, -0.9, [40, 100, 46]), (4.0, -1.2, 5.8, 1.6, [48, 116, 52]),
              (3.8, 1.4, 7.6, -1.2, [44, 108, 48]), (3.4, 0.2, 9.0, 0.3, [58, 132, 58])]
    for i, (d, x, y, z, c) in enumerate(leaves):
        m.ball("Leaves%d" % i, d, [x, y, z], c, "Grass")
    return m.build()


SPECS = {
    "Hero_Knight": knight(),
    "Hero_Mage": mage(),
    "Hero_Ranger": ranger(),
    "Hero_Guardian": guardian(),
    "Hero_Assassin": assassin(),
    "Hero_Gunslinger": gunslinger(),
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
