from gen import *
RL = N('ReefLife'); SBD = N('Seabed'); CO = "main.get_node('Colony')"
def mp(node, prefix, i=0): return MS + ".mesh_pos(ls.get_node('%s'), '%s', %d)" % (node, prefix, i)
specs = [dict(name="warm", tod=1, target=V(0, 3, 0), offs=[(5, 1, 5)], wait=120)]
specs.append(dict(name="probe", setup=[MS + ".mm_meshes(ls.get_node('Ferns'))", MS + ".mm_meshes(ls.get_node('Debris'))", MS + ".mm_meshes(ls.get_node('Grass'))", MS + ".probe(%s, 'colonies', 1)" % RL, MS + ".g(%s, 'colonies', [0, 'eels', 0])" % RL], offs=[], target="null"))
for k, r, lift in (("CocoB", 6.5, 7.5), ("CocoA", 7.5, 10.5), ("LatA", 5.5, 6.5), ("LatB", 4.5, 4.5), ("PalmA", 8, 13), ("PalmB", 7, 9.5)):
    for i in (1, 2, 3, 4, 6, 8, 11, 14):
        specs.append(dict(name="%s_%d" % (k, i), target=mp("EndemicPalms", "endemic_palms_%sTrunk" % k, i), offs=[(r, -lift * 0.55, r * 0.4)], fov=55, lift=(0, lift, 0), wait=60))
for i in range(4): specs.append(dict(name="seed%d" % i, target=MS + ".mm_pos(ls.get_node('EndemicPalms/CocoSeed'), %d)" % i, offs=[(0.9, 0.5, 0.9), (-0.9, 0.5, 0.9)], fov=40))
for i in range(4): specs.append(dict(name="fruitold%d" % i, target=MS + ".mm_pos(ls.get_node('EndemicPalms/CocoFruitOld'), %d)" % i, offs=[(0.9, 0.5, 0.9)], fov=40))
for i in (0, 7, 15, 30, 60, 90): specs.append(dict(name="fern%d" % i, target=MS + ".fern(%d, 5)" % i, offs=[(1.3, 0.7, 1.3), (-1.3, 0.7, 1.3)], fov=45, lift=(0, 0.2, 0)))
for i in range(5): specs.append(dict(name="wtp%d" % i, target=MS + ".pick(%s, '_perches', 'kind', 'WhiteTernPerched', %d)" % (CO, i * 5 + 2), offs=[(0.8, 0.1, 0.8), (-0.8, 0.1, -0.8), (0.8, 0.1, -0.8)], fov=30))
build("b11", specs)
