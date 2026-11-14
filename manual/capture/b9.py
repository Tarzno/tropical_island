from gen import *
DC = "main.get_node('DayCycle')"; FA = "main.get_node('Fauna')"
J = []
def shot(name, pos, yaw, pitch=0, fov=70, frames=120, **kw):
    d = {"kind": "shot", "pos": list(pos), "yaw": yaw, "pitch": pitch, "fov": fov, "frames": frames, "out": name + ".png"}; d.update(kw); J.append(d)
def ex(*e, frames=20): J.append({"kind": "expr", "frames": frames, "exprs": list(e)})
def tod(p): J.append({"kind": "tod", "preset": p, "frames": 240})
def aim(name, target, off, fov=45, frames=120):
    ex(MS + ".set('lift', Vector3(0, 0, 0))", MS + ".player(null)", MS + ".aim(%s, %s, %s, false)" % (target, V(*off), fov), frames=3); ex(MS + ".save('%s.png')" % name, frames=frames)
aim("aerial1", V(-45, 5, 0), (300, 150, 260), 42); aim("aerial2", V(-45, 5, 0), (260, 120, -300), 42); aim("aerial3", V(-45, 5, 0), (-300, 130, 200), 42); aim("aerial4", V(-45, 5, 20), (330, 90, 40), 42)
ex(MS + ".free_cam()")
shot("stream1", (-71, 8.4, -86), 50, -25, 65); shot("stream2", (-80, 11.5, -74), 55, -20, 65); shot("pond2", (-50.5, 6.0, -100.5), 47, -24, 60)
tod(2); shot("golden", (-3, 2.2, 42), 15, -3, 68); shot("golden2", (-7, 2.6, 30), -70, -2, 72); shot("golden3", (2, 2.0, 5), -150, 0, 68); shot("golden4", (-110, 46.0, -12), -90, -8, 75)
tod(3); shot("sunset", (-7, 2.6, 30), -90, 4, 70); shot("sunset2", (-3, 2.2, 42), -60, 4, 68); shot("sunset3", (-110, 46.0, -12), -90, -4, 75); shot("sunset4", (2, 2.0, 5), -120, 4, 68)
tod(4); ex(DC + ".set_moon(1)", frames=240)
ex(DC + ".get('moon_elev')", DC + ".get('MOON')", DC + ".get('to_sun')")
for y in (-90, -45, 0, 90, 180): shot("fullmoon_%d" % y, (-7, 2.6, 30), y, 22, 80)
shot("fullmoon_up", (-7, 2.6, 30), -90, 60, 85); shot("moonpath", (2, 2.2, 28), -90, 12, 60); shot("moonpath2", (2, 2.2, 28), -90, 30, 70)
# flying foxes in the night air
ex(MS + ".player(Vector3(-50, 14, -4))", MS + ".aim(Vector3(-50, 16, -4), Vector3(3, 0, 3), 50, false)", frames=700)
for k, off in enumerate([(1.2, 0.2, -1.2), (-1.2, 0.2, -1.2), (1.6, 0.0, 0.0), (0.2, 0.9, -1.4), (0.3, -0.8, -1.4), (1.5, 0.3, 1.0)]):
    ex(MS + ".aim(%s, %s, 34, true)" % (arr(FA, '_bats', [0, 'node']), V(*off)), frames=3); ex(MS + ".save('bat_%d.png')" % k, frames=30)
ex(MS + ".probe(%s, '_bats')" % FA); ex(MS + ".free_cam()")
ex(DC + ".set_moon(3)", frames=240); ex(DC + ".get('moon_elev')")
for y in (-90, 0, 90, 180): shot("cres_%d" % y, (-7, 2.6, 30), y, 20, 80)
ex(DC + ".set_moon(4)", frames=240)
for y in (-90, 0, 90, 180): shot("stars_%d" % (y + 90), (-110, 46.0, -12), y, 35, 85)
shot("stars_up", (-110, 46.0, -12), 0, 75, 90)
ex(DC + ".glow_report()"); ex("%s.toggle_glow() if not %s.glow_wanted() else 0" % (DC, DC), frames=600); ex(DC + ".glow_report()")
shot("glow1", (1.5, 1.8, 30), 10, -12, 72); shot("glow2", (3, 2.4, 10), -20, -14, 72); shot("glow4", (4, 1.2, 25), 0, -8, 72); shot("glow5", (5, 1.5, -20), 170, -10, 72)
ex(DC + ".set_moon(1)", frames=240); shot("glowmoon1", (1.5, 1.8, 30), 10, -10, 72); shot("glowmoon2", (3, 2.2, 12), -50, -4, 72)
build("b9", [dict(name="scenes", jobs=J)])
