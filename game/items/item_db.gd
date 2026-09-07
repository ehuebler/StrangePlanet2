class_name ItemDB
extends RefCounted

## Every item the game can put in a slot.
##
## `kind` explicitly separates apparel, ordinary items, weapons and abilities.
## `slot` remains the wearable slot an apparel item occupies. Hats and capes.
## Container filters call [method accepts], so body equipment,
## the numbered hotbar, ability buttons and the backpack all share these rules.
## `scene` is the .glb, worn on the body or put in the hands and also rendered
## into the item's icon; `tint` stands in for the icon until that render lands.
##
## A weapon carries three more fields: `hold`, one of the WeaponPose holds, which
## decides how the arms take it; `attack`, either ATTACK_SWING or ATTACK_SHOOT; and
## for a shooting weapon, `cell`, how many shots it stores.

const KIND_APPAREL := "apparel"
const KIND_ITEM := "item"
const KIND_WEAPON := "weapon"
const KIND_ABILITY := "ability"
const KIND_MODIFIER := "modifier"

## Container filter ids. WEAPON is retained for old rack containers; HOTBAR is
## the broader numbered-slot rule and accepts both weapons and ordinary items.
const WEAPON := KIND_WEAPON
const HOTBAR := "hotbar"
const ABILITY := KIND_ABILITY
const BACKPACK := "backpack"

