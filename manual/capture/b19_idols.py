from gen import *
ID = N('Idols'); TI = N('Tide')
specs = [dict(name="trio", target=ID + ".marker(1)", offs=[(1.6, 0.3, 1.0)] * 6 + [(-0.9, 0.2, 1.3)] * 6, fov=40, stand=12, wait=75)]
specs.append(dict(name="pair", target=ID + ".marker(0)", offs=[(0.6, 0.1, 0.6), (-0.6, 0.1, -0.6), (-0.6, 0.1, 0.6), (0.6, 0.12, -0.6), (1.0, 0.2, 0.3), (-0.3, 0.2, 1.0)] * 2, fov=36, stand=12, wait=110))
specs.append(dict(name="near", target=ID + ".marker(0)", offs=[(1.4, 0.3, 0.8)] * 6, fov=45, stand=1.2, wait=60))
specs.append(dict(name="lowtrio", setup=[TI + ".set_state(3, true)"], setup_wait=200, target=ID + ".marker(1)", offs=[(1.6, 0.3, 1.0)] * 4 + [(2.5, 1.6, 2.5)] * 2, fov=40, stand=12, wait=90))
specs.append(dict(name="rep", setup=[ID + ".report()"], offs=[], target="null"))
build("i8", specs, pre=[MS + ".set('clear', 0.2)"])
