from gen import *
ID = N('Idols'); FI = "main.get_node('Fish')"
specs = [dict(name="probe", setup=[ID + ".soak(1800.0, 0)", ID + ".soak(900.0, 1)", ID + ".soak(900.0, 2)", ID + ".set('mates_apart', false)", ID + ".soak(1800.0, 0)", ID + ".set('mates_apart', true)"], setup_wait=60, offs=[], target="null")]
specs.append(dict(name="pair", target=ID + ".marker(0)", offs=[(0.55, 0.1, 0.55), (-0.55, 0.1, -0.55), (-0.55, 0.1, 0.55), (0.55, 0.12, -0.55), (0.9, 0.2, 0.3), (-0.3, 0.2, 0.9), (0.9, 0.15, -0.3), (-0.9, 0.2, 0.3)] * 2, fov=36, stand=12, wait=110))
specs.append(dict(name="south", target=ID + ".marker(2)", offs=[(0.6, 0.1, 0.6), (-0.6, 0.1, -0.6), (-0.6, 0.1, 0.6), (0.6, 0.12, -0.6)] * 2, fov=36, stand=12, wait=110))
for i in (1, 6):
    specs.append(dict(name="convict%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, '_schools', [%d, 'fish', 0]), 'pos', {off}, {fov})" % (FI, i), offs=ring(0.55, 0.1) + ring(1.0, 0.2), fov=34, wait=60))
    specs.append(dict(name="convictb%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, '_schools', [%d, 'fish', 3]), 'pos', {off}, {fov})" % (FI, i), offs=ring(0.8, 0.15), fov=34, wait=60))
specs.append(dict(name="night", tod=4, setup=[MS + ".aim(" + ID + ".marker(0), Vector3(1.5, 0.4, 1.5), 40, false)"], setup_wait=3000, target=ID + ".marker(0)", offs=[(0.6, 0.15, 0.6)], fov=36, stand=12, wait=60))
specs.append(dict(name="rep", setup=[ID + ".report()", FI + ".night_report()"], offs=[], target="null"))
build("i4", specs, pre=[MS + ".set('clear', 0.2)"])
