from gen import *
PL = N('PoolLife'); TI = N('Tide')
PB = MS + ".palm(30) + Vector3(-4, 0.2, 2)"
specs = [dict(name="warm", tod=1, setup=[MS + ".player(%s)" % PB, MS + ".aim(%s, Vector3(3, 1, 3), 40, false)" % PB], setup_wait=2500, target=PB, player=PB, offs=[(3, 1, 3)], wait=10)]
specs.append(dict(name="gecko", target=IL + ".gecko_node()", player=PB, local=True,
    offs=[(0, 0.4, 0), (0.25, 0.3, 0), (-0.25, 0.3, 0), (0, 0.3, 0.25), (0, 0.3, -0.25), (0.3, 0.2, 0.3), (-0.3, 0.2, -0.3), (0.0, 0.7, 0.3)], fov=30, wait=30))
specs.append(dict(name="geckow", target=IL + ".gecko_node()", player=PB, offs=ring(0.4, 0.05) + [(0.5, 0, 0), (-0.5, 0, 0), (0, 0, 0.5), (0, 0, -0.5)], fov=30, wait=30))
for i in (0, 40, 200, 600): specs.append(dict(name="nestfern%d" % i, target=MS + ".mm_find(ls.get_node('Ferns'), 'ferns_NestFern', %d)" % i, offs=[(1.0, 0.6, 1.0), (-1.0, 0.6, 1.0)], fov=45, lift=(0, 0.25, 0)))
specs.append(dict(name="low", setup=[TI + ".set_state(3, true)"], setup_wait=200, target=V(-183, 0.5, -24), offs=[(6, 4, 6)], fov=55))
for p in range(3):
    for i in range(3): specs.append(dict(name="fix%d_%d" % (p, i), target=arr(PL, 'pools', [p, 'fixed', i]), offs=[(0.3, 0.3, 0.3), (-0.2, 0.15, 0.2)], fov=34, stand=6))
build("b16", specs)
