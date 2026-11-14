from gen import *
PL = N('PoolLife'); BN = N('Barnacles'); NE = N('Nesting'); TI = N('Tide')
specs = [dict(name="low", setup=[TI + ".set_state(3, true)", BN + ".finish()"], setup_wait=200, target=V(-183, 0.5, -24), offs=[(6, 4, 6), (-3, 5, 8)], fov=55)]
for i in range(4): specs.append(dict(name="pool%d" % i, target="ls.get('tide_pools')[%d]['at']" % i, offs=ring(1.6, 1.1)[:2], fov=45, stand=5))
for i in (0, 1, 3): specs.append(dict(name="skipper%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, 'pools', [%d, 'fish', 0]), 'pos', {off}, {fov})" % (PL, i), offs=ring(0.22, 0.2)[:3], fov=32, stand=6))
for i in (0, 100, 400, 700): specs.append(dict(name="barn%d" % i, target=arr(BN, 'spots', [i]), offs=ring(0.35, 0.15)[:2], fov=34))
specs.append(dict(name="barnw", target=BN + ".nearest(Vector3(-183, 0, -24))", offs=ring(0.5, 0.25) + ring(1.5, 0.6)[:2], fov=36))
specs.append(dict(name="probe", setup=[MS + ".g(%s, 'pools', [0, 'fixed'])" % PL, MS + ".g(%s, 'pools', [0, 'fish', 0])" % PL, BN + ".report()", PL + ".report()"], offs=[], target="null"))
PS = V(-6, 1.5, 28)
specs.append(dict(name="nestsite", setup=[TI + ".set_state(0, true)"], target=arr(NE, 'nests', [1, 'pos']), offs=ring(2.2, 1.3)[:2], fov=45))
specs.append(dict(name="nest", setup=[MS + ".player(%s)" % PS, MS + ".aim(%s, Vector3(3, 1, 3), 40, false)" % PS], setup_wait=30,
    setup_after=[NE + ".summon()", NE + ".set('time_scale', 2.5)"], after_wait=300, target=NE + ".turtle", player=PS,
    offs=[(1.6, 0.5, 1.6), (-1.6, 0.6, 1.2), (1.2, 0.9, -1.6), (-1.4, 0.5, -1.4)] * 4, fov=36, wait=420))
specs.append(dict(name="hatch", setup=[NE + ".set('time_scale', 1.0)", NE + ".hatch_now()"], setup_wait=240, target="x", player=PS,
    aimx=MS + ".aim_d(" + MS + ".g(%s, 'hatch', [12]), 'pos', {off}, {fov})" % NE, offs=ring(0.5, 0.3) + ring(1.0, 0.5), fov=36, wait=150))
specs.append(dict(name="probe2", setup=[MS + ".probe(%s, 'hatch')" % NE, NE + ".get('visits')", MS + ".probe(%s, 'st')" % NE], offs=[], target="null"))
build("b7", specs)