const ITEMS := {
	"straw_hat": {
		"title": "Straw Hat",
		"description": "Woven brim gone soft at the edges. Sits low enough to keep the sun off the page.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_hat.glb",
		"tint": Color(0.9023, 0.7954, 0.4978),
	},
	"c3_hair": {
		"title": "Settler Hair",
		"description": "Spiked and cut from the dressed settler. Sits on the scalp and takes a tint.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_hair.glb",
		"tint": Color(0.10, 0.11, 0.20),
	},
	"c3_party_hat": {
		"title": "Party Hat",
		"description": "A paper cone with a pom-pom. The stripes are the whole joke.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_party_hat.glb",
		"tint": Color(0.92, 0.22, 0.50),
	},
	"c3_bunny_ears": {
		"title": "Bunny Ears",
		"description": "Tall and slightly wilted. The pink is on the inside, where it belongs.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_bunny_ears.glb",
		"tint": Color(0.96, 0.72, 0.78),
	},
	"crawler_gale_hat": {
		"title": "Gale Cap",
		"description": "A city-made propeller cap. Flight time and footwork jump the moment it sits on.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_propeller_cap.glb",
		"tint": Color(0.18, 0.46, 0.92),
	},
	"crawler_ward_hat": {
		"title": "Ward Halo",
		"description": "A pale city halo. A thin iridescent bubble takes one hit, then comes back after a short wait.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_halo.glb",
		"tint": Color(0.72, 0.90, 1.0),
	},
	"crawler_luck_hat": {
		"title": "Fortune Cap",
		"description": "A city-made jester cap. Luck jumps the moment it sits on.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_jester_hat.glb",
		"tint": Color(0.18, 0.78, 0.42),
	},
	"crawler_kit_hat": {
		"title": "Bench Visor",
		"description": "A city-made visor. Ability mods can be moved anywhere the moment it sits on.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_visor.glb",
		"tint": Color(0.92, 0.62, 0.18),
	},
	"crawler_missile_hat": {
		"title": "Hex Hat",
		"description": "A city-made wizard hat. It looses a few homing missiles at the nearest mob.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_wizard_hat.glb",
		"tint": Color(0.48, 0.22, 0.82),
	},
	"crawler_mine_hat": {
		"title": "Trail Cap",
		"description": "A city-made hard hat. It drops a mine at your feet that bursts after a second.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_hard_hat.glb",
		"tint": Color(0.92, 0.42, 0.12),
	},
	"crawler_vampire_hat": {
		"title": "Vampire Horns",
		"description": "City-cut devil horns. Damage you deal pulls a little health back.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_devil_horns.glb",
		"tint": Color(0.72, 0.08, 0.14),
	},
	"crawler_phase_hat": {
		"title": "Phase Helm",
		"description": "A city-made space helm. Incoming projectiles sometimes pass through.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_space_helmet.glb",
		"tint": Color(0.42, 0.88, 0.96),
	},
	"crawler_ordinance_hat": {
		"title": "Ordinance Helm",
		"description": "A city-made combat helm. Explosive damage does not land.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_helmet.glb",
		"tint": Color(0.42, 0.48, 0.22),
	},
	"crawler_rubber_hat": {
		"title": "Rubber Beanie",
		"description": "A city-made yellow beanie. Shock does not land.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_beanie.glb",
		"tint": Color(0.96, 0.86, 0.18),
	},
	"crawler_learned_hat": {
		"title": "Learned Cap",
		"description": "A city-made deerstalker. A fourth ability can be equipped.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_deerstalker.glb",
		"tint": Color(0.38, 0.24, 0.16),
	},
	"crawler_juke_hat": {
		"title": "Juke Cap",
		"description": "A city-made ball cap. Juking through a foe hurts them.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_baseball_cap.glb",
		"tint": Color(0.22, 0.72, 0.38),
	},
	"crawler_plain_cape": {
		"title": "Plain Cape",
		"description": "A blank white cape. It hangs from the shoulders and follows the wind. Colour comes later.",
		"kind": KIND_APPAREL,
		"slot": "cape",
		"scene": "res://game/player/cape_cloth.tscn",
		"tint": Color(1.0, 1.0, 1.0),
	},
	"crawler_fool_cape": {
		"title": "Fool's Teleport Cape",
		"description": "Purple cloth with red splotches. A hit throws you somewhere else, usually a few metres, rarely a very long way.",
		"kind": KIND_APPAREL,
		"slot": "cape",
		"scene": "res://game/player/cape_cloth.tscn",
		"tint": Color(0.42, 0.16, 0.62),
		"paint": "res://assets/runtime/apparel/cape_fool_paint.png",
	},
	"crawler_respawn_ticket": {
		"title": "Respawn Ticket",
		"description": "One death comes back at Relay 07. Buy more at the city black market. Without a ticket the run ends.",
		"kind": KIND_ITEM,
		"ledger": true,
		"tint": Color(0.86, 0.22, 0.28),
	},
	"c3_top_hat": {
		"title": "Top Hat",
		"description": "Tall black felt and a gold band. Makes the settler look like it has somewhere to be.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_top_hat.glb",
		"tint": Color(0.12, 0.11, 0.12),
	},
	"c3_crown": {
		"title": "Crown",
		"description": "Seven points and a blue stone over the brow. Authority, or a very committed costume.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_crown.glb",
		"tint": Color(0.90, 0.70, 0.22),
	},
	"c3_beanie": {
		"title": "Beanie",
		"description": "Slouchy knit with a thick cuff. Sits off to one side as if it grew there.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_beanie.glb",
		"tint": Color(0.18, 0.50, 0.46),
	},
	"c3_cowboy_hat": {
		"title": "Cowboy Hat",
		"description": "Wide brim rolled at the sides, crown pinched. For weather that has not arrived yet.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_cowboy_hat.glb",
		"tint": Color(0.55, 0.38, 0.22),
	},
	"c3_propeller_cap": {
		"title": "Propeller Cap",
		"description": "A red crown and two blades that do not turn. The suggestion of flight is enough.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_propeller_cap.glb",
		"tint": Color(0.82, 0.18, 0.16),
	},
	"c3_flower_crown": {
		"title": "Flower Crown",
		"description": "A vine and a ring of blooms. Soft, and it still counts as a hat.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_flower_crown.glb",
		"tint": Color(0.90, 0.45, 0.62),
	},
	"c3_antlers": {
		"title": "Antlers",
		"description": "Branched bone on a leather band. Wider than the doorway, which is part of the look.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_antlers.glb",
		"tint": Color(0.45, 0.28, 0.16),
	},
	"c3_halo": {
		"title": "Halo",
		"description": "A gold ring that hovers. It does not make you better. It does make you taller.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_halo.glb",
		"tint": Color(0.98, 0.84, 0.34),
	},
	"c3_wizard_hat": {
		"title": "Wizard Hat",
		"description": "A bent purple cone, gold band, and a buckle that has never held a spell.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_wizard_hat.glb",
		"tint": Color(0.36, 0.18, 0.52),
	},
	"c3_sombrero": {
		"title": "Sombrero",
		"description": "A straw brim you could land a bird on, with a red band for emphasis.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_sombrero.glb",
		"tint": Color(0.80, 0.62, 0.28),
	},
	"c3_newsboy_cap": {
		"title": "Newsboy Cap",
		"description": "Puffy tweed and a short brim. The button on top is load-bearing, emotionally.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_newsboy_cap.glb",
		"tint": Color(0.30, 0.36, 0.28),
	},
	"c3_helmet": {
		"title": "Helmet",
		"description": "A steel dome with a ridge. It will not stop a fall. It will stop the sun.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_helmet.glb",
		"tint": Color(0.48, 0.50, 0.54),
	},
	"c3_pirate_hat": {
		"title": "Pirate Hat",
		"description": "A tricorne folded in three places, trimmed red. No ship is required.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_pirate_hat.glb",
		"tint": Color(0.10, 0.08, 0.08),
	},
	"c3_chef_toque": {
		"title": "Chef Toque",
		"description": "Pleated white linen stacked into a cloud. Suggests you know what a kitchen is.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_chef_toque.glb",
		"tint": Color(0.94, 0.94, 0.90),
	},
	"c3_jester_hat": {
		"title": "Jester Hat",
		"description": "Three floppy points and a bell on each. You will hear yourself coming.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_jester_hat.glb",
		"tint": Color(0.48, 0.16, 0.56),
	},
	"c3_mushroom_cap": {
		"title": "Mushroom Cap",
		"description": "A red dome with white spots. Soft-looking, and not for eating.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_mushroom_cap.glb",
		"tint": Color(0.80, 0.18, 0.16),
	},
	"c3_antennae": {
		"title": "Antennae",
		"description": "Two sprung rods and lime bulbs. Reception is a matter of confidence.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_antennae.glb",
		"tint": Color(0.40, 0.88, 0.32),
	},
	"c3_visor": {
		"title": "Visor",
		"description": "A foam brim and a strap. Keeps glare off the eyes and little else.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_visor.glb",
		"tint": Color(0.18, 0.78, 0.36),
	},
	"c3_bow": {
		"title": "Hair Bow",
		"description": "A silk knot, two loops, and tails. Sits high, where it can be seen from behind.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_bow.glb",
		"tint": Color(0.74, 0.12, 0.22),
	},
	"c3_horned_helm": {
		"title": "Horned Helm",
		"description": "Iron bowl, two swept horns. Historical accuracy was not consulted.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_horned_helm.glb",
		"tint": Color(0.40, 0.41, 0.44),
	},
	"c3_fedora": {
		"title": "Fedora",
		"description": "Pinched crown, brim snapped in front. The band is darker than the felt on purpose.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_fedora.glb",
		"tint": Color(0.30, 0.18, 0.12),
	},
	"c3_santa_hat": {
		"title": "Santa Hat",
		"description": "A floppy red cone, white cuff, white pom. It leans like it has had a long year.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_santa_hat.glb",
		"tint": Color(0.74, 0.10, 0.10),
	},
	"c3_cat_ears": {
		"title": "Cat Ears",
		"description": "Short, pointed, and pink inside. The band is the only part doing any work.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_cat_ears.glb",
		"tint": Color(0.16, 0.12, 0.12),
	},
	"c3_beret": {
		"title": "Beret",
		"description": "A slouch of wool and a stem that does nothing. It sits like it has opinions.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_beret.glb",
		"tint": Color(0.22, 0.18, 0.48),
	},
	"c3_baseball_cap": {
		"title": "Baseball Cap",
		"description": "A soft crown and a brim that points forward. The button is still load-bearing.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_baseball_cap.glb",
		"tint": Color(0.16, 0.34, 0.64),
	},
	"c3_sun_hat": {
		"title": "Sun Hat",
		"description": "A straw brim wide enough to make its own shade, and a ribbon that insists.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_sun_hat.glb",
		"tint": Color(0.86, 0.74, 0.40),
	},
	"c3_hard_hat": {
		"title": "Hard Hat",
		"description": "A yellow shell with a ridge. It looks official. It is not.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_hard_hat.glb",
		"tint": Color(0.90, 0.72, 0.12),
	},
	"c3_ushanka": {
		"title": "Ushanka",
		"description": "Fur, ear flaps, and the suggestion that winter is a personality.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_ushanka.glb",
		"tint": Color(0.44, 0.30, 0.18),
	},
	"c3_turban": {
		"title": "Turban",
		"description": "Cloth wrapped until it becomes architecture. The jewel is optional confidence.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_turban.glb",
		"tint": Color(0.74, 0.18, 0.20),
	},
	"c3_devil_horns": {
		"title": "Devil Horns",
		"description": "Two swept horns on a dark band. Costume shops have been notified.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_devil_horns.glb",
		"tint": Color(0.46, 0.08, 0.10),
	},
	"c3_unicorn_horn": {
		"title": "Unicorn Horn",
		"description": "A spiral on the crown. Magic is not included and will not be refunded.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_unicorn_horn.glb",
		"tint": Color(0.96, 0.88, 0.70),
	},
	"c3_headphones": {
		"title": "Headphones",
		"description": "Over-ear cups and a band that actually clears the skull. Silent, on purpose.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_headphones.glb",
		"tint": Color(0.16, 0.16, 0.18),
	},
	"c3_tiara": {
		"title": "Tiara",
		"description": "A low silver arc and five small stones. Formal, if you squint.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_tiara.glb",
		"tint": Color(0.82, 0.84, 0.88),
	},
	"c3_bandana": {
		"title": "Bandana",
		"description": "Tied at the back, covering the crown. The knot is doing most of the talking.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_bandana.glb",
		"tint": Color(0.18, 0.44, 0.30),
	},
	"c3_rice_hat": {
		"title": "Rice Hat",
		"description": "A conical straw brim. Rain, sun, and curiosity all bounce off the same slope.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_rice_hat.glb",
		"tint": Color(0.72, 0.58, 0.28),
	},
	"c3_laurel": {
		"title": "Laurel",
		"description": "A ring of leaves. Victory is implied and not enforced.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_laurel.glb",
		"tint": Color(0.30, 0.54, 0.20),
	},
	"c3_nightcap": {
		"title": "Nightcap",
		"description": "A floppy cone and a pale pom. It leans as if bedtime already won.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_nightcap.glb",
		"tint": Color(0.32, 0.20, 0.54),
	},
	"c3_deerstalker": {
		"title": "Deerstalker",
		"description": "Front brim, back brim, ear flaps. Detection of deer is still pending.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_deerstalker.glb",
		"tint": Color(0.38, 0.34, 0.24),
	},
	"c3_frog_hood": {
		"title": "Frog Hood",
		"description": "A green hood with two eye bumps. You will be asked if you are a frog.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_frog_hood.glb",
		"tint": Color(0.30, 0.64, 0.24),
	},
	"c3_rainbow": {
		"title": "Rainbow",
		"description": "Three arcs parked on the crown. Weather is not required.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_rainbow.glb",
		"tint": Color(0.88, 0.28, 0.34),
	},
	"c3_paper_crown": {
		"title": "Paper Crown",
		"description": "Eight points and a yellow dot on each. Birthday authority, laminated in spirit.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_paper_crown.glb",
		"tint": Color(0.92, 0.24, 0.30),
	},
	"c3_space_helmet": {
		"title": "Space Helmet",
		"description": "A glass bubble and a collar. The planet is already strange; this commits to it.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_space_helmet.glb",
		"tint": Color(0.58, 0.74, 0.84),
	},
	"c3_cake_hat": {
		"title": "Cake Hat",
		"description": "Two layers, pink icing, six candles. Do not eat it. That is the whole rule.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_cake_hat.glb",
		"tint": Color(0.94, 0.46, 0.58),
	},
	"c3_leaf_wreath": {
		"title": "Leaf Wreath",
		"description": "Autumn leaves on a vine. Seasonal, and it still counts as a hat.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_leaf_wreath.glb",
		"tint": Color(0.64, 0.38, 0.14),
	},
	"c3_mohawk": {
		"title": "Mohawk",
		"description": "A ridge of hair down the middle. The clip is the only honest part.",
		"kind": KIND_APPAREL,
		"slot": "hat",
		"scene": "res://assets/runtime/apparel/apparel_c3_mohawk.glb",
		"tint": Color(0.74, 0.14, 0.44),
	},
	"sword": {
		"title": "Drill Sword",
		"description": "Brass furniture on a leather-wrapped grip. Held two-handed, blade up, and cut across the body from right to left.",
		"kind": KIND_WEAPON,
		"slot": "weapon",
		"scene": "res://assets/runtime/items/sword.glb",
		"hold": "blade",
		"attack": "swing",
		"tint": Color(0.72, 0.735, 0.76),
	},
	"laser_rifle": {
		"title": "Laser Carbine",
		"description": "Twelve shots in a cell that trickles back up on its own. Left hand under the barrel, right on the trigger; right click to sight down the optic.",
		"kind": KIND_WEAPON,
		"slot": "weapon",
		"scene": "res://assets/runtime/items/laser_rifle.glb",
		"hold": "rifle",
		"attack": "shoot",
		"cell": 12,
		"tint": Color(0.44, 0.47, 0.5),
	},
}

