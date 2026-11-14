"""The manual's words. build_manual.py lays them out.
A species: (picture, name, scientific name, tag, where to look, description).
Tags: E found only in the Seychelles, I brought by people, R rare in the game, N by night / dusk."""

TITLE = "Tropical Island"
SUBTITLE = "A walker's manual and field guide"

WELCOME = [
    "Tropical Island is a walk, not a game to win. You arrive on the beach of a small granite "
    "island in the Seychelles, untouched by people, and everything from there is yours to "
    "find: a forest of takamaka and palms, a hill with a view, a stream, a cave under leaning "
    "boulders, a seabird colony, a lagoon and a coral reef. There are no goals, no score and "
    "no dangers. Nothing here bites, stings or hunts you.",
    "The island keeps time with your own day. Its sun, moon, tide and night sky follow your "
    "computer's clock and calendar, so the place you find in the morning is not the one you "
    "find at night. The second half of this manual is a field guide to the plants and animals "
    "that live here, with a box to tick for each one you have met.",
]

CONTROLS = [
    ("W A S D / arrows", "Walk"),
    ("Mouse", "Look around (click to capture the mouse, Esc to release it)"),
    ("Shift", "Jog"),
    ("Space", "Hop; while swimming: dive on one breath"),
    ("C (hold)", "Crouch, for a close look at small things"),
    ("T", "Time of day: your clock, midday, afternoon, golden hour, sunset, night"),
    ("M", "Moon: today's phase, full, half, crescent, new"),
    ("G", "Tide: by the moon, high water, half tide, low water"),
    ("N", "Call a rain shower; press again to let it pass"),
    ("B", "The sea's glow at night: call it or send it away"),
    ("F", "Free camera (E / Space up, C / Ctrl down, Shift faster)"),
    ("P", "Photo, saved to your Pictures folder"),
    ("R", "Unstuck: back to the last firm ground you stood on"),
    ("H", "Show the keyboard shortcuts"),
    ("Ctrl + Cmd + F", "Full screen (also Option + Enter)"),
    ("Cmd + Q", "Quit"),
]

GOOD_TO_KNOW = [
    "<b>Starting.</b> Open <i>Tropical Island.app</i>. On a Mac that has not run it before, "
    "right-click the app and choose Open. Click into the window to look around.",
    "<b>Walking.</b> Bushes are not solid; you push through them. Rocks and trunks are. If you "
    "ever get wedged, press R.",
    "<b>Swimming.</b> Walk into the sea. Where the water is deeper than your chest you float "
    "and swim. Deep water beyond the reef is the island's only boundary.",
    "<b>Snorkeling.</b> While floating, look down: your face goes under water and the reef "
    "opens below you.",
    "<b>Diving.</b> While swimming, press Space and swim where you look, down to four and a "
    "half meters, for up to 45 seconds. The edges of the view dim for the last ten. You rise "
    "by yourself and need ten seconds of breath before the next dive.",
]

# Places on the map: (number, x, z, name, text), in the game's own meters: +x is west, +z north.
PLACES = [
    (1, -6, 28, "Start beach", "Where you arrive, on the west coast. The sun sets over this sea."),
    (2, -62, 46, "The grotto", "55 m inland, up the opening toward the ridge, then right. A cleft facing the sea leads in."),
    (3, -60, 20, "The ridge", "An open grassy back leading up the hill. The giant tortoises graze here."),
    (4, -110, -12, "The summit", "44 m up: the lookout. Pitcher plants, orchids and wild vanilla on the granite just below."),
    (5, -57, -106, "Stream and pond", "150 m south along the beach, then inland. Frogs, dragonflies, a heron."),
    (6, -96, -188, "Seabird colony", "The Pisonia grove on the southern headland: noddies, white terns, frigatebirds, tropicbirds."),
    (7, -43, -184, "Sooty terns", "Seventy ground-nesting terns on the open sand west of the grove. You hear them first."),
    (8, -183, -22, "East headland", "A granite platform with tide pools and barnacles. Come at low water."),
    (9, 76, -4, "Coral garden", "75 m straight out from the start beach, on the reef crest where the swell breaks."),
    (10, 90, 30, "Reef edge", "As far as you can swim. The barracudas hang here; dolphins pass outside."),
    (11, 3, -40, "Mangroves", "Where the forest meets the sea. Mudskippers sit on the wet sand."),
    (12, 23, -2, "The boat", "An old boat at anchor in the lagoon, riding the swell."),
]

