from gen import *
RL = N('ReefLife'); SBD = N('Seabed')
specs = []
for i in (0, 2, 3): specs.append(dict(name="eel%d" % i, target=arr(RL, 'colonies', [i, 'pos']), offs=[(1.0, 0.25, 0.3), (-0.3, 0.25, 1.0), (0.7, 0.2, -0.7), (1.6, 0.3, 0.0)], fov=32, lift=(0, 0.22, 0), stand=22))
for i in range(10): specs.append(dict(name="cush%d" % i, target=MS + ".mm_find(%s, %s, %d, 20.0, 95.0)" % (SBD, MS + ".g(%s, '_stars', [2, 0])" % SBD, i * 7), offs=[(0.3, 0.35, 0.3)], fov=36))
for i in range(6): specs.append(dict(name="bluest%d" % i, target=MS + ".mm_find(%s, %s, %d, 20.0, 95.0)" % (SBD, MS + ".g(%s, '_stars', [0, 0])" % SBD, i * 11), offs=[(0.3, 0.35, 0.3)], fov=36))
for i in (0, 1, 2, 4): specs.append(dict(name="tab%d" % i, target=MS + ".coral(4, %d)" % i, offs=[(2.0, 0.5, 0.8), (-0.8, 0.6, 2.0)], fov=45, lift=(0, 0.3, 0)))
for i in (1, 2): specs.append(dict(name="plate%d" % i, target=MS + ".coral(8, %d)" % i, offs=[(1.6, 1.0, 0.8), (-0.8, 1.0, 1.6)], fov=45, lift=(0, 0.2, 0)))
for i in (1, 2, 5): specs.append(dict(name="bould%d" % i, target=MS + ".coral(2, %d)" % i, offs=[(2.4, 1.2, 1.2), (-1.2, 1.2, 2.4)], fov=45, lift=(0, 0.3, 0)))
for i in (1, 2): specs.append(dict(name="leath%d" % i, target=MS + ".coral(10, %d)" % i, offs=[(0.9, 0.7, 0.5), (-0.5, 0.7, 0.9)], fov=45, lift=(0, 0.1, 0)))
for i in range(6): specs.append(dict(name="clam%d" % i, target=arr(SBD, 'clam_spots', [i * 3]), offs=[(0.5, 0.4, 0.5)], fov=36))
specs.append(dict(name="grass", target=MS + ".on_ground(26, 40, 0.2)", offs=[(1.5, 0.35, 1.0), (-1.0, 0.35, 1.5), (1.2, 0.5, -1.2)], fov=50))
build("b12", specs, pre=[MS + ".set('clear', 0.2)"])