## How each stat is spelled out for the abilities menu, in the order it is shown.
##
## A table rather than a formatter per screen, because the menu is not the only
## thing that will ever want to say how much damage something does, and two
## places writing "60 m" their own way is how one of them ends up saying "60.0".
## Anything an ability declares that is not listed here is still shown, using
## its own key and a plain number, so a new stat is never silently swallowed.
const STAT_ORDER := ["boost", "damage", "player_damage", "impact", "speed", "duration",
	"range", "radius", "cooldown", "cast", "delay", "launch_height", "launch_speed",
	"slam_speed", "rope_length", "swing_acceleration", "max_speed",
	"impact_speed", "knockback", "lift", "self_launch_speed",
	"crater_radius", "crater_depth", "crater_warp",
	"projectile_radius", "beam_radius", "paint_radius", "paint_spacing",
	"chain_interval",
	"size", "beam_width", "impact_radius", "damage_hz", "arcs", "shock",
	"toxic", "freeze", "charm", "slots",
	"wobble", "wobble_cone_degrees", "multi", "far_cast", "bounce",
	"impact_cast", "homing", "homing_range",
	"wall_width", "wall_height", "wall_thickness", "fade_duration",
	"project", "firewall", "house", "swap",
	"explosion_duration", "animation_duration", "apex_time"]
