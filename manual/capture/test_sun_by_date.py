from gen import *
import calendar
DC = "main.get_node('DayCycle')"
ex = []
for nm, (y, m, d) in [("today 12 Nov", (2026, 11, 12)), ("21 Dec", (2026, 12, 21)), ("20 Mar", (2027, 3, 20)), ("21 Jun", (2027, 6, 21)), ("23 Sep", (2027, 9, 23))]:
    u = calendar.timegm((y, m, d, 8, 0, 0))
    ex += [DC + ".set('sun_unix', %d.0)" % u, DC + ".sun_decl()", DC + ".sun_at(12.35)", DC + ".hour_of_elev(0.0)", DC + ".sun_at(%s.hour_of_elev(0.0))" % DC, DC + ".sun_at(9.75)", DC + ".preset_today(1)['azim']", DC + ".preset_today(2)['azim']", DC + ".preset_today(3)['azim']", DC + ".preset_today(1)['hour']"]
ex += [DC + ".set('sun_unix', -1.0)"]
build("sun2", [dict(name="p", setup=ex, setup_wait=30, offs=[], target="null")])
