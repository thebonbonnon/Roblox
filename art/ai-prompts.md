# AI prompts: picture first, then 3D model

Two steps for each model:

1. **Picture:** paste the **image prompt** into a text-to-image AI (Meshy's image tool, ChatGPT, Gemini, etc.). Make a few, and keep the best one.
2. **3D model:** upload that picture to an **image-to-3D** tool (for example Meshy *Image to 3D*). If it has a text box, paste the **3D prompt**, then use the settings below.

Credits tip: pictures are cheap and 3D models are expensive. Only turn a picture into 3D once you really like it, and do the **Tower** first to test the whole process before the rest.

---

## Settings for the 3D step (if the tool asks)

| Setting | Choose |
|---|---|
| Style | Stylized / cartoon (not realistic) |
| Texture | On |
| Polycount / detail | Low or medium (about 5,000–10,000 triangles). Roblox limits triangles per mesh |
| Symmetry | On for the tower, nexus, minions and tree; Auto for weapons |
| Remove lighting / delight | On, if offered (keeps shadows from being painted into the texture) |
| Export format | FBX or GLB |

---

## Same start for every image prompt

Every image prompt below already includes this, so all models match each other:

> stylized 3D game asset, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, single object, centered, entire object visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text

**Negative prompt** (if there's a box for it, same for all):
```
realistic, photo, blurry, text, logo, watermark, multiple objects, cropped, cut off, background scenery, ground, grass, people, hands
```

---

## Structures and minions (start here)

### Tower
**Image prompt**
```
stylized 3D game asset of a round stone watchtower, wide round stepped stone base, smooth grey stone walls with two pale stone rings, four white cloth banners hanging from gold rods, round battlement top with rounded stone merlons, a glowing white crystal floating in a gold bowl above the top, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, single object, centered, entire object visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text
```
**3D prompt**
```
round stylized stone watchtower with a floating glowing crystal on top, smooth rounded game asset, clean hand-painted texture
```

### Nexus
**Image prompt**
```
stylized 3D game asset of a magic crystal shrine, a large glowing white crystal floating above a round stepped white marble platform, gold pedestal under the crystal, two thin glowing rings orbiting the crystal, four round marble pillars around the edge with gold caps and small glowing orbs, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, single object, centered, entire object visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text
```
**3D prompt**
```
round marble shrine with a big floating glowing crystal and four pillars, smooth stylized game asset, clean hand-painted texture
```

### Melee minion
**Image prompt**
```
stylized 3D game asset of a small chubby toy soldier robot, round body, round steel helmet with a glowing visor slit and a small crest, short sword in the right hand, round shield on the left arm, standing in a neutral pose, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, white and steel colors, single character, centered, full body visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text
```
**3D prompt**
```
small chubby armored toy soldier with sword and round shield, smooth stylized game character, clean hand-painted texture
```

### Caster minion
**Image prompt**
```
stylized 3D game asset of a small hooded spellcaster creature in a layered round robe, gold collar, dark hood with two glowing eyes, holding a short wooden wand topped with a glowing white orb, standing in a neutral pose, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, white and grey robe, single character, centered, full body visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text
```
**3D prompt**
```
small hooded robed spellcaster with glowing eyes and a glowing orb wand, smooth stylized game character, clean hand-painted texture
```

### Siege minion
**Image prompt**
```
stylized 3D game asset of a small wooden cannon cart, four chunky round wooden wheels, rounded wooden body with iron side plates, dark iron cannon with a gold band, small white flag on a pole at the back, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, single object, centered, entire object visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text
```
**3D prompt**
```
small toy-like wooden cannon cart on four round wheels with a flag, smooth stylized game asset, clean hand-painted texture
```

### Tree
**Image prompt**
```
stylized 3D game asset of a round fantasy tree, short thick smooth brown trunk with visible roots, a full cluster of six puffy round green leaf balls, smooth rounded shapes, chunky toy-like proportions, clean hand-painted textures, soft bright colors, single object, centered, entire object visible, three-quarter view, plain white background, soft even studio lighting, no ground shadow, no text
```
**3D prompt**
```
round stylized tree with a thick trunk and puffy round leaf clusters, smooth game asset, clean hand-painted texture
```

---

## Hero weapons (optional, for later)

Heroes walk and swing as R6 rigs, so don't turn a whole hero into one model: it would be a stiff statue. Make just their **weapon** instead. Weapons look best **from the side**, so these prompts use a side view.

| Hero | Image prompt (the object part) | 3D prompt |
|---|---|---|
| Knight | `a knight's straight longsword with a gold crossguard and round gold pommel, leather grip` | `stylized longsword with gold crossguard` |
| Knight | `a kite-shaped knight shield, white with a gold rim and a gold cross` | `stylized kite shield with gold rim and cross` |
| Mage | `a wooden wizard staff with gold claws holding a glowing purple orb at the top` | `stylized wizard staff with glowing orb` |
| Ranger | `a curved wooden longbow with a leather grip and white string` | `stylized wooden longbow` |
| Guardian | `a heavy war hammer with a round steel head, gold band and long wooden handle` | `stylized war hammer with round steel head` |
| Guardian | `a tall rounded tower shield, white with a gold frame and a round gold boss` | `stylized tall tower shield with gold frame` |
| Assassin | `a short curved dagger with a dark grip and small guard` | `stylized short dagger` |
| Gunslinger | `a western lever-action rifle with a wooden stock, dark metal barrel and small scope` | `stylized lever-action rifle with wooden stock` |

Use the same template as the structures, with the object part swapped in. Replace "three-quarter view" with **"side view, lying straight, horizontal"**:
```
stylized 3D game asset of [OBJECT PART], smooth rounded shapes, chunky proportions, clean hand-painted textures, soft bright colors, single object, centered, entire object visible, side view, lying straight, horizontal, plain white background, soft even studio lighting, no ground shadow, no text
```

---

## Put it in the game

**Structures, minions, tree:**
1. In Studio: *File → Import 3D* and pick the FBX/GLB file.
2. Rename it to exactly `Tower`, `Nexus`, `Minion_melee`, `Minion_caster`, `Minion_siege` or `Tree`.
3. Put it in a folder named **Models** inside **ServerStorage**. Make sure the front faces Studio's *Front* side.
4. Press Play. The game resizes it and keeps all the gameplay working.

**Hero weapons (with the Model Kit plugin):**
1. Open the Model Kit and click the hero, for example **Knight**.
2. Import the weapon mesh and drag it into the editable Knight model, into his right hand. Delete the old part-built sword pieces.
3. Click **Save for both teams**. The new weapon follows the arm when he walks and swings. It also shows up in first person and on players who pick that hero.

Because these models use white and neutral colors, one version works for both teams. The health bars still show who's Blue and who's Red.