const STAT_LABELS := {
	"boost": "Boost",
	"damage": "Damage",
	"player_damage": "Player Damage",
	"impact": "Impact",
	"speed": "Speed",
	"duration": "Duration",
	"range": "Range",
	"radius": "Radius",
	"cooldown": "Cooldown",
	"cast": "Cast Time",
	"delay": "Delay",
	"launch_height": "Launch Height",
	"launch_speed": "Launch Speed",
	"slam_speed": "Slam Speed",
	"rope_length": "Rope Length",
	"swing_acceleration": "Swing Acceleration",
	"max_speed": "Maximum Speed",
	"impact_speed": "Impact Threshold",
	"knockback": "Knockback",
	"lift": "Lift",
	"self_launch_speed": "Self Launch",
	"crater_radius": "Crater Radius",
	"crater_depth": "Crater Depth",
	"crater_warp": "Crater Irregularity",
	"projectile_radius": "Projectile Radius",
	"beam_radius": "Beam Radius",
	"paint_radius": "Paint Radius",
	"paint_spacing": "Paint Spacing",
	"chain_interval": "Blast Step",
	"size": "Size",
	"beam_width": "Beam Width",
	"impact_radius": "Impact Radius",
	"damage_hz": "Pulse Rate",
	"arcs": "Arcs",
	"shock": "Shock",
	"toxic": "Toxic",
	"freeze": "Freeze",
	"charm": "Charm",
	"slots": "Modifier Slots",
	"wobble": "Wobble",
	"wobble_cone_degrees": "Wobble Cone",
	"multi": "Splits",
	"far_cast": "Far Cast",
	"bounce": "Bounces",
	"impact_cast": "Impact Cast",
	"homing": "Homing",
	"homing_range": "Seek Range",
	"wall_width": "Wall Width",
	"wall_height": "Wall Height",
	"wall_thickness": "Wall Thickness",
	"fade_duration": "Fade",
	"project": "Project",
	"firewall": "Firewall",
	"house": "House",
	"swap": "Swap",
	"explosion_duration": "Explosion",
	"animation_duration": "Animation",
	"apex_time": "Apex Hold",
}
const STAT_UNITS := {
	"damage": "",
	"player_damage": "",
	"impact": "",
	"speed": " m/s",
	"duration": " s",
	"range": " m",
	"radius": " m",
	"cooldown": " s",
	"cast": " s",
	"delay": " s",
	"launch_height": " m",
	"launch_speed": " m/s",
	"slam_speed": " m/s",
	"rope_length": " m",
	"swing_acceleration": " m/s²",
	"max_speed": " m/s",
	"impact_speed": " m/s",
	"knockback": " m/s",
	"lift": " m/s",
	"self_launch_speed": " m/s",
	"crater_radius": " m",
	"crater_depth": " m",
	"projectile_radius": " m",
	"beam_radius": " m",
	"paint_radius": " m",
	"paint_spacing": " m",
	"chain_interval": " s",
	"size": " x",
	"slots": "",
	"beam_width": " x",
	"impact_radius": " m",
	"damage_hz": "/s",
	"arcs": "",
	"shock": " s",
	"toxic": " s",
	"freeze": "%",
	"charm": " s",
	"wobble_cone_degrees": "°",
	"multi": "x",
	"far_cast": " m",
	"bounce": "",
	"wall_width": " m",
	"wall_height": " m",
	"wall_thickness": " m",
	"fade_duration": " s",
	"project": " m/s",
	"firewall": "/s",
	"explosion_duration": " s",
	"animation_duration": " s",
	"apex_time": " s",
}

