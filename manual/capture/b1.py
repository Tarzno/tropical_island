from gen import *
CR = N('Critters'); SL = N('SmallLand'); FA = "main.get_node('Fauna')"
def arr(node, prop, keys): return MS + ".g(%s, '%s', %s)" % (node, prop, json.dumps(keys).replace('"', "'"))
ring = lambda r, h: [(r, h, r), (-r, h, r), (r, h, -r), (-r, h, -r)]
specs = [
 dict(name="tortoise", tod=1, target=arr(IL, '_torts', [0, 'node']), offs=ring(1.5, 0.5), fov=38, lift=(0, 0.3, 0)),
 dict(name="tortoise2", target=arr(IL, '_torts', [1, 'node']), offs=ring(1.3, 0.4), fov=38, lift=(0, 0.25, 0)),
 dict(name="skink", target=arr(IL, '_skinks', [0, 'node']), offs=ring(0.22, 0.12), fov=30, stand=6),
 dict(name="skink3", target=arr(IL, '_skinks', [3, 'node']), offs=ring(0.22, 0.12), fov=30, stand=6),
 dict(name="ghostcrab", target=arr(FA, '_crabs', [0, 'node']), offs=ring(0.3, 0.15), fov=32, stand=9),
 dict(name="ghostcrab1", target=arr(FA, '_crabs', [1, 'node']), offs=ring(0.3, 0.15), fov=32, stand=9),
 dict(name="rockcrab", target=arr(CR, 'rock_crabs', [0, 'node']), offs=ring(0.3, 0.15), fov=32, stand=9),
 dict(name="rockcrab5", target=arr(CR, 'rock_crabs', [5, 'node']), offs=ring(0.3, 0.15), fov=32, stand=9),
 dict(name="spider", target=arr(CR, 'webs', [0, 'spider']), offs=[(0.5, 0, 0), (-0.5, 0, 0), (0, 0, 0.5), (0, 0, -0.5), (1.6, -0.4, 0), (0, -0.4, 1.6)], fov=35, stand=8),
 dict(name="termites", target=arr(CR, 'termite_nests', [0]), offs=ring(0.9, 0.0), fov=40, stand=3),
 dict(name="mudskipper", target=arr(CR, 'mudskippers', [0, 'node']), offs=ring(0.2, 0.09), fov=30, stand=7),
 dict(name="frog", target=arr(CR, 'frogs', [0, 'node']), offs=ring(0.1, 0.06), fov=26, stand=5),
 dict(name="frog1", target=arr(CR, 'frogs', [1, 'node']), offs=ring(0.1, 0.06), fov=26, stand=5),
 dict(name="roost", target=arr(CR, 'roost', [0, 'root']), offs=ring(1.1, -0.5), fov=38, lift=(0, -0.2, 0)),
 dict(name="roostwide", target=CR + ".roost_center", offs=ring(6, -4), fov=45),
 dict(name="butterfly", target=arr(CR, 'butterflies', [0, 'node']), offs=ring(0.25, 0.12), fov=32, stand=8),
 dict(name="hermit", target=arr(SL, 'hermits', [0, 'node']), offs=ring(0.16, 0.08), fov=30, stand=6),
 dict(name="hermit1", target=arr(SL, 'hermits', [1, 'node']), offs=ring(0.16, 0.08), fov=30, stand=6),
 dict(name="pitcher", target=arr(SL, 'pitcher_spots', [0]), offs=ring(0.45, 0.3), fov=38, lift=(0, 0.1, 0)),
 dict(name="pitcher5", target=arr(SL, 'pitcher_spots', [5]), offs=ring(0.45, 0.3), fov=38, lift=(0, 0.1, 0)),
 dict(name="orchid", target=arr(SL, 'orchid_spots', [0]), offs=ring(0.5, 0.3), fov=38, lift=(0, 0.15, 0)),
 dict(name="orchid1", target=arr(SL, 'orchid_spots', [1]), offs=ring(0.5, 0.3), fov=38, lift=(0, 0.15, 0)),
 dict(name="vanilla", target=arr(SL, 'vanilla_spots', [0]), offs=ring(0.6, 0.4), fov=38, lift=(0, 0.05, 0)),
 dict(name="vanilla1", target=arr(SL, 'vanilla_spots', [1]), offs=ring(0.6, 0.4), fov=38, lift=(0, 0.05, 0)),
]
build("b1", specs)
