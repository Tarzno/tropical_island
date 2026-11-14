from gen import *
SB = N('ShoreBirds'); LB = N('LandBirds'); CO = "main.get_node('Colony')"; FA = "main.get_node('Fauna')"
fl = [(1.6, 0.3, -1.6), (-1.6, 0.3, -1.6), (2.2, 0.1, 0.0), (0.3, 1.2, -2.2)]
specs = [
 dict(name="tern", tod=1, target=arr(FA, '_terns', [0, 'node']), offs=fl, fov=30, local=True, wait=50),
 dict(name="tern1", target=arr(FA, '_terns', [1, 'node']), offs=fl, fov=30, local=True, wait=50),
 dict(name="noddy", target=MS + ".pick(%s, '_perches', 'kind', 'NoddyPerched', 0)" % CO, offs=ring(0.7, 0.15), fov=30),
 dict(name="noddy4", target=MS + ".pick(%s, '_perches', 'kind', 'NoddyPerched', 4)" % CO, offs=ring(0.7, 0.15), fov=30),
 dict(name="wtern", target=MS + ".pick(%s, '_perches', 'kind', 'WhiteTernPerched', 0)" % CO, offs=ring(0.7, 0.15), fov=30),
 dict(name="wtern4", target=MS + ".pick(%s, '_perches', 'kind', 'WhiteTernPerched', 4)" % CO, offs=ring(0.7, 0.15), fov=30),
 dict(name="wternfly", target=MS + ".pick(%s, '_flyers', 'kind', 'WhiteTern', 0)" % CO, offs=fl, fov=30, local=True, wait=50),
 dict(name="noddyfly", target=MS + ".pick(%s, '_flyers', 'kind', 'Noddy', 0)" % CO, offs=fl, fov=30, local=True, wait=50),
 dict(name="frigdisp", target=arr(CO, '_displays', [0, 'node']), offs=ring(1.6, 0.3), fov=32),
 dict(name="frigdisp1", target=arr(CO, '_displays', [1, 'node']), offs=ring(1.6, 0.3), fov=32),
 dict(name="frigate", setup=[CO + ".set('_frigate_timer', 0.0)"], setup_wait=240, target=arr(CO, '_frigates', [0, 'node']),
      offs=[(3.5, -1.0, -3.5), (-3.5, -1.0, -3.5), (4, 0.5, 0), (0.5, -3, -3)], fov=30, local=True, wait=50),
 dict(name="tropicnest", target=arr(SB, 'sitters', [0, 'root']), offs=ring(0.8, 0.3), fov=32, lift=(0, 0.1, 0)),
 dict(name="tropicnest1", target=arr(SB, 'sitters', [1, 'root']), offs=ring(0.8, 0.3), fov=32, lift=(0, 0.1, 0)),
 dict(name="tropicfly", target=arr(SB, 'tropics', [0, 'root']), offs=fl, fov=30, local=True, wait=50),
 dict(name="tropicchick", target=arr(SB, 'chicks', [0, 'node']), offs=ring(0.45, 0.2), fov=30),
 dict(name="gnoddy", target=arr(SB, 'ground_noddies', [0, 'node']), offs=ring(0.6, 0.25), fov=30),
 dict(name="gnoddy1", target=arr(SB, 'ground_noddies', [1, 'node']), offs=ring(0.6, 0.25), fov=30),
 dict(name="sootywide", target=SB + ".sooty_center", offs=ring(4.5, 1.3), fov=45),
 dict(name="sooty", target=arr(SB, 'sooty_standing', [0, 'root']), offs=ring(0.7, 0.25), fov=30, lift=(0, 0.1, 0)),
 dict(name="sootysit", target=arr(SB, 'sooty', [0, 'pos']), offs=ring(0.7, 0.3), fov=30, lift=(0, 0.1, 0)),
 dict(name="sootychick", target=arr(SB, 'sooty_chicks', [0, 'pos']), offs=ring(0.5, 0.25), fov=30),
 dict(name="turnstone", target=arr(SB, 'flocks', [0, 'birds', 0, 'root']), offs=ring(0.55, 0.2), fov=30, stand=11, lift=(0, 0.08, 0)),
 dict(name="crabplover", target=arr(SB, 'flocks', [1, 'birds', 0, 'root']), offs=ring(0.9, 0.3), fov=30, stand=18, lift=(0, 0.2, 0)),
 dict(name="heron", target=arr(SB, 'heron', ['root']), offs=ring(1.0, 0.35), fov=30, stand=16, lift=(0, 0.25, 0)),
]
for i, nm in enumerate(["mynah", "dove", "fody", "robin"]):
    specs.append(dict(name=nm, setup=[LB + ".summon()"] if i == 0 else None, setup_wait=600,
        target=arr(LB, 'groups', [i, 'birds', 0, 'root']), offs=ring(0.45, 0.18), fov=30, stand=7, lift=(0, 0.08, 0)))
specs.append(dict(name="probe", setup=[MS + ".probe(%s, 'heron')" % SB, MS + ".probe(%s, 'groups')" % LB, MS + ".g(%s, 'groups', [0, 'birds', 0])" % LB, MS + ".g(%s, 'flocks', [0, 'birds', 0])" % SB, MS + ".g(%s, 'groups', [0, 'prm'])" % LB, MS + ".g(%s, 'groups', [1, 'prm'])" % LB, MS + ".g(%s, 'groups', [2, 'prm'])" % LB, MS + ".g(%s, 'groups', [3, 'prm'])" % LB], offs=[], target="null"))
build("b2", specs)
