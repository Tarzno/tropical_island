from gen import *
CR = N('Critters'); SL = N('SmallLand'); FA = "main.get_node('Fauna')"; LB = N('LandBirds'); CO = "main.get_node('Colony')"
fl = [(0.25, 0.08, -0.25), (-0.25, 0.08, -0.25), (0.35, 0.05, 0.0), (0.05, 0.25, -0.2)]
def stay(p): return [MS + ".player(%s)" % p, MS + ".aim(%s, Vector3(3, 1, 3), 40, false)" % p]
PB = MS + ".palm(30) + Vector3(-3, 0.2, 1)"
PP = V(-52, 3.6, -101)
PF = MS + ".tree('Taka0', 0) + Vector3(2.5, 0.2, 2.5)"
specs = [dict(name="warm", tod=1, target=V(0, 3, 0), offs=[(5, 1, 5)], wait=150),
 dict(name="tortoiseW", target=arr(IL, '_torts', [0, 'node']), offs=ring(2.2, 0.6), fov=34, lift=(0, 0.3, 0)),
 dict(name="tortoiseW1", target=arr(IL, '_torts', [1, 'node']), offs=ring(2.0, 0.6), fov=34, lift=(0, 0.3, 0))]
for i in (0, 5, 9): specs.append(dict(name="skinkW%d" % i, target=arr(IL, '_skinks', [i, 'node']), offs=ring(0.4, 0.2), fov=30, stand=6))
for i in (0, 2, 3, 5): specs.append(dict(name="spider%d" % i, target=arr(CR, 'webs', [i, 'spider']), offs=[(0, 0, 0.9), (0, 0, -0.9), (0.5, 0.1, 0.8), (-0.5, 0.1, -0.8)], fov=34, local=True, stand=8))
for i in (1, 2, 3): specs.append(dict(name="orchid%d" % i, target=arr(SL, 'orchid_spots', [i]), offs=ring(0.8, 0.25)[:2], fov=38, lift=(0, 0.45, 0)))
for i in (0, 1, 2): specs.append(dict(name="vanilla%d" % i, target=arr(SL, 'vanilla_spots', [i]), offs=ring(0.28, 0.15)[:2] + [(1.2, 0.6, 1.2)], fov=38, lift=(0, 0.1, 0)))
for i in (0, 1, 2): specs.append(dict(name="butterfly%d" % i, target=arr(CR, 'butterflies', [i, 'node']), offs=ring(0.14, 0.07)[:2] + fl[:2], fov=32, stand=8, wait=15))
for i in (2, 3, 4): specs.append(dict(name="hermit%d" % i, target=arr(SL, 'hermits', [i, 'node']), offs=ring(0.2, 0.1)[:2], fov=30, stand=6))
for i in (1, 2, 3, 6, 9): specs.append(dict(name="wternp%d" % i, target=MS + ".pick(%s, '_perches', 'kind', 'WhiteTernPerched', %d)" % (CO, i), offs=ring(1.3, 0.2)[:2], fov=30))
specs.append(dict(name="gecko", setup=stay(PB), setup_wait=500, target=IL + ".gecko_node()", player=PB,
    offs=ring(0.3, 0.05) + [(0.45, 0, 0), (-0.45, 0, 0), (0, 0, 0.45), (0, 0, -0.45)], fov=30))
for i in (0, 1, 2): specs.append(dict(name="dragon%d" % i, setup=stay(PP) if i == 0 else None, setup_wait=300, target=arr(CR, 'dragonflies', [i, 'node']), player=PP, offs=fl, fov=30, local=True, wait=25))
specs.append(dict(name="milli", setup=stay(PF) + [SL + ".set('force', 1)"], setup_wait=700, target=SL + ".nearest(1)", player=PF, offs=ring(0.22, 0.1), fov=30))
specs.append(dict(name="snail", target=SL + ".nearest(2)", player=PF, offs=ring(0.2, 0.1), fov=30))
specs.append(dict(name="climber", target=SL + ".climber()", player=PF, offs=[(0.4, 0, 0), (-0.4, 0, 0), (0, 0, 0.4), (0, 0, -0.4)], fov=30))
specs.append(dict(name="fody", setup=[LB + ".summon()"], setup_wait=600, target=arr(LB, 'groups', [2, 'birds', 0, 'root']), player=PF, offs=ring(0.3, 0.12), fov=30, lift=(0, 0.05, 0)))
specs.append(dict(name="fodyb", target=arr(LB, 'groups', [2, 'birds', 1, 'root']), player=PF, offs=ring(0.3, 0.12), fov=30, lift=(0, 0.05, 0)))
PR = V(-50, 14, -4)
specs.append(dict(name="bats", tod=3, setup=stay(PR), setup_wait=1500, target=arr(FA, '_bats', [0, 'node']), player=PR, offs=[(1.2, 0.2, -1.2), (-1.2, 0.2, -1.2), (1.6, 0.0, 0.0), (0.2, 0.9, -1.4)], fov=32, local=True, wait=40))
specs.append(dict(name="bats1", target=arr(FA, '_bats', [1, 'node']), player=PR, offs=[(1.2, 0.2, -1.2), (-1.2, 0.2, -1.2)], fov=32, local=True, wait=40))
specs.append(dict(name="probe", setup=[MS + ".probe(%s, '_bats')" % FA, IL + ".gecko_node()", SL + ".report()"], offs=[], target="null"))
build("b5", specs)
