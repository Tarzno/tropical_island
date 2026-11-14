from gen import *
import calendar
DC = "main.get_node('DayCycle')"
B = "ls.get_node('GrottoBeam').material_override.get_shader_parameter('strength')"
J = []
def ex(*e, frames=40): J.append({"kind": "expr", "frames": frames, "exprs": list(e)})
J.append({"kind": "shot", "pos": [-78, 9.6, 50], "yaw": 90, "pitch": 10, "fov": 80, "frames": 60, "out": "in.png"})
for h in (8.5, 9.2, 9.8, 10.5, 11.3, 12.35):
    J.append({"kind": "clock", "hour": h, "frames": 60}); ex(B)
J.append({"kind": "tod", "preset": 0, "frames": 60}); ex(B)
J.append({"kind": "tod", "preset": 1, "frames": 60}); ex(B)
ex(DC + ".set('sun_unix', %d.0)" % calendar.timegm((2027, 6, 21, 8, 0, 0)))
for h in (9.8, 12.35):
    J.append({"kind": "clock", "hour": h, "frames": 60}); ex(B, DC + ".get('to_sun')")
J.append({"kind": "tod", "preset": 0, "frames": 60}); ex(B)
J.append({"kind": "tod", "preset": 3, "frames": 60}); ex(DC + ".get('to_sun')", DC + ".get('shown_hour')", "main.get_node('IslandLife/Tide').report()")
build("sun3", [dict(name="s", jobs=J)])