FEATURES = [
    ("The day", "T",
     "The island's hour is your own. Sunrise comes at about 6:20 in the east, behind the island, "
     "and sunset at about 18:20 in the west, over the sea off the start beach, as near the equator all year. "
     "The sun takes its true path for the Seychelles on today's date: from November to January it "
     "passes south of overhead, from May to July north, and the point of sunset wanders along the "
     "horizon with it. "
     "Start in the evening and you arrive at night. Many animals keep hours: fish schools "
     "sleep among the corals after dark and turtles rest on the bottom, terns and tropicbirds "
     "fly out at dusk, and the flying foxes leave their roost. T steps through the times of "
     "day and, after night, returns to the clock."),
    ("The moon and the stars", "M",
     "The moon shows the real phase for today's date and crosses the sky as the real moon "
     "does. A full moon rises behind the island as the sun sets and stands high at "
     "midnight; a young crescent hangs over the sea after sunset, lying on its back like a "
     "boat, as it does in the tropics. Its light follows its phase and height. At new moon "
     "the night belongs to a southern sky of stars and the Milky Way, which turn with the hours."),
    ("The tide", "G",
     "The sea rises and falls at its real pace, with high water every 12 hours and 25 minutes, "
     "about 50 minutes later each day. Because the moon drives it, the range is greatest at "
     "new and full moon (spring tides) and smallest at half moon (neaps). At high water the "
     "sea stands among the mangrove roots. At low water the beaches are some five meters "
     "wider, the reef crest comes out of the sea and tide pools are left on the east "
     "headland. Shorebirds, mudskippers and young sharks follow the water's edge."),
    ("Rain", "N",
     "Rarely, a shower passes at its natural pace. The sky closes, the wind doubles and the "
     "trees show it, then it rains for a quarter of an hour or more. Sand and rock turn dark, "
     "rings spread on the sea, lizards and butterflies take cover; under overhanging granite "
     "it stays dry. Toward the end the sun returns while the last drops fall. If it stands "
     "low, look away from it for a rainbow, far off and often double. Afterward the leaves "
     "glint, the trees drip and the frogs call. Rain brings out hermit crabs, millipedes and snails."),
    ("The glowing sea", "B",
     "On about one night in three the sea glows. A bloom of <i>Noctiluca</i>, a single-celled "
     "plankton, flashes blue wherever the water is stirred: in the breaking surf, in your "
     "wake, in your wet footprints on the sand. The light is a chemical reaction of the "
     "kind fireflies use, set off by movement. Whether tonight glows is decided by the date; "
     "glowing nights tend to follow each other, and so do dark ones."),
]

MORE = [
    ("Under water",
     "Sunlight plays on the sea floor as a moving net of bright lines, and in the afternoon "
     "shafts of light slant down through the water. With your head under you hear the reef: "
     "the fine crackle of snapping shrimp, loudest over living coral, and the crunch of "
     "parrotfish biting it. You glide over the corals, never through them."),
    ("The grotto",
     "The cave is of the kind these granite islands have: not a hollow in the rock but the "
     "space under huge boulders leaning on one another. A low front room, a passage, then a "
     "high inner room where the roots of a tree hang through a gap in the roof. On mornings "
     "from late October to late February, and with T's midday at any time, a shaft of sunlight falls through it. Water drips, and your steps echo."),
    ("Listening",
     "Every sound belongs to something. Surf keeps step with the waves you see. The mynas "
     "chatter, the ground dove coos, the sooty terns scream; a tortoise munches, a turtle "
     "blows when its head breaks the surface, a ripe coconut thuds down somewhere near you."),
]

TIPS = [
    "<b>Keep a little distance.</b> Animals move off calmly when you come too close. A few "
    "steps back and most carry on.",
    "<b>Stand still.</b> A hermit crab that has snapped into its shell looks out again after "
    "a few seconds. Garden eels rise behind you once you have passed.",
    "<b>Look small and look up.</b> Skinks, frogs and millipedes are life-size. Crouch (C). "
    "Spiders, geckos and termites are on the trunks, above head height.",
    "<b>Choose your hour.</b> Golden hour and night bring out hermit crabs, millipedes, "
    "snails and flying foxes. Day belongs to lizards, butterflies and reef fish.",
    "<b>Choose your tide.</b> Low water (G) opens the tide pools and shows the barnacle belt.",
    "<b>Give the nesting turtle room.</b> Stay three meters away while she crawls up and "
    "digs, or she turns back without laying.",
]

GUIDE_INTRO = (
    "Everything in this guide lives on the island or in its lagoon and can be found on foot "
    "or with a snorkel. Entries are in the order you might meet them, from the beach inland "
    "and then out to sea. Each tells you where to look in the game and something true about "
    "the species in nature. Tick the box when you have found it.")

TAGS = {"E": "Found only in the Seychelles", "I": "Brought by people", "R": "Rare here: a lucky find",
        "N": "Best at dusk, at night or after rain"}

