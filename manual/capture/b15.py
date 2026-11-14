from gen import *
RL = N('ReefLife'); SBD = N('Seabed')
specs = []
for i in (0, 2, 3): specs.append(dict(name="eel%d" % i, target=arr(RL, 'colonies', [i, 'pos']), offs=[(1.0, 0.25, 0.3), (-0.3, 0.25, 1.0), (0.7, 0.2, -0.7), (1.6, 0.3, 0.0)], fov=32, lift=(0, 0.22, 0), stand=22))
for i in range(10): specs.append(dict(name="cush%d" % i, target=MS + ".mm_find(%s, %s, %d, 20.0, 95.0)" % (SBD, MS + ".g(%s, '_stars', [2, 0])" % SBD, i * 7), offs=[(0.3, 0.35, 0.3)], fov=36))
for i in range(4): specs.append(dict(name="bluest%d" % i, target=MS + ".mm_find(%s, %s, %d, 20.0, 95.0)" % (SBD, MS + ".g(%s, '_stars', [0, 0])" % SBD, i * 11), offs=[(0.3, 0.35, 0.3)], fov=36))
build("b15", specs, pre=[MS + ".set('clear', 0.2)"])
