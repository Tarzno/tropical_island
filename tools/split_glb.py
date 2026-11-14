"""Splits a binary glTF whose nodes all lie at the scene's top (one mesh each, no skins, no
animations, no images) into several smaller .glb files without touching a byte of the mesh
data: every part gets a share of the nodes, all the materials, and its own repacked buffer.

    python3 tools/split_glb.py assets/models/leaves.glb 4 build/leaves_before_split.glb

writes leaves.glb (the first part, under the old name: scenes that instance it stay as they
are), leaves_b.glb, leaves_c.glb, leaves_d.glb, and moves the whole file to the third
argument first (keep it out of the project: Godot would import it). The nodes are dealt out
largest first to the lightest part, so the parts come out nearly equal.

Why: GitHub refuses files over 100 MiB and warns from 50 (leaves.glb was 160 MB; 2026-11-13).
scripts/world.gd: _join_leaves() puts the parts together again at start-up. Prove that
nothing changed with tools/leaf_dump.gd before and after.
"""
import json, os, shutil, struct, sys


def read_glb(path):
    with open(path, "rb") as f:
        magic, ver, _ = struct.unpack("<III", f.read(12))
        assert magic == 0x46546C67 and ver == 2, "not a glTF 2 binary"
        n, t = struct.unpack("<II", f.read(8))
        assert t == 0x4E4F534A
        j = json.loads(f.read(n))
        n, t = struct.unpack("<II", f.read(8))
        assert t == 0x004E4942
        return j, f.read(n)


def write_glb(path, j, blob):
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    blob += b"\0" * (-len(blob) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)


def mesh_accessors(mesh):
    out = []
    for p in mesh["primitives"]:
        assert set(p) <= {"attributes", "indices", "material", "mode"}, p.keys()
        out += list(p["attributes"].values())
        if "indices" in p:
            out.append(p["indices"])
    return out


def part(j, blob, nodes):
    """A glTF of these nodes (indices into j["nodes"], kept in their old order)."""
    out = {k: j[k] for k in ("asset", "extensionsUsed", "materials") if k in j}
    acc_map, bv_map = {}, {}
    out["accessors"], out["bufferViews"], out["meshes"], out["nodes"] = [], [], [], []
    data = bytearray()
    for ni in sorted(nodes):
        node = j["nodes"][ni]
        mesh = json.loads(json.dumps(j["meshes"][node["mesh"]]))
        for a in mesh_accessors(mesh):
            if a in acc_map:
                continue
            acc = dict(j["accessors"][a])
            b = acc["bufferView"]
            if b not in bv_map:
                bv = dict(j["bufferViews"][b])
                start = bv.get("byteOffset", 0)
                data += b"\0" * (-len(data) % 4)
                bv["byteOffset"] = len(data)
                data += blob[start:start + bv["byteLength"]]
                bv_map[b] = len(out["bufferViews"])
                out["bufferViews"].append(bv)
            acc["bufferView"] = bv_map[b]
            acc_map[a] = len(out["accessors"])
            out["accessors"].append(acc)
        for p in mesh["primitives"]:
            p["attributes"] = {k: acc_map[v] for k, v in p["attributes"].items()}
            if "indices" in p:
                p["indices"] = acc_map[p["indices"]]
        out["nodes"].append({"mesh": len(out["meshes"]), "name": node["name"]})
        out["meshes"].append(mesh)
    out["buffers"] = [{"byteLength": len(data) + (-len(data) % 4)}]
    out["scene"] = 0
    out["scenes"] = [{"name": j["scenes"][0]["name"], "nodes": list(range(len(out["nodes"])))}]
    return out, bytes(data)


def main():
    src, n, keep = sys.argv[1], int(sys.argv[2]), sys.argv[3]
    j, blob = read_glb(src)
    assert set(j) <= {"asset", "extensionsUsed", "scene", "scenes", "nodes", "materials", "meshes", "accessors", "bufferViews", "buffers"}, j.keys()
    assert len(j["buffers"]) == 1 and len(j["scenes"]) == 1
    assert sorted(j["scenes"][0]["nodes"]) == list(range(len(j["nodes"])))
    assert all(set(nd) == {"mesh", "name"} for nd in j["nodes"]), "a node with a transform or children"
    size = {}
    for i, nd in enumerate(j["nodes"]):
        size[i] = sum(j["bufferViews"][j["accessors"][a]["bufferView"]]["byteLength"]
                      for a in set(mesh_accessors(j["meshes"][nd["mesh"]])))
    bins = [[] for _ in range(n)]
    for i in sorted(size, key=lambda i: (-size[i], i)):
        min(bins, key=lambda b: sum(size[k] for k in b)).append(i)
    assert not os.path.exists(keep), keep + " exists already"
    shutil.move(src, keep)
    stem = src[:-4]
    for k, nodes in enumerate(bins):
        path = src if k == 0 else "%s_%s.glb" % (stem, "abcdefgh"[k])
        g, data = part(j, blob, nodes)
        write_glb(path, g, bytearray(data))
        print("%s: %d nodes, %.1f MB: %s" % (path, len(nodes), os.path.getsize(path) / 1e6,
                                             " ".join(j["nodes"][i]["name"] for i in sorted(nodes))))
    print("the whole file is kept as " + keep)


if __name__ == "__main__":
    main()