SECTIONS = [
 ("Plants of the shore", "From the tide line to the edge of the forest.", [
  ("coconut", "Coconut palm", "Cocos nucifera", "", "Every shore.",
   "The palm of every tropical beach, leaning out toward the light. Its nut floats and "
   "still sprouts after months at sea, which is how it reached islands like this. Fallen "
   "nuts lie along the strand line. Now and then a ripe one drops with a thud."),
  ("naupaka", "Beach naupaka (veloutier)", "Scaevola taccada", "", "Top of the beaches, in front of the trees.",
   "A dense, salt-proof shrub with fleshy, bright green leaves in rosettes. Its small white "
   "flowers look torn in half, with all five petals on one side. The white berries float "
   "and are carried from island to island by the sea."),
  ("pemphis", "Pemphis (bwa d'amann)", "Pemphis acidula", "", "Rocky shores and the upper beach; gray-green and low.",
   "A wiry shrub with tiny silver-gray leaves that grows where little else can, on rock and "
   "coral rubble within reach of the spray. Its wood is among the hardest and heaviest of "
   "any shore plant and was prized for tool handles and boat pegs."),
  ("glory", "Beach morning glory", "Ipomoea pes-caprae", "", "Creeping over the sand of the start beach and the east beach.",
   "Long runners with pink trumpet flowers that open in the morning. The leaves are notched "
   "like a goat's footprint, which gave the plant its Latin name. It is one of the first "
   "plants to bind bare sand, and its seeds drift across whole oceans."),
  ("vacoa", "Screwpine (vacoa)", "Pandanus balfourii", "E", "Among the granite boulders and along the beaches.",
   "Not a pine and not a palm. It stands on stilt roots like a tent on its poles, with "
   "sword leaves set in a spiral and orange fruit heads that break into floating segments. "
   "The coastal vacoa of the granitic Seychelles grows nowhere else. The leaves were woven "
   "into mats and baskets."),
  ("mangrove", "Red mangrove", "Rhizophora mucronata", "", "Where the forest meets the sea; at high water the sea stands in its roots.",
   "A tree that lives with its feet in salt water, propped on arching stilt roots. Its "
   "seeds sprout while still on the tree and drop as green spears that plant themselves in "
   "the mud. The root cages shelter young fish; the mudskippers live beneath them."),
 ]),
 ("Plants of the forest", "Under the canopy and on the hill.", [
  ("takamaka", "Takamaka", "Calophyllum inophyllum", "", "The commonest forest tree; short thick trunk, heavy spreading limbs.",
   "The great shade tree of Seychelles beaches. The dark, glossy leaves have fine parallel "
   "veins like a feather, and the white flowers smell sweet. Its hard reddish timber built "
   "the islands' boats. The round green fruits are eaten by fruit bats."),
  ("badamier", "Badamier (Indian almond)", "Terminalia catappa", "", "Through the forest; branches in flat tiers like a pagoda.",
   "Easy to know by its shape: the branches leave the trunk in horizontal stories. Before "
   "they fall, the big leaves turn red, a rare sight of fall color in the tropics. Look "
   "for a few red leaves in every crown. The kernel of its corky, floating fruit tastes of almond."),
  ("jackfruit", "Jackfruit", "Artocarpus heterophyllus", "I", "Scattered in the forest. Look at the trunk, not the crown.",
   "The fruit grows straight out of the trunk and the thick branches, as few trees' do. It "
   "is the largest tree-borne fruit in the world and can weigh more than 30 kg. Brought "
   "from India long ago, it now grows half-wild on many Seychelles islands."),
  ("pisonia", "Pisonia (mapou)", "Pisonia grandis", "", "The grove on the southern headland, full of nesting seabirds.",
   "The seabirds' tree: massive pale trunks, soft brittle wood and big soft leaves. It "
   "grows on islands where birds nest and feeds on their guano. Its seeds are coated in "
   "glue and ride away on feathers, sometimes so many that a small bird cannot fly."),
  ("cocodemer", "Coco de mer", "Lodoicea maldivica", "E", "On the slopes of the hill. Female palms carry the huge green fruit.",
   "The palm of legend. It grows wild on only two islands in the world, Praslin and "
   "Curieuse, and bears the largest seed of any plant. Male and female are separate trees: "
   "the females carry two-lobed fruit that take six to seven years to ripen, the males "
   "arm-long catkins. The fan leaves are several meters across."),
  ("cocodemer_nut", "Coco de mer nut", "Lodoicea maldivica", "E", "On the ground under the female palms.",
   "The bare double nut, which can weigh 18 kg and more. For centuries it was known only "
   "from nuts washed up on distant shores, and people believed it grew on a tree at the "
   "bottom of the sea: hence 'coconut of the sea'. Around the parent stand young palms "
   "that have no trunk yet."),
  ("latanier", "Latanier feuille (thief palm)", "Phoenicophorium borsigianum", "E", "The commonest of the island's own palms, on the hill and in the forest.",
   "A palm whose broad leaf is not divided into leaflets but stays in one pleated piece, "
   "split only at the tips and edged with orange when young. The leaves were the classic "
   "thatch for Seychelles roofs. Young palms are armed with black spines; old ones lose them."),
  ("palmiste", "Palmiste (cabbage palm)", "Deckenia nobilis", "E", "The tallest palms, rising above the forest on a slender trunk.",
   "The giant among the Seychelles' own palms, reaching 30 meters and more. Its heart was "
   "eaten as 'millionaire's salad', a dish that costs the palm its life, and it became "
   "scarce for that reason. It is now protected. Young trees are covered in yellow spines."),
  ("fern", "Sword fern", "Nephrolepis biserrata", "", "The forest floor, by the thousand.",
   "Arching fronds with a row of leaflets on each side, the commonest fern of the forest "
   "floor. Ferns make no flowers or seeds. Look under a frond for the rows of brown dots "
   "that shed spores as fine as dust."),
  ("nestfern", "Bird's-nest fern", "Asplenium nidus", "", "Singly on the forest floor: a rosette of broad, undivided fronds.",
   "A funnel of glossy, strap-shaped fronds. The funnel catches falling leaves, which rot "
   "in its heart into the fern's own supply of compost. In wetter forest it perches high on "
   "branches, like a nest."),
 ]),
 ("Plants of the summit granite and the lagoon", "Rarities of the bare rock, a few steps south and west of the top, and one plant of the sea.", [
  ("pitcher", "Seychelles pitcher plant", "Nepenthes pervillei", "E", "Mats on the granite slabs just below the summit.",
   "A plant that eats insects. Each leaf ends in a goblet, yellow, orange or red, holding "
   "a pool of digestive fluid under a lid that keeps the rain out. It grows only on granite "
   "outcrops of Mahé and Silhouette, thousands of kilometers from its nearest relatives in "
   "Madagascar and Asia."),
  ("orchid", "Tropicbird orchid", "Angraecum eburneum", "", "On the summit granite: a fan of strap leaves with sprays of white flowers.",
   "The national flower of the Seychelles. Each waxy white flower carries a long spur like "
   "a tropicbird's tail streamer. It is scented at night, when the hawk moths that "
   "pollinate it are flying. Gray roots grip the bare rock."),
  ("vanilla", "Wild vanilla", "Vanilla phalaenopsis", "E", "Green ropes running over the summit rock, with a few large flowers.",
   "A leafless orchid. The thick green stems do the work of leaves and scramble over rock "
   "and bushes. The large white flowers with an apricot throat last only a day. It is a "
   "cousin of the vanilla of the kitchen, but its pods are not used."),
  ("seagrass", "Seagrass", "Thalassia and Thalassodendron", "", "Meadows on the sandy floor of the lagoon.",
   "Not seaweed but true flowering plants that returned to the sea, with roots, flowers and "
   "pollen that drifts under water. The meadows are the pasture of the green turtle and a "
   "nursery for young fish. In bright sun, strings of oxygen bubbles rise from the blades."),
 ]),
 ("Animals of the land", "Reptiles, a mammal and a frog.", [
  ("tortoise", "Aldabra giant tortoise", "Aldabrachelys gigantea", "E", "A pair grazes on the grassy ridge above the grotto.",
   "One of the last two kinds of giant tortoise on Earth. Males can weigh 250 kg and many "
   "live well beyond a hundred years. On Aldabra atoll some hundred thousand keep the grass "
   "cropped like a lawn. Come too close and it pulls in head and legs with a hiss."),
  ("skink", "Seychelles skink", "Trachylepis sechellensis", "E", "On rocks, the forest floor and the upper beach, in sunshine.",
   "A sleek bronze lizard with a dark stripe along each side, always busy. On seabird "
   "islands skinks live in astonishing numbers, feeding on fish dropped under the nests and "
   "on broken eggs. It hides when it rains."),
  ("gecko", "Day gecko", "Phelsuma astriata", "E", "On palm trunks, one to two meters up, by day.",
   "Emerald green with red spots, and active in daylight, unlike most geckos. It has no "
   "eyelids and cleans its eyes with its tongue. Besides insects it licks nectar and "
   "pollen, and so pollinates flowers. Millions of microscopic hairs under its toes hold it "
   "to the bark."),
  ("flyingfox", "Seychelles fruit bat", "Pteropus seychellensis", "N", "By day hanging in a tree below the ridge; at night in the air.",
   "A flying fox with a wingspan of more than a meter and a golden-furred head. It finds "
   "fruit by sight and smell, not by echo. By carrying seeds across the island it plants "
   "the forest. The roost is noisy with squabbling; at dusk the bats leave it one by one."),
  ("frog", "Seychelles frog", "Sooglossus sechellensis", "ER", "Seven on the whole island, by the stream's rock pools and the pond. Listen for a thin trill.",
   "A frog the size of a thumbnail from an ancient family found only on these islands. It "
   "needs no pond to breed: the eggs are laid on damp ground, and the tadpoles climb onto a "
   "parent's back and are carried there until they are froglets."),
 ]),
 ("Small animals of the land", "Crabs, insects and other creatures without a backbone. Many keep to the hours of dusk and night.", [
  ("ghostcrab", "Horned ghost crab", "Ocypode ceratophthalmus", "", "On the damp sand of the beaches. Each has a burrow of its own.",
   "Pale as the sand and very fast: it can run two meters in a second, sideways. Adults "
   "carry a pointed horn on top of each eye. The burrow goes down to damp sand, where the "
   "crab wets its gills. Round holes and scribbled tracks give it away."),
  ("rockcrab", "Rock crab", "Grapsus tenuicrustatus", "", "On the boulders at the waterline, in the splash of the waves.",
   "A dark, flat crab that clings to wave-washed granite and darts across it on the tips "
   "of its legs. It scrapes algae off the rock with its claws, as if with spoons. It never "
   "strays far from a crack to vanish into."),
  ("hermit", "Land hermit crab", "Coenobita rugosus", "N", "A few by day in the shade at the top of the beach; many from golden hour through the night and after rain.",
   "A crab that lives on land in a borrowed snail shell and must move to a larger one as "
   "it grows. It carries a little water in the shell to keep its gills wet. Come within a "
   "step and it snaps back inside; stand still and it looks out again."),
  ("spider", "Palm spider", "Nephila inaurata", "", "In golden webs strung between two trunks, above head height.",
   "The red-legged golden orb-weaver. The female spans a hand, and her silk shines yellow "
   "in the sun and is, weight for weight, stronger than steel. The tiny males live at "
   "the web's edge. It is harmless to people and stays in its web."),
  ("termites", "Tree termites", "Nasutitermes", "", "Dark nests on two palm trunks. Step close to see the workers on their runways.",
   "The nest is 'carton', chewed wood glued with saliva. Termites avoid the light, so the "
   "workers travel in covered runways that run down the trunk like veins. The soldiers "
   "have a nozzle for a head and squirt glue at ants."),
  ("millipede", "Seychelles giant millipede", "Sechelleptus seychellarum", "EN", "The forest floor from golden hour, at night and after rain. Some climb trunks.",
   "Glossy black and as long as a hand, with legs that move in waves. It eats fallen "
   "leaves and turns a large share of the island's leaf litter back into soil. It does not bite. "
   "Disturbed, it coils into a spiral."),
  ("snail", "Seychelles snail", "Stylodonta unidentata", "ERN", "Two on the island, on the forest floor at night or after rain.",
   "A large brown land snail found only in the Seychelles. Unlike most snails it lays no "
   "eggs but gives birth to a few fully formed young. It walks with its eye stalks out and "
   "takes all the time in the world."),
  ("dragonfly", "Wandering glider", "Pantala flavescens", "", "Golden dragonflies over the pond, the ridge and the summit.",
   "The greatest traveler among insects. Swarms cross the Indian Ocean from India to "
   "Africa on the monsoon winds, with the Seychelles on the way. The flight is a dart, a "
   "hover and a sharp turn. The young grow up in rain pools within weeks."),
  ("butterfly", "Plain tiger", "Danaus chrysippus", "", "Along the forest's edge near you, by day and in dry weather.",
   "Orange with black wing tips and a white bar. Its caterpillars feed on poisonous "
   "milkweeds and the butterfly keeps the poison, so birds leave it alone, and several "
   "harmless butterflies imitate it. It appears in Egyptian wall paintings 3,500 years old."),
  ("mudskipper", "Mudskipper", "Periophthalmus", "", "On the wet sand where the mangroves stand thickest. It follows the tide.",
   "A fish that spends most of its life out of water. It walks on its front fins, breathes "
   "through its wet skin and watches the world with eyes on top of its head. Come near and "
   "it skips into the water."),
 ]),
 ("Birds of the sea", "The colony on the southern headland is at its best by day. No bird here leaves its nest when you walk up.", [
  ("crestedtern", "Greater crested tern", "Thalasseus bergii", "", "Hovering and plunge-diving along the beaches.",
   "A big tern with a shaggy black crest and a long yellow bill. It patrols a few meters "
   "above the shallows, hovers, and drops head first for a fish. It flies out to sea at "
   "dusk and comes back at dawn."),
  ("noddy", "Brown noddy", "Anous stolidus", "", "On nests in the colony's trees and on its open ground.",
   "A chocolate-brown tern with a white cap: the pattern of other terns turned inside out. "
   "It is named for the nodding with which pairs greet each other. On islands without rats "
   "or cats it nests on the ground as readily as in trees."),
  ("whitetern", "White tern (fairy tern)", "Gygis alba", "", "Perched on bare twigs in the colony and flying over it.",
   "Pure white with large dark eyes. It builds no nest at all: the single egg is balanced "
   "in a hollow of a bare branch, and the chick hatches with strong claws and holds on. "
   "Pairs fly in close formation and peer at you from the air."),
  ("frigate", "Great frigatebird", "Fregata minor", "", "Soaring over the colony; males display in the treetops.",
   "Wings more than two meters across on a body that weighs little over a kilogram. It "
   "cannot land on the sea, since its feathers are not waterproof, so it snatches flying "
   "fish and robs other seabirds in the air. The male blows up his red throat sac like a "
   "balloon to court."),
  ("tropicbird", "White-tailed tropicbird", "Phaethon lepturus", "", "Around the summit granite, the east headland and the colony.",
   "White, with black wing bars and two tail streamers as long as its body. Pairs court in "
   "the air, one flying just above the other. It plunges for flying fish and squid. In the "
   "Seychelles it nests on the ground, here in nooks at the foot of boulders and trees. "
   "A chick alone on a nest is a ball of pale down."),
  ("sooty", "Sooty tern", "Onychoprion fuscatus", "", "The loud colony on the sand west of the grove.",
   "Black above, white below. Outside the breeding season it does not come to land for "
   "years and is thought to sleep on the wing. It cannot rest on the sea. On Bird Island, north of "
   "Mahé, hundreds of thousands of pairs nest a step apart. Each lays one speckled egg on "
   "bare sand; the chicks are balls of buff down."),
 ]),
 ("Birds of the shore and the land", "Waders at the water's edge, and four small birds that keep you company.", [
  ("turnstone", "Ruddy turnstone", "Arenaria interpres", "", "A small flock working the waterline near you.",
   "A stocky wader that does what its name says: it flips stones, shells and weed with its "
   "bill to catch what hides beneath. It breeds on Arctic tundra and flies to the tropics "
   "for the northern winter. It lets you come within a few steps."),
  ("crabplover", "Crab plover", "Dromas ardeola", "", "Three on the wet sand, a little way from you.",
   "Black and white, long-legged, with a heavy bill built for cracking crabs. It is the "
   "only wader that nests in burrows, in colonies on sandy islands around Arabia. Its "
   "visitors to the Seychelles come for the winter. It keeps a dozen meters from you."),
  ("heron", "Striated heron", "Butorides striata", "", "Hunched at the edge of the pond.",
   "A small, dark heron that stands still for minutes, then strikes. Some have been seen "
   "to drop an insect or a feather on the water as bait and wait for a fish to rise. Come "
   "close and it flies across the pond."),
  ("myna", "Common myna", "Acridotheres tristis", "I", "A pair strutting on open ground; loud and wary.",
   "Brown with a black head, yellow bill and yellow skin around the eye. It was brought "
   "from India in the eighteenth century to eat insect pests and is now everywhere in the "
   "Seychelles. It is clever, a good mimic, and a fierce rival of native birds for nest holes."),
  ("dove", "Barred ground dove", "Geopelia striata", "I", "Three pattering about the top of the beach.",
   "A small dove finely barred like a zebra, with a blue-gray face. It came from Southeast "
   "Asia and is tame almost to the point of walking over your feet. Its soft, rolling coo "
   "is one of the sounds of every Seychelles garden."),
  ("fody", "Seychelles fody (toc-toc)", "Foudia sechellarum", "E", "Three hopping on the forest floor, almost underfoot.",
   "A plain olive-brown weaver, the islands' own. It survived only on a few rat-free "
   "islands such as Cousin, and has since been carried to others. It eats insects, seeds "
   "and, given the chance, a seabird's egg. Males in breeding dress have a yellow face."),
  ("robin", "Seychelles magpie-robin", "Copsychus sechellarum", "ER", "Rarely, on the forest floor.",
   "Glossy black with a white shoulder patch, tame and curious. In the 1960s fewer than "
   "twenty were left, all on Frégate Island. Moving birds to rat-free islands has raised "
   "the number to several hundred. Meeting one here is as lucky as in life."),
 ]),
 ("Between the tides", "Life on the granite of the east headland. Come at half tide or low water.", [
  ("rockskipper", "Rockskipper", "Istiblennius and Alticus", "", "On the floor of the tide pools; it darts away when your shadow falls on the pool.",
   "A small blenny at home where the sea comes and goes. It can breathe air and hop from "
   "pool to pool over wet rock. It shares the pools with long-spined urchins in the deepest "
   "corners, a cushion star and nerite snails around the rim."),
  ("barnacles", "Barnacles", "Tetraclita and Chthamalus", "", "A belt on the headland and on every boulder the sea reaches.",
   "Not shellfish but relatives of crabs that glue themselves head-down to the rock and "
   "kick food into their mouths with feathery legs. Each kind keeps its own level: ribbed "
   "volcano barnacles in the middle of the tidal range, small star barnacles above them up "
   "to the high-water mark. Shown larger than life."),
 ]),
 ("Sharks, rays, turtles and dolphins", "The big animals of the lagoon. None of them takes any interest in you.", [
  ("blacktip", "Blacktip reef shark", "Carcharhinus melanopterus", "", "Young ones a meter long in the shallows, fins out of the water.",
   "The shark of knee-deep water. The young spend their first years in the shallows, where "
   "bigger sharks cannot follow, and patrol the water's edge with the tide. The black fin "
   "tips with a pale band beneath are unmistakable. It is shy."),
  ("tigershark", "Tiger shark", "Galeocerdo cuvier", "R", "Now and then a tall fin beyond the surf.",
   "One of the largest sharks of warm seas, four meters and more, with a broad blunt head. "
   "The dark bars that give it its name fade with age. It roams widely and eats almost "
   "anything. Here it only passes outside the reef."),
  ("eagleray", "Spotted eagle ray", "Aetobatus ocellatus", "", "A few together over sand and seagrass in the lagoon.",
   "Dark with white spots, a head like a duck's bill and a whip tail far longer than its "
   "body. It flies through the water on pointed wings and digs clams and crabs out of the "
   "sand, crushing them with plates of flat teeth."),
  ("manta", "Reef manta ray", "Mobula alfredi", "", "One cruises the deeper lagoon, sometimes with its wing tips out.",
   "Up to five meters across and harmless. It eats plankton, strained from the water it "
   "funnels into its mouth with the two flaps on its head. Mantas have the largest brain of "
   "any fish, and each can be told by the spots on its belly. It pays you no attention."),
  ("greenturtle", "Green turtle", "Chelonia mydas", "", "Grazing the seagrass off the start beach; up for air every minute or two.",
   "The grazer among sea turtles. Adults eat seagrass and algae, which tints their fat "
   "green and gave them their name. A female returns to nest on the coast where she herself "
   "hatched decades before. At night it sleeps on the bottom."),
  ("hawksbill", "Hawksbill turtle", "Eretmochelys imbricata", "", "The smaller turtle among the corals off the start beach.",
   "Told by its narrow, bird-like beak and the overlapping plates of its shell, the "
   "'tortoiseshell' for which it was hunted to the brink. It eats mainly sponges that few "
   "other animals can stomach. Critically endangered worldwide; the Seychelles are one of "
   "its strongholds."),
  ("nesting", "A hawksbill comes ashore", "Eretmochelys imbricata", "R", "Now and then, by day, on a beach near you. Tracks and a nest lie north of the start.",
   "Seychelles hawksbills nest in daylight, as almost no other sea turtles do. She hauls "
   "herself up the sand, digs, lays over a hundred eggs, covers them with flying sand and "
   "returns by another way: about five minutes here, an hour or more in life. Occasionally "
   "an old nest hatches and the young race for the sea."),
  ("dolphin", "Spinner dolphin", "Stenella longirostris", "R", "A pod passing outside the reef, by day; best from the reef edge or the hill.",
   "A small, slender dolphin famous for leaping clear and spinning up to seven times "
   "before it falls back. Pods rest near islands by day and hunt small fish and squid in "
   "deep water at night. Watch for dark backs rolling, then a splash."),
 ]),
 ("Fish of the reef", "Each of the reef's characters is at home in one place. The schools come to you when you wade.", [
  ("grouper", "Giant grouper", "Epinephelus lanceolatus", "", "One, 65 m out from the start beach, five meters down over open sand.",
   "The largest bony fish of coral reefs. It can grow to more than two and a half meters "
   "and 400 kg; this one measures 1.7 m. It hangs in place sculling with its fins and "
   "swallows fish, small sharks and lobsters whole. It moves aside without haste."),
  ("barracuda", "Great barracuda", "Sphyraena barracuda", "", "Two at the reef's edge, 90 m out, hanging under the surface.",
   "A silver pike of the sea, over a meter long, with a jutting lower jaw. It hunts by "
   "ambush, hanging motionless and then striking at great speed. It lets you come within "
   "four or five meters and then slides off to seaward."),
  ("titan", "Titan triggerfish", "Balistoides viridescens", "", "The shallower reef 30 m out to the south-west.",
   "The biggest triggerfish of the Indo-Pacific, to 75 cm. It swims by waving the fins on "
   "its back and belly while the body stays stiff, and tips head down to blow sand off its "
   "prey and crunch urchins and coral. It can lock its dorsal spine upright with a second "
   "spine, the 'trigger'."),
  ("clown", "Clown triggerfish", "Balistoides conspicillum", "", "Deeper reef to the north-west of the start beach.",
   "Black with large white spots below, a yellow net on the back and orange lips: one of "
   "the most strikingly patterned fish in the sea. The pattern may break up its outline "
   "against the reef. It is solitary and keeps a territory."),
  ("idol", "Moorish idol", "Zanclus cornutus", "", "In twos and threes at a coral head: 35 m out from the start beach, in the coral garden, and further north.",
   "White, black and yellow, with a back fin drawn out into a long white streamer. It is "
   "the only living species of its family. With its tube of a snout it picks sponges out "
   "of cracks in the reef. It keeps to pairs and small groups. Its young drift in the "
   "open sea for months, which has spread it from Africa to Mexico."),
  ("lionfish", "Lionfish", "Pterois miles", "", "A few, each hanging by a big coral with its fans spread.",
   "Striped red and white, with fins like fans and feathers. It herds small fish into a "
   "corner with its spread fins and swallows them in one gulp. The spines of its back are "
   "venomous in life, and the bold stripes are a warning. Here it is safe to watch."),
  ("honeycomb", "Honeycomb moray", "Gymnothorax favagineus", "", "Looking out of a hole in a lump of reef rock.",
   "Patterned like a giraffe. The steady opening and closing of its mouth is not a threat: "
   "it is how a moray pumps water over its gills. A second set of jaws in its throat shoots "
   "forward to pull prey down. It hunts at night, by smell."),
  ("giantmoray", "Giant moray", "Gymnothorax javanicus", "", "In its own hole in the reef rock; brown with dark freckles.",
   "The heaviest of all morays, to three meters and 30 kg. It is known to hunt together "
   "with groupers: the grouper signals with a shake of its head, the moray goes into the "
   "crevices, and whichever fish the prey flees toward gets the meal."),
  ("gardeneels", "Spotted garden eel", "Heteroconger hassi", "", "Colonies on bare sand, standing like a field of question marks.",
   "Each eel lives in a burrow it never fully leaves, its tail anchored in the sand, and "
   "picks plankton from the passing current. As you come near the whole colony sinks out of "
   "sight, and rises again behind you."),
  ("anemonefish", "Seychelles anemonefish", "Amphiprion fuscocaudatus", "E", "In the carpet anemones, a pair and their young in each.",
   "Found only in the Seychelles, Aldabra included. A coat of mucus protects it from the "
   "anemone's stinging tentacles. Every anemonefish starts life as a male; the largest of "
   "the group is the only female, and if she dies her mate changes sex and takes her place."),
  ("skunk", "Skunk anemonefish", "Amphiprion akallopisos", "", "In the long-tentacled magnificent anemones on top of the coral heads.",
   "Apricot-colored with a white stripe along the back, like a skunk's. Fish and anemone "
   "help each other: the fish is safe among the tentacles, and in return it drives off "
   "butterflyfish that would eat them and fans fresh water through its host."),
  ("bluetang", "Blue tang", "Paracanthurus hepatus", "", "Small schools traveling in file near the bottom.",
   "Royal blue with a black 'palette' on the side and a yellow tail. Like all surgeonfish "
   "it carries a spine as sharp as a scalpel on each side of the tail base. It grazes algae "
   "by day and wedges itself into the coral at night."),
  ("convict", "Convict surgeonfish", "Acanthurus triostegus", "", "Schools in the shallows off the start beach, traveling low over sand and seagrass.",
   "Pale with six thin black bars, like the stripes of an old prison uniform. One of the "
   "commonest surgeonfish of the Indian Ocean. It grazes fine algae, and travels in "
   "schools because numbers are its way in: a crowd simply overruns the damselfish "
   "that guard their algae gardens. Its tail spine is small."),
  ("sergeant", "Indo-Pacific sergeant", "Abudefduf vaigiensis", "", "Milling in mid-water in loose schools.",
   "Five dark bars on a silver body with a wash of yellow over the back: the stripes of a "
   "sergeant. It feeds on plankton in open water above the reef. The male guards a purple "
   "patch of eggs on the rock and chases off fish many times his size."),
  ("parrotfish", "Parrotfish", "Scarus and Chlorurus", "", "Two to four together, nosing down to graze. You hear them crunch.",
   "Its teeth are fused into a beak that scrapes algae off dead coral, rock and all. The "
   "rock is ground up and leaves the fish as fine white sand: a large parrotfish makes "
   "hundreds of kilograms of beach a year. Many sleep in a bubble of their own mucus."),
  ("chromis", "Blue-green chromis", "Chromis viridis", "", "A cloud hanging over one spot; it drops to the bottom when alarmed.",
   "A small damselfish that lives in shoals above branching corals, picking plankton from "
   "the water. At any alarm the whole shoal dives between the branches at once. It "
   "shimmers from pale green to sky blue as the light changes."),
 ]),
 ("Soft-bodied and spiny", "Animals of the reef without a backbone.", [
  ("octopus", "Day octopus", "Octopus cyanea", "", "In a den with shells and stones before the door; sometimes on top of its rock.",
   "An octopus that hunts by day and changes color and skin texture in an instant, turning "
   "dark or pale as you watch. The heap of empty shells at the entrance is its garbage "
   "dump. It has three hearts, blue blood and a brain that reaches into its arms."),
  ("jellyfish", "Moon jellyfish", "Aurelia aurita", "", "Small groups drifting a meter or two down in the west lagoon.",
   "A clear bell with four pale rings and a fringe of fine tentacles, beating slowly. It "
   "is 95 percent water and has no brain, heart or blood. It catches plankton in mucus on "
   "its bell. Its sting is too weak for most people to feel."),
  ("urchin", "Long-spined sea urchin", "Diadema setosum", "", "Clusters at the feet of the corals and in the tide pools.",
   "Black needles up to 30 cm long that turn toward any shadow passing over it: the whole "
   "skin can sense light. Look for the orange ring and five white dots on top. By grazing "
   "algae at night it keeps rock clear for young corals. Here it only looks dangerous."),
  ("bluestar", "Blue sea star", "Linckia laevigata", "", "On the coral rock; now and then an orange one.",
   "The bright blue comes from a pigment of its own, linckiacyanin. It creeps over the "
   "reef on hundreds of tube feet, grazing films of algae and bacteria, and can grow back a "
   "lost arm."),
  ("redknob", "Red-knobbed sea star", "Protoreaster lincki", "", "On open sand and in the seagrass.",
   "Cream with a net of scarlet ridges and thorn-like knobs: a sea star of the western "
   "Indian Ocean. Like other sea stars it has no brain and no blood. Sea water pumped "
   "through its body moves its feet, and it can push its stomach out to feed."),
  ("cushion", "Cushion star", "Culcita schmideliana", "", "On the reef and in the tide pools: a plump pentagon.",
   "A sea star whose arms have all but vanished into a body like an inflated cushion. It "
   "feeds on coral polyps and the film that grows on rock. Tiny shrimps often live on its "
   "underside."),
  ("clam", "Giant clam", "Tridacna maxima", "", "Set in the rock, bright mantle showing.",
   "The blue, green or gold of the mantle belongs to algae that live in the clam's flesh "
   "and feed it with sugar they make from sunlight, which is why it gapes toward the sun. "
   "No two mantles have the same pattern. It can live for decades in one place."),
 ]),
 ("Corals", "Each coral is a colony of thousands of tiny animals that build the reef. The coral garden lies 75 m straight out from the start beach.", [
  ("staghorn", "Staghorn coral", "Acropora", "", "Thickets across the lagoon, tan, yellow-brown, pale blue or pink.",
   "The fastest-growing corals, adding ten centimeters and more to a branch each year. "
   "Thickets shelter chromis and young fish. They are also the first to suffer when the "
   "sea becomes too warm, turning white as they lose their algae."),
  ("table", "Table coral", "Acropora", "", "Broad plates on a single stalk, from two meters down.",
   "A relative of the staghorns that spreads sideways into a flat plate to catch as much "
   "light as it can. The shade beneath is a resting place for fish. A big table may be "
   "decades old and two meters or more across."),
  ("finger", "Finger coral", "Porites cylindrica", "", "Upright fingers, yellow-tan or lavender.",
   "Smooth, blunt fingers closely set. Each tiny pit on the surface houses one polyp, an "
   "animal like a miniature anemone that puts out its tentacles at night to catch plankton."),
  ("cauliflower", "Cauliflower coral", "Pocillopora", "", "Also on the shallow reef crest; pink, cream or lavender heads.",
   "Compact, knobbly heads that stand up to waves, among the first corals to settle on bare "
   "rock. Small crabs live between the branches for life and defend their coral, even "
   "against the crown-of-thorns starfish."),
  ("boulder", "Boulder coral", "Porites", "", "Rounded domes; old ones a man's height across.",
   "Slow and long-lived: it grows about a centimeter a year, so a dome taller than a "
   "person is centuries old. Its skeleton carries yearly bands like tree rings, from which "
   "scientists read the history of the sea."),
  ("brain", "Brain coral", "Platygyra and Leptoria", "", "Domes with a maze of winding grooves.",
   "The polyps sit in rows in long shared valleys, and the ridges between them wind like "
   "the folds of a brain. The rounded, solid shape withstands storms that smash branching "
   "corals."),
  ("plate", "Scroll coral", "Turbinaria", "", "Whorls of thin plates, from two and a half meters down.",
   "Thin plates that curl into whorls like the petals of a rose or a head of lettuce. The "
   "shape gathers light where it is weak and lets sand slide off. In deeper water the "
   "plates lie flatter."),
  ("fire", "Fire coral", "Millepora", "", "Mustard-yellow blades with pale tips, in the shallows.",
   "Not a true coral but a relative of jellyfish and hydroids. In life its fine hairs give "
   "a burning sting to bare skin. Here it does not hurt, but learn the color and shape for "
   "real reefs."),
  ("leather", "Leather coral", "Sarcophyton", "", "Low folded lobes, cream, ochre or pale green.",
   "A soft coral without a stony skeleton, tough and leathery to the touch. When its "
   "polyps are out it looks furry; when they withdraw the surface is smooth. It defends "
   "itself with chemicals."),
  ("seafan", "Sea fan", "Gorgonian", "", "From three meters down; purple, orange or yellow.",
   "A flat, branched fan on a flexible horny skeleton. It always grows across the current, "
   "so that the water flows through it and each polyp can catch its share of plankton."),
 ]),
]

CREDITS = [
    "Idea and direction by Hanno Teeling.",
    "Concept extension and initial implementation by Claude Opus 5.5.",
    "Further substantial extension and refinement by Claude Fable 5.2.",
]
COLOPHON = ("The island itself is imagined: no chart of the Seychelles shows it. Its plants and "
            "animals are real, gathered from across the islands. "
            "Made with Godot 4.7. All pictures in this manual were taken in the game. Some small "
            "animals are shown larger than life so that they can be found. "
            "Tropical Island and this manual \u00a9 2026 Hanno Teeling, licensed under CC BY-NC-SA 4.0: "
            "share and adapt them with credit, not commercially, under the same license.")