## Wearable slots, hat then cape. Hats sit on the head; capes hang from the back.
const SLOT_ORDER := ["hat", "cape"]

const ATTACK_SWING := "swing"
const ATTACK_SHOOT := "shoot"

## Shown on an equipment slot that has nothing in it yet.
const SLOT_LABELS := {
	"hat": "Hat",
	"cape": "Cape",
}


static var _runtime_items: Dictionary = {}


static func register_runtime_item(id: String, data: Dictionary) -> void:
	if id.is_empty() or data.is_empty():
		return
	_runtime_items[id] = data.duplicate(true)


static func unregister_runtime_item(id: String) -> void:
	_runtime_items.erase(id)


static func model_of(id: String) -> String:
	var listed := String(_field(id, "model", ""))
	return listed if not listed.is_empty() else id


static func has_item(id: String) -> bool:
	if _runtime_items.has(id):
		return true
	if CrawlerCatalog.is_token(id):
		return CrawlerCatalog.has(id)
	return ITEMS.has(id) or AbilityCatalog.has(id) or CrawlerCatalog.has(id)


static func title(id: String) -> String:
	if CrawlerCatalog.has(id):
		var labeled := CrawlerCatalog.title_of(id)
		if not labeled.is_empty():
			return labeled
	var definition := ability_definition(id)
	if definition != null:
		return definition.title
	return String(_field(_catalog_key(id), "title", _catalog_key(id)))


