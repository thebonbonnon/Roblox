# Meshy reference pack

Reference renders of every model in the game, for Meshy (or any image-to-3D tool), plus a text prompt for each.
`overview.png` shows them all.

```
art/meshy/
  Tower_Blue/       threequarter.png  front.png  back.png  left.png  right.png
  Tower_Red/        ...
  Nexus_Blue/ Nexus_Red/
  Minion_melee_Blue/ Minion_melee_Red/  (also caster, siege)
  Hero_Knight_Blue/ Hero_Knight_Red/    (also Mage, Ranger, Guardian, Assassin)
  Tree/
```

All images are 1024×1024 on a plain white background with one object each, and every model faces the camera in `front.png`.

## Which images to upload

- **One image:** use `threequarter.png`. It shows the most of the model at once.
- **Multiple views:** if Meshy offers multi-image upload, use `front.png`, `left.png`, `back.png` and `right.png`.
- **Always add the text prompt below.** The renders are made of blocks, so image-only generation can come out just as blocky. The prompt tells Meshy to add real detail while keeping the shape, colors and proportions from the image. If you want a smoother result, try Text to 3D with the prompt and use the image only as a guide.

## Settings that suit Roblox

- **Style:** stylized / cartoon. Turn texturing on, with PBR if offered.
- **Polycount:** keep it low (a few thousand triangles for minions and props, up to around 10k for towers). Roblox limits triangles per mesh, so check the Creator Hub docs for the current number. Use Meshy's remesh/reduce option or Blender if a mesh is too heavy.
- **Export:** `.fbx` or `.glb`. Studio's 3D Importer reads both.

## Prompts

Start every prompt with the same style line so all the models match:

> **Style:** stylized low-poly fantasy game asset, chunky toy-like proportions, hand-painted textures, clean readable silhouette, bright saturated colors, single object, no base, no background

Then add the model's line. Swap **blue** for **red** in the Red versions.

| Model | Prompt (after the style line) |
|---|---|
| Tower | a round stone watchtower with a stepped square plinth, grey cobblestone, two pale stone bands, four blue cloth banners with gold rods hanging on its sides, a crenellated battlement top, and a glowing blue crystal floating in a gold bowl above it |
| Nexus | a glowing blue crystal core floating above a stepped white marble platform, a gold pedestal under the crystal, two thin glowing blue rings orbiting it, four marble pillars at the corners topped with gold caps and small glowing blue orbs |
| Minion_melee | a small chubby armored soldier, blue body, round steel helmet with a glowing visor slit and a blue crest, steel chest plate, short sword in the right hand, round blue shield on the left arm |
| Minion_caster | a small hooded robed spellcaster, blue layered robe, gold collar, dark hood with two glowing eyes, holding a wooden wand topped with a glowing blue orb |
| Minion_siege | a small wooden cannon cart, four chunky wooden wheels, blue armor plates on the sides, dark iron cannon with a blue band, a blue flag on a pole at the back |
| Tree | a stylized round jungle tree, short thick brown trunk with roots, a cluster of four puffy green leaf balls |
| Hero_Knight | a knight in steel plate armor, blue tabard with a white cross, round helmet with a visor slit and a blue plume, shoulder pauldrons, holding a straight sword forward in the right hand, blue kite shield on the left arm |
| Hero_Mage | an old wizard in a purple robe with a blue sash, white beard, tall crooked purple wizard hat with a gold star, holding a wooden staff with a glowing purple orb in gold claws |
| Hero_Ranger | a hooded ranger in a green tunic, leather belt and bracers, blue cape, quiver of arrows on the back, wooden longbow in the left hand |
| Hero_Guardian | a huge tank warrior in heavy gold and bronze armor, horned helmet with a glowing blue visor, big round gold shoulder pads with bone spikes, tall blue tower shield on the left, war hammer in the right hand |
| Hero_Assassin | a slim assassin in dark grey cloth, hood and black face mask with glowing blue eyes, blue scarf with a trailing tail, two daggers held forward |

**Negative prompt** (if Meshy has one): `realistic, photo, gore, text, logo, base, pedestal, ground, background, multiple objects, extra limbs`

## Put it in the game

1. In Studio, open the 3D Importer (*File → Import 3D*) and import the `.fbx` or `.glb` file.
2. Rename the model to match its folder name here, for example `Tower_Blue`.
3. In the Explorer, create a folder named **`Models`** inside **`ServerStorage`** and move the model into it.
4. Make sure the front of the model faces the **Front** side in Studio (−Z). If it's backwards in game, rotate it 180° and save.
5. Press Play. The game scales it to the original model's height, removes any scripts inside it, and keeps all the gameplay (health bars, hitboxes, attacks) the same.

**Team colors:** a Meshy model has its colors painted into its texture, so make a `_Blue` and a `_Red` version. If you only add one version without a team name (just `Tower`), both teams use that same model.

## Start with towers, the nexus, minions and trees

Those don't need to bend, so a single mesh works perfectly.

**Heroes are different.** They are R6 rigs that walk and swing, and a Meshy hero is one solid statue that won't animate: it would slide around stiffly. So keep the R6 heroes, or generate just their **gear** (helmet, shield, sword, hat) as separate meshes and swap those in later.
