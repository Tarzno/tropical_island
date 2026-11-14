from gen import *
J = [{"kind": "shot", "pos": [-45, 400, 0], "yaw": 0, "pitch": -90, "fov": 70, "frames": 200, "ortho": 560, "out": "map.png"},
     {"kind": "tod", "preset": 1, "frames": 200},
     {"kind": "shot", "pos": [-45, 400, 0], "yaw": 0, "pitch": -90, "fov": 70, "frames": 200, "ortho": 560, "out": "map_pm.png"}]
build("b13", [dict(name="scenes", jobs=J)], res="2000x2000")
