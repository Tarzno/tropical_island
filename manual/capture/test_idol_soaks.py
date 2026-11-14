from gen import *
ID = N('Idols'); TI = N('Tide')
runs = [ID + ".soak(1800.0, 0)"] * 3 + [ID + ".soak(1800.0, 1)", ID + ".soak(1800.0, 2)"]
specs = [dict(name="p0", setup=[TI + ".set_state(2, true)"], setup_wait=60, setup_after=runs + [TI + ".set_state(3, true)"], after_wait=30, offs=[], target="null"),
         dict(name="p1", setup=runs + [TI + ".set_state(1, true)"], setup_wait=30, offs=[], target="null"),
         dict(name="p2", setup=runs, setup_wait=30, offs=[], target="null")]
build("i7", specs)
