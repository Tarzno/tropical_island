from gen import *
def mp(node, prefix, i=0): return MS + ".mesh_pos(ls.get_node('%s'), '%s', %d)" % (node, prefix, i)
specs = [dict(name="warm", tod=1, target=V(0, 3, 0), offs=[(5, 1, 5)], wait=120)]
for k, r, lift in (("CocoB", 6.5, 7.5), ("CocoA", 7.5, 10.5), ("LatA", 5.5, 6.5), ("LatB", 4.5, 4.5)):
    for i in (1, 2, 3, 4, 6, 8, 11, 14, 17):
        specs.append(dict(name="%s_%d" % (k, i), target=mp("EndemicPalms", "endemic_palms_%sTrunk" % k, i), offs=[(r, -lift * 0.55, r * 0.4)], fov=55, lift=(0, lift, 0), wait=60))
build("b14", specs)
