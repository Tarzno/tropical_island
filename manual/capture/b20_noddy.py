from gen import *
SB = N('ShoreBirds'); CO = "main.get_node('Colony')"
specs = [dict(name="warm", tod=0, target=V(-96, 6, -188), offs=[(5, 1, 5)], wait=200)]
loc = [(0.45, 0.12, -0.45), (-0.45, 0.12, -0.45), (0.6, 0.1, 0.0), (-0.6, 0.1, 0.0), (0.0, 0.15, -0.6), (0.4, 0.3, 0.4)]
for i in (0, 2, 3, 5, 7, 9): specs.append(dict(name="g%d" % i, target=arr(SB, 'ground_noddies', [i, 'node']), offs=loc, fov=30, local=True, lift=(0, 0.06, 0), wait=40))
for i in (1, 3, 6, 9, 12, 15): specs.append(dict(name="p%d" % i, target=MS + ".pick(%s, '_perches', 'kind', 'NoddyPerched', %d)" % (CO, i), offs=loc, fov=30, local=True, lift=(0, 0.06, 0), wait=40))
fl = [(1.2, 0.2, -1.2), (-1.2, 0.2, -1.2), (1.6, -0.2, 0.2), (0.2, 0.7, -1.5)]
for i in (0, 1, 2): specs.append(dict(name="f%d" % i, target=MS + ".pick(%s, '_flyers', 'kind', 'Noddy', %d)" % (CO, i), offs=fl, fov=30, local=True, wait=40))
build("nod", specs)
