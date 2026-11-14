from gen import *
CR = N('Critters'); SL = N('SmallLand'); SBD = N('Seabed'); CO = "main.get_node('Colony')"; DO = N('Dolphins'); WE = N('Weather'); SB = N('ShoreBirds')
PE = V(-12, 1.2, 25)
specs = [dict(name="warm", tod=1, setup=[MS + ".player(%s)" % PE, MS + ".aim(%s, Vector3(3, 1, 3), 40, false)" % PE], setup_wait=400, target=PE, player=PE, offs=[(3, 1, 3)], wait=10)]
for i in range(6): specs.append(dict(name="bfly%d" % i, target=arr(CR, 'butterflies', [i, 'node']), player=PE, offs=[(0.12, 0.05, 0.12), (-0.12, 0.05, 0.12), (0.0, 0.16, 0.05), (0.3, 0.1, -0.3)], fov=32, wait=12))
specs.append(dict(name="probe", setup=[MS + ".probe(%s, 'butterflies', 6)" % CR, CR + ".leave_report()"], offs=[], target="null"))
for i in range(6): specs.append(dict(name="herm%d" % i, target=arr(SL, 'hermits', [i, 'node']), offs=[(0.22, 0.12, 0.22), (-0.22, 0.12, -0.22)], fov=30, stand=7))
PF = MS + ".tree('Taka0', 0) + Vector3(2.5, 0.2, 2.5)"
specs.append(dict(name="milli", setup=[MS + ".player(%s)" % PF, MS + ".aim(%s, Vector3(3, 1, 3), 40, false)" % PF, SL + ".set('force', 1)"], setup_wait=700, target=SL + ".nearest(1)", player=PF,
    offs=[(0.3, 0.3, 0.3), (-0.3, 0.3, 0.3), (0.3, 0.3, -0.3), (-0.3, 0.3, -0.3), (0.0, 0.5, 0.05), (0.45, 0.2, 0.0)], fov=34))
for k, nm in enumerate(["stag", "stag2", "boulder", "brain", "table", "fan", "cauli", "finger", "plate", "fire", "leather"]):
    for i in (0, 3):
        specs.append(dict(name="c_%s%d" % (nm, i), target=MS + ".coral(%d, %d)" % (k, i), offs=[(1.0, 0.7, 1.0), (-1.0, 0.7, -1.0), (1.6, 0.9, -1.6)], fov=45, lift=(0, 0.25, 0)))
specs.append(dict(name="dolph", setup=[DO + ".summon()"], setup_wait=420, target=arr(DO, '_pod', [3, 'node']), offs=[(9, 2.2, 9), (-9, 2.2, 9), (9, 2.2, -9), (-9, 2.2, -9)] * 2, fov=30, wait=45, stand=40))
for k in range(4): specs.append(dict(name="leap%d" % k, setup=[DO + ".leap_now(%d)" % (k + 1)], setup_wait=22 + 6 * k, target=arr(DO, '_pod', [k + 1, 'node']), offs=[(5, 1.0, 5)], fov=32, wait=4, stand=40))
specs.append(dict(name="frigate", setup=[CO + ".set('_frigate_timer', 0.0)"], setup_wait=300, target=arr(CO, '_frigates', [0, 'node']),
      offs=[(3.5, -1.0, -3.5), (-3.5, -1.0, -3.5), (4, 0.5, 0), (0.5, -3, -3), (0.5, 3.5, -2)], fov=30, local=True, wait=50))
for i in (0, 1, 2): specs.append(dict(name="frigd%d" % i, target=arr(CO, '_displays', [i, 'node']), offs=ring(1.1, 0.3) + [(2.5, 0.5, 0)], fov=32))
for i in (0, 2, 5): specs.append(dict(name="tropfly%d" % i, target=arr(SB, 'tropics', [i, 'root']), offs=[(1.3, 0.2, -1.3), (-1.3, 0.2, -1.3), (0.2, 0.8, -1.6), (1.8, -0.3, 0.3)], fov=30, local=True, wait=40))
J = []
def shot(name, pos, yaw, pitch=0, fov=70, frames=120): J.append({"kind": "shot", "pos": list(pos), "yaw": yaw, "pitch": pitch, "fov": fov, "frames": frames, "out": name + ".png"})
def ex(*e, frames=20): J.append({"kind": "expr", "frames": frames, "exprs": list(e)})
ex(MS + ".free_cam()"); J.append({"kind": "tod", "preset": 2, "frames": 240})
ex(WE + ".call_shower()"); ex(WE + ".jump(1080.0)", frames=300); ex(WE + ".report()", "main.get_node('DayCycle').get('to_sun')")
for y in (0, 45, 90, 135, 180, -135, -90, -45): shot("rb_%d" % (y % 360), (-110, 46.0, -12), y, 14, 80)
shot("rb_w", (-178, 3.0, -30), 90, 16, 80); shot("rb_b", (-7, 2.6, 30), 90, 20, 80)
ex(WE + ".jump(1130.0)", frames=300); ex(WE + ".report()")
for y in (45, 90, 135): shot("rc_%d" % y, (-110, 46.0, -12), y, 14, 80)
specs.append(dict(name="rainbow", jobs=J))
build("b10", specs, pre=[MS + ".set('clear', 0.2)"])
