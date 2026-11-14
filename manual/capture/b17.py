from gen import *
J = []
def ex(*e, frames=20): J.append({"kind": "expr", "frames": frames, "exprs": list(e)})
def aim(name, target, off, fov=45, lift=-40, frames=140):
    ex(MS + ".set('lift', Vector3(0, %s, 0))" % lift, MS + ".player(null)", MS + ".aim(%s, %s, %s, false)" % (target, V(*off), fov), frames=3); ex(MS + ".save('%s.png')" % name, frames=frames)
for tod in (0, 1, 2):
    J.append({"kind": "tod", "preset": tod, "frames": 200})
    aim("cov%d_se" % tod, V(-45, 5, 0), (480, 250, 420), 50, -90)
    aim("cov%d_s" % tod, V(-70, 5, 0), (120, 170, 470), 50, -70)
    aim("cov%d_e" % tod, V(-70, 5, 0), (420, 150, 90), 55, -90)
    aim("cov%d_ne" % tod, V(-70, 5, 0), (330, 200, -420), 50, -90)
    aim("cov%d_beach" % tod, V(-30, 5, 10), (150, 45, 110), 60, -30)
build("b17", [dict(name="scenes", jobs=J)], res="1240x1754")