static func description(id: String, host_id := "", size_rank := -1) -> String:
	if CrawlerCatalog.has(id) and (
			CrawlerCatalog.is_modifier(id) or CrawlerCatalog.is_modifier_token(id)):
		return CrawlerCatalog.description_of(id, host_id, size_rank)
	var definition := ability_definition(id)
	if definition != null:
		return definition.description
	if CrawlerCatalog.has(id):
		return CrawlerCatalog.description_of(id, host_id, size_rank)
	return String(_field(_catalog_key(id), "description", ""))


## The body slot this item is worn in, or "" if it cannot be worn.
static func slot_of(id: String) -> String:
	return String(_field(id, "slot", ""))


## Explicit catalogue classification. The fallback keeps an older external item
## table parseable, but every item shipped in [constant ITEMS] declares a kind.
static func kind_of(id: String) -> String:
	if CrawlerCatalog.is_modifier_token(id) or CrawlerCatalog.is_modifier(id):
		return KIND_MODIFIER
	if CrawlerCatalog.is_ability_token(id) or AbilityCatalog.has(_catalog_key(id)):
		return KIND_ABILITY
	var explicit := String(_field(id, "kind", ""))
	if not explicit.is_empty():
		return explicit
	var slot := slot_of(id)
	if slot == WEAPON:
		return KIND_WEAPON
	if slot in SLOT_ORDER:
		return KIND_APPAREL
	return KIND_ITEM if has_item(id) else ""


