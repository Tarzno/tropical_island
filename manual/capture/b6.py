from gen import *
RL = N('ReefLife'); FI = "main.get_node('Fish')"; SBD = N('Seabed')
specs = []
for i in range(6): specs.append(dict(name="moray%d" % i, target=arr(RL, 'morays', [i, 'node']), offs=ring(0.9, 0.3), fov=30))
for i in (0, 300, 900): specs.append(dict(name="urchin%d" % i, target=arr(SBD, 'urchin_spots', [i]), offs=ring(1.0, 0.6)[:2], fov=38))
for i in (3, 4, 6, 8, 11, 14, 17, 21, 25, 30, 36, 44): specs.append(dict(name="star%d" % i, target=arr(SBD, 'star_spots', [i]), offs=[(0.3, 0.35, 0.3)], fov=36))
for i in (0, 1, 2, 3, 4):
    specs.append(dict(name="school%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, '_schools', [%d, 'fish', 0]), 'pos', {off}, {fov})" % (FI, i), offs=ring(0.5, 0.1), fov=34, wait=30))
    specs.append(dict(name="schoolb%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, '_schools', [%d, 'fish', 1]), 'pos', {off}, {fov})" % (FI, i), offs=ring(0.8, 0.15)[:2], fov=34, wait=30))
for k, (x, z) in enumerate([(74, -30), (76, -15), (75, 0), (74, 12), (78, -22), (72, -8), (70, 5), (77, 8)]):
    specs.append(dict(name="garden%d" % k, target=MS + ".on_ground(%d, %d, 0.3)" % (x, z), offs=[(2.2, 0.5, 0.6), (-0.6, 0.6, 2.2)], fov=55))
for k in range(24):
    specs.append(dict(name="coral%02d" % k, target=arr(SBD, 'big_corals', [k * 131, 0]), offs=[(1.3, 0.9, 1.3)], fov=42, lift=(0, 0.3, 0)))
specs.append(dict(name="grass", target=MS + ".on_ground(24, 42, 0.2)", offs=ring(2.0, 0.5)[:2], fov=50))
specs.append(dict(name="probe", setup=[MS + ".g(%s, '_schools', [0, 'fish', 0])" % FI], offs=[], target="null"))
build("b6", specs, pre=[MS + ".set('clear', 0.25)"])
