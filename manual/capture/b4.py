from gen import *
def mp(node, prefix, i=0): return MS + ".mesh_pos(ls.get_node('%s'), '%s', %d)" % (node, prefix, i)
def tree(kind, i=0): return MS + ".tree('%s', %d)" % (kind, i)
specs = []
def add(name, target, r, h, lift, fov=50, n=4):
    specs.append(dict(name=name, target=target, offs=ring(r, h)[:n], fov=fov, lift=(0, lift, 0), wait=70))
specs.append(dict(name="warm", tod=1, target="Vector3(0, 3, 0)", offs=[(5, 1, 5)], wait=120))
for i in (0, 30, 90): add("palm%d" % i, MS + ".palm(%d)" % i, 7, 1.0, 4.5, 55, 2)
for k in ("Taka0", "Taka1", "Bad0", "Bad1", "Pis0", "Pis1"):
    add(k, tree(k, 0), 9, 0.5, 4.0, 55, 2); add(k + "b", tree(k, 3), 9, 0.5, 4.0, 55, 2)
for k in ("Jack0", "Jack1"):
    add(k, tree(k, 0), 4.5, 0.3, 2.5, 50, 4); add(k + "b", tree(k, 2), 4.5, 0.3, 2.5, 50, 2)
for k, r, lift in (("CocoB", 7, 5), ("CocoA", 8, 6), ("LatA", 6, 4), ("LatB", 5, 3), ("PalmA", 9, 8), ("PalmB", 8, 6)):
    add(k, mp("EndemicPalms", "endemic_palms_%sTrunk" % k, 0), r, 0.3, lift, 55, 2)
    add(k + "b", mp("EndemicPalms", "endemic_palms_%sTrunk" % k, 5), r, 0.3, lift, 55, 2)
add("CocoBnuts", mp("EndemicPalms", "endemic_palms_CocoBTrunk", 0), 3.0, -2.0, 8.0, 45, 4)
add("CocoAcat", mp("EndemicPalms", "endemic_palms_CocoATrunk", 0), 3.0, -2.5, 11.0, 45, 2)
add("CocoJ", mp("EndemicPalms", "endemic_palms_CocoJ0Crown", 0), 4.0, 1.0, 1.5, 50, 2)
add("CocoSeed", "ls.get_node('EndemicPalms/CocoSeed')", 1, 1, 0, 50, 1)
for k, r, lift in (("Vacoa0", 4.5, 2.0), ("Vacoa2", 4.5, 2.0)):
    add(k, mp("Vacoas", "forest_trees_%sBark" % k, 0), r, 0.5, lift, 50, 2); add(k + "b", mp("Vacoas", "forest_trees_%sBark" % k, 4), r, 0.5, lift, 50, 2)
for k in ("Mangrove0", "Mangrove1"):
    add(k, mp("Mangroves", "mangroves_%sBark" % k, 0), 5, 0.6, 1.6, 50, 2); add(k + "b", mp("Mangroves", "mangroves_%sBark" % k, 4), 5, 0.6, 1.6, 50, 2)
for k in ("A", "E", "F", "B", "D"):
    add("Bush" + k, mp("BushClusters", "bushes_Bush%sTwigs" % k, 0), 2.6, 0.5, 0.7, 45, 2); add("Bush" + k + "b", mp("BushClusters", "bushes_Bush%sTwigs" % k, 9), 2.6, 0.5, 0.7, 45, 2)
add("glory", MS + ".on_ground(-4, 17)", 1.4, 0.7, 0.1, 45, 4)
add("glory2", MS + ".on_ground(-6, 12)", 0.7, 0.4, 0.1, 40, 2)
specs.append(dict(name="probe", setup=[MS + ".kids(ls.get_node('Ferns'))", MS + ".kids(ls.get_node('Grass'))", MS + ".kids(ls.get_node('MorningGloryEast'))", MS + ".kids(ls.get_node('Debris'))", "ls.get_node('EndemicPalms/CocoSeed').get_class()", "ls.get('_fern_cells').size()", "ls.get('_fern_cells').keys().slice(0, 12)", "ls.get('_fern_cells').values().slice(0, 3)"], offs=[], target="null"))
build("b4", specs)
