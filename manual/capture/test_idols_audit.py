from gen import *
ID = N('Idols'); FI = "main.get_node('Fish')"
specs = [dict(name="audit", setup=["add_tool('res://tools/coral_audit.gd', 'CoralAudit')"], setup_wait=30, offs=[], target="null")]
# the trio in the coral garden, watched for a while from one side, then from above
specs.append(dict(name="trio", target=ID + ".marker(1)", offs=[(1.5, 0.35, 0.9)] * 10, fov=40, stand=12, wait=100))
specs.append(dict(name="trioup", target=ID + ".marker(1)", offs=[(0.02, 2.2, 0.0)] * 8, fov=45, stand=12, wait=45))
specs.append(dict(name="pair", target=ID + ".marker(0)", offs=[(-0.9, 0.2, 1.2)] * 8 + [(0.5, 0.1, 0.5), (-0.5, 0.1, -0.5)], fov=40, stand=12, wait=100))
# a snorkeler's view: from the surface above the first group
specs.append(dict(name="snork", target=ID + ".marker(0)", offs=[(1.2, 2.6, 1.2), (-1.5, 2.8, 0.5)], fov=60, stand=1.5, wait=120))
for i in (1, 6):
    specs.append(dict(name="convict%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, '_schools', [%d, 'fish', 0]), 'pos', {off}, {fov})" % (FI, i), offs=ring(0.5, 0.1) + ring(1.1, 0.25), fov=34, wait=40))
    specs.append(dict(name="convictb%d" % i, target="x", aimx=MS + ".aim_d(" + MS + ".g(%s, '_schools', [%d, 'fish', 2]), 'pos', {off}, {fov})" % (FI, i), offs=ring(0.8, 0.15), fov=34, wait=40))
specs.append(dict(name="rep", setup=[ID + ".report()", "main.get_node('CoralAudit').report()", "main.get_node('CoralAudit').pair_report()"], offs=[], target="null"))
build("i3", specs, pre=[MS + ".set('clear', 0.2)"])
