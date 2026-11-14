from gen import *
SE = "main.get_node('SeaLife')"; TU = N('Turtles'); RL = N('ReefLife'); FI = "main.get_node('Fish')"; SBD = N('Seabed')
BA = N('Barracudas'); JE = N('Jellyfish'); DO = N('Dolphins')
specs = [
 dict(name="pup", target=arr(SE, '_pups', [0, 'node']), offs=[(1.2, 0.9, 1.2), (-1.2, 0.9, -1.2), (0.9, 0.0, 0.9), (-0.9, 0.0, 0.9)], fov=35, stand=12),
 dict(name="pup1", target=arr(SE, '_pups', [1, 'node']), offs=[(1.2, 0.9, 1.2), (-1.2, 0.9, -1.2), (0.9, 0.0, 0.9), (-0.9, 0.0, 0.9)], fov=35, stand=12),
 dict(name="manta", target=SE + ".get('_manta')", offs=[(4.5, 1.2, 4.5), (-4.5, 1.2, 4.5), (4, -1.2, -4), (-4, -1.0, -4)], fov=40),
 dict(name="rays", setup=[SE + ".summon_rays(3)"], target=arr(SE, '_rays', [0, 'node']), offs=ring(1.6, 0.7), fov=38),
 dict(name="shark", setup=[SE + ".summon_shark()"], setup_wait=200, target=SE + ".get('_shark')", offs=[(5, 1.6, 5), (-5, 1.6, 5), (4, -0.4, 4), (-4, -0.4, -4)], fov=38),
 dict(name="green", target=arr(TU, 'turtles', [0, 'node']), offs=ring(1.2, 0.35), fov=36),
 dict(name="hawks", target=arr(TU, 'turtles', [1, 'node']), offs=ring(1.1, 0.3), fov=36),
 dict(name="anem0", target=arr(RL, 'anemones', [0, 'pos']), offs=ring(0.55, 0.3), fov=34, lift=(0, 0.08, 0)),
 dict(name="anem1", target=MS + ".pick(%s, 'anemones', 'kind', 1, 0, 'pos')" % RL, offs=ring(0.55, 0.3), fov=34, lift=(0, 0.08, 0)),
 dict(name="eels", target=arr(RL, 'colonies', [0, 'pos']), offs=ring(1.5, 0.45), fov=38, lift=(0, 0.15, 0), stand=16),
 dict(name="moray0", target=arr(RL, 'morays', [0, 'node']), offs=ring(0.5, 0.2), fov=34),
 dict(name="moray1", target=arr(RL, 'morays', [1, 'node']), offs=ring(0.5, 0.2), fov=34),
 dict(name="octo", target=arr(RL, 'octopuses', [0, 'node']), offs=ring(0.6, 0.3), fov=34),
 dict(name="octo1", target=arr(RL, 'octopuses', [1, 'node']), offs=ring(0.6, 0.3), fov=34),
 dict(name="lion", target=arr(RL, 'lionfish', [0, 'pos']), offs=ring(0.5, 0.12), fov=34),
 dict(name="lion1", target=arr(RL, 'lionfish', [1, 'pos']), offs=ring(0.5, 0.12), fov=34),
 dict(name="grouper", target=arr(RL, 'grouper', ['node']), offs=ring(1.9, 0.4), fov=36),
 dict(name="titan", target=arr(RL, 'triggers', [0, 'node']), offs=ring(0.9, 0.2), fov=34),
 dict(name="clown", target=arr(RL, 'triggers', [1, 'node']), offs=ring(0.6, 0.15), fov=34),
 dict(name="barra", target=arr(BA, 'fish', [0, 'node']), offs=ring(1.5, 0.3), fov=36),
 dict(name="jelly", target=JE + ".marker(0)", offs=[(0.5, -0.15, 0.5), (-0.5, -0.15, 0.5), (0.5, 0.1, -0.5), (-0.9, -0.3, -0.9)], fov=34),
 dict(name="urchin", target=arr(SBD, 'urchin_spots', [0]), offs=ring(0.5, 0.3), fov=36),
 dict(name="clam", target=arr(SBD, 'clam_spots', [0]), offs=ring(0.4, 0.3), fov=36),
 dict(name="clam1", target=arr(SBD, 'clam_spots', [1]), offs=ring(0.4, 0.3), fov=36),
]
for i in range(8): specs.append(dict(name="star%d" % i, target=arr(SBD, 'star_spots', [i * 9]), offs=[(0.35, 0.3, 0.35)], fov=36))
for i in range(7): specs.append(dict(name="school%d" % i, target=arr(FI, '_schools', [i, 'center']), offs=[(1.1, 0.25, 1.1), (-1.1, 0.25, -1.1)], fov=38))
specs.append(dict(name="dolph", setup=[DO + ".summon()"], setup_wait=300, target=arr(DO, '_pod', [3, 'node']), offs=[(7, 1.6, 7), (-7, 1.6, 7), (7, 1.6, -7), (-7, 1.6, -7)], fov=32, wait=60))
specs.append(dict(name="dolphleap", setup=[DO + ".leap_now(3)"], setup_wait=25, target=arr(DO, '_pod', [3, 'node']), offs=[(6, 1.2, 6)], fov=32, wait=20))
specs.append(dict(name="probe", setup=[MS + ".probe(%s, 'fish')" % BA, MS + ".g(%s, '_schools', [0, 'prm'])" % FI, MS + ".g(%s, '_schools', [1, 'prm'])" % FI, MS + ".g(%s, '_schools', [2, 'prm'])" % FI, MS + ".g(%s, '_schools', [3, 'prm'])" % FI, MS + ".g(%s, '_schools', [4, 'prm'])" % FI, MS + ".g(%s, '_schools', [5, 'prm'])" % FI, MS + ".g(%s, '_schools', [6, 'prm'])" % FI, DO + ".report()", MS + ".probe(%s, '_pod', 7)" % DO], offs=[], target="null"))
build("b3", specs, pre=[MS + ".set('clear', 0.25)"])