static func is_apparel(id: String) -> bool:
	return kind_of(id) == KIND_APPAREL


static func is_weapon(id: String) -> bool:
	return kind_of(id) == KIND_WEAPON


static func is_item(id: String) -> bool:
	return kind_of(id) == KIND_ITEM


static func is_ability(id: String) -> bool:
	return kind_of(id) == KIND_ABILITY


## Numbered slots accept things that can be drawn and activated with the mouse.
## Ledger items stay on the run sheet; they never occupy a hotbar or backpack slot.
static func accepts_hotbar(id: String) -> bool:
	return has_item(id) and (is_weapon(id) or is_item(id)) and not is_ledger(id)


static func is_ledger(id: String) -> bool:
	return bool(_field(id, "ledger", false))


static func accepts_ability(id: String) -> bool:
	return has_item(id) and is_ability(id)


## Abilities are selected powers rather than carried objects.
static func accepts_backpack(id: String) -> bool:
	return has_item(id) and not is_ability(id) and not is_ledger(id)


## Shared rule used by [ItemContainer]. Empty ids always clear a slot.
static func accepts(filter: String, id: String) -> bool:
	if id.is_empty():
		return true
	if filter.begins_with(CrawlerCatalog.FILTER_MOD):
		var ability := filter.substr(CrawlerCatalog.FILTER_MOD.length())
		if ability.begins_with(":"):
			ability = ability.substr(1)
		if kind_of(id) != KIND_MODIFIER:
			return false
		return ability.is_empty() or CrawlerCatalog.compatible(id, ability)
	match filter:
		CrawlerCatalog.FILTER_KIT:
			return CrawlerCatalog.is_token(id) and CrawlerCatalog.has(id)
		"":
			return has_item(id)
		HOTBAR:
			return accepts_hotbar(id)
		ABILITY:
			return accepts_ability(id)
		BACKPACK:
			return accepts_backpack(id)
		WEAPON:
			return is_weapon(id)
		_:
			return is_apparel(id) and slot_of(id) == filter


## Every weapon in the catalogue, in table order. Derived rather than listed, so a
## weapon added to [constant ITEMS] is offered by the character editor with no
## second table to remember. The wardrobe's equivalent is
## [method CharacterDB.apparel_ids], which cannot be derived the same way: a
## garment belongs to one skeleton and a weapon is held by anybody.
static func weapon_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id: String in ITEMS:
		if is_weapon(id):
			ids.append(id)
	return ids


static func hotbar_ids() -> PackedStringArray:
	var ids := PackedStringArray()
	for id: String in ITEMS:
		if accepts_hotbar(id):
			ids.append(id)
	return ids


static func ability_ids() -> PackedStringArray:
	return AbilityCatalog.ids()


## Complete authored definition, shared by runtime, menu, and effect factories.
static func ability_definition(id: String) -> AbilityDefinition:
	return AbilityCatalog.definition(_catalog_key(id))


## The script that implements an ability, or "" for anything that is not one.
static func ability_script(id: String) -> String:
	var definition := ability_definition(id)
	return definition.implementation.resource_path \
		if definition != null and definition.implementation != null else ""


## The raw numbers behind an ability: damage, range, cooldown and so on.
##
## Kept in the catalogue beside the title and the description because those
## three together are the whole of what a slot needs to describe itself, and
## splitting the numbers into the ability script would mean the menu had to load
## and instance an ability to find out what it does.
static func stats_of(id: String) -> Dictionary:
	var definition := ability_definition(id)
	return definition.stats if definition != null else {}


static func ability_profile(id: String) -> String:
	var definition := ability_definition(id)
	return definition.profile_line() if definition != null else ""


static func ability_icon(id: String) -> Texture2D:
	var definition := ability_definition(id)
	if definition != null and definition.icon != null:
		return definition.icon
	return CrawlerCatalog.icon(id)


static func _catalog_key(id: String) -> String:
	return CrawlerCatalog.catalog_id(id) if CrawlerCatalog.is_token(id) else id


