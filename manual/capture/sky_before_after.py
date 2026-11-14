import sys
from gen import *
DC = "main.get_node('DayCycle')"
tag = sys.argv[1]; extra = sys.argv[2:] 
J = []
def shot(name, pos, yaw, pitch=0, fov=70, frames=90):
    J.append({"kind": "shot", "pos": list(pos), "yaw": yaw, "pitch": pitch, "fov": fov, "frames": frames, "out": name + ".png"})
def ex(*e, frames=20): J.append({"kind": "expr", "frames": frames, "exprs": list(e)})
if extra: ex(*extra)
BEACH = ((-7, 2.6, 30), -70, -6); UP = ((-7, 2.6, 30), -90, 40); SUMMIT = ((-110, 46.0, -12), -90, -6); INL = ((-12, 2.2, 22), 100, 0)
for h in (6.6, 8.0, 9.8, 12.35, 15.0, 17.0, 18.1):
    J.append({"kind": "clock", "hour": h, "frames": 60})
    ex(DC + ".sun_at(%s)" % h, DC + ".get('to_sun')", DC + ".get('moon_elev')")
    shot("c%04.1f_beach" % h, *BEACH); shot("c%04.1f_summit" % h, *SUMMIT)
    if h in (9.8,): shot("c%04.1f_grotto" % h, (-78, 9.6, 50), 90, 10, 80)
    if h in (12.35,): shot("c%04.1f_down" % h, (-7, 2.6, 30), 0, -50, 75)
for p in (0, 1, 2, 3):
    J.append({"kind": "tod", "preset": p, "frames": 60})
    ex(DC + ".get('to_sun')", DC + ".get('shown_hour')")
    shot("t%d_beach" % p, *BEACH); shot("t%d_summit" % p, *SUMMIT)
    if p == 0: shot("t0_grotto", (-78, 9.6, 50), 90, 10, 80)
J.append({"kind": "tod", "preset": 4, "frames": 60}); ex(DC + ".set_moon(1)", frames=120)
ex(DC + ".get('moon_elev')", DC + ".get('shown_hour')")
shot("n_full_sea", (-7, 2.6, 30), -90, 22, 80); shot("n_full_south", (-110, 46.0, -12), 0, 20, 85); shot("n_full_north", (-110, 46.0, -12), 180, 20, 85)
for h in (20.0, 23.0, 2.0):
    J.append({"kind": "clock", "hour": h, "frames": 80}); ex(DC + ".get('moon_elev')")
    shot("m%04.1f_west" % h, (-110, 46.0, -12), -90, 30, 85); shot("m%04.1f_east" % h, (-110, 46.0, -12), 90, 30, 85); shot("m%04.1f_south" % h, (-110, 46.0, -12), 0, 20, 85)
build("sun_" + tag, [dict(name="s", jobs=J)])