## The same numbers written out for a menu, one line each, in a fixed order.
##
## Label and value are separated by a tab so a caller can lay them out in two
## columns without parsing anything back out of the string.
static func stat_lines(id: String) -> PackedStringArray:
	return stat_lines_from(stats_of(id))


static func stat_lines_from(stats: Dictionary, base: Dictionary = {}) -> PackedStringArray:
	var lines := PackedStringArray()
	if stats.is_empty():
		return lines
	var written := {}
	for key: String in STAT_ORDER:
		if not stats.has(key) or not _is_stat_number(stats[key]):
			continue
		written[key] = true
		lines.append("%s\t%s" % [STAT_LABELS.get(key, key.capitalize()),
			format_boosted(base, stats, key)])
	# Anything the table above does not know about, so an ability declaring a
	# stat nobody has thought of yet still shows it rather than hiding it.
	for key: Variant in stats:
		var name := str(key)
		if written.has(name) or name.ends_with("_unit") or not _is_stat_number(stats[key]):
			continue
		lines.append("%s\t%s" % [STAT_LABELS.get(name, name.capitalize()),
			format_boosted(base, stats, name)])
	return lines


static func format_boosted(base_stats: Dictionary, live_stats: Dictionary,
		key: String) -> String:
	if not live_stats.has(key) or not _is_stat_number(live_stats[key]):
		return ""
	if base_stats.is_empty() or not base_stats.has(key) \
			or not _is_stat_number(base_stats[key]):
		return _stat_value(live_stats, key)
	var shown := _stat_value(base_stats, key)
	var delta := float(live_stats[key]) - float(base_stats[key])
	if is_zero_approx(delta):
		return shown
	var bit := "%d" % int(round(delta)) if is_equal_approx(delta, round(delta)) \
		else "%.1f" % delta
	if delta > 0.0:
		bit = "+" + bit
	return "%s (%s)" % [shown, bit]


static func _is_stat_number(value: Variant) -> bool:
	return typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT


## One stat as it reads on screen. Whole numbers lose their decimal point, since
## "1200 /s" is a damage figure and "1200.0 /s" is a debug print.
static func _stat_value(stats: Dictionary, key: String) -> String:
	if not _is_stat_number(stats.get(key, null)):
		return ""
	var amount := float(stats[key])
	if key == "boost":
		return "%d%%" % int(round(amount * 100.0))
	if key == "swap":
		return "On" if amount > 0.5 else "Off"
	var written := "%d" % int(round(amount)) if is_equal_approx(
		amount, round(amount)) else "%.1f" % amount
	# A per-second or per-hit qualifier authored beside the number, so a
	# sustained beam and a single blow are told apart in the menu.
	return written + String(stats.get(key + "_unit",
		STAT_UNITS.get(key, "")))


## Which WeaponPose hold the arms take this in, or "" for something not held.
static func hold_of(id: String) -> String:
	return String(_field(id, "hold", ""))


## ATTACK_SWING or ATTACK_SHOOT, or "" for an item that does neither.
static func attack_of(id: String) -> String:
	return String(_field(id, "attack", ""))


## Shots the weapon's cell holds, or 0 for a weapon that needs none.
static func cell_size(id: String) -> int:
	return int(_field(id, "cell", 0))


static func tint(id: String) -> Color:
	var definition := ability_definition(id)
	if definition != null:
		return definition.tint
	return _field(id, "tint", Color(0.6, 0.6, 0.6))


## The .glb this item is worn as, or "" for an item with no model.
static func scene_path(id: String) -> String:
	return String(_field(id, "scene", ""))


static func paint_path(id: String) -> String:
	return String(_field(id, "paint", ""))


## Every item that is worn in `slot`, which is how the wardrobe is stocked.
static func items_for_slot(slot: String) -> Array:
	var found := []
	for id in ITEMS:
		if slot_of(id) == slot:
			found.append(id)
	return found


static func _field(id: String, key: String, fallback: Variant) -> Variant:
	if _runtime_items.has(id):
		return (_runtime_items[id] as Dictionary).get(key, fallback)
	var entry: Dictionary = ITEMS.get(id, {})
	return entry.get(key, fallback)
