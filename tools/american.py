"""American English in everything a reader of this project sees (since 2026-11-13).

    python3 tools/american.py scan            what British spellings are left, and where:
                                              in comments, in strings, in names of the code
    python3 tools/american.py fix             rewrite the comments (and docstrings) only
    python3 tools/american.py fix --all       comments, string literals and the code's own names
    python3 tools/american.py text FILE ...   rewrite whole text files (README.md and the like)

"fix" alone touches only comments: GDScript and shell `#`, Python `#` and docstrings, shader
`//` and `/* */`; words that look like code are left alone there (in backticks, next to `_`,
`.`, `/` or `(`), and it proves itself by comparing every file with its comments taken out.
"fix --all" renames too (`colony_centre` becomes `colony_center`, the key "metres" becomes
"meters"), the same word the same way in every file, so that what refers to what still does.
That holds only while nothing outside these files uses such a name: on 2026-11-13 no scene,
no data file and no model did (look again before running it: `scan` cannot see them). It stops
if a new name is taken already. Afterward: check every script, run the game, compare
tools/placements.gd and tools/reef_placements.gd with a run from before.
This file itself (its word lists) and the third-party addon (addons/) are left alone.
Run "scan" now and then: new text should be American from the start.
"""
import io, os, re, sys, tokenize

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIRS = ["scripts", "shaders", "tools", "manual", "manual/capture", "dmg"]
EXTS = (".gd", ".gdshader", ".gdshaderinc", ".py", ".sh")

# ---------------------------------------------------------------- the words
OUR = ["behaviour", "neighbour", "flavour", "favour", "harbour", "honour", "labour", "vapour", "odour",
       "armour", "humour", "rumour", "colour", "endeavour", "vigour", "rigour", "tumour", "splendour",
       "parlour", "candour", "clamour", "fervour", "saviour", "savour", "valour", "rancour", "demeanour"]
ISE = ("real recogn organ optim normal random initial synchron minim maxim emphas summar visual stabil "
       "local parametr parameter quant linear general special memor apolog critic character categor "
       "priorit util serial final equal neutral harmon standard material capital penal digit item colon "
       "fertil vapor central familiar custom modern symbol sympath synthes hypothes vector discret "
       "regular global polar magnet energ oxid anonym author civil legal mobil natural popular rational "
       "scrutin social steril subsid tranquill trivial urban victim vocal pressur miniatur immun dramat "
       "econom fantas jeopard monopol pulver tantal crystall raster patron revolution terror").split()
ELL = ("travel model label level cancel signal tunnel channel marvel snorkel pedal dial fuel quarrel "
       "shovel spiral swivel total jewel funnel panel barrel bevel counsel equal pencil rival towel "
       "grovel tassel shrivel unravel ravel gravel chisel duel parcel revel trowel tinsel enamel libel "
       "marshal nickel stencil drivel snivel").split()
WARDS = ("to after back for up down on in out sea land shore side home sky east west north south lee "
         "wind rear").split()
PLAIN = {  # whole words, lower case
    "centred": "centered", "centring": "centering", "grey": "gray", "greys": "grays", "greyish": "grayish",
    "greyer": "grayer", "greyed": "grayed", "greying": "graying", "licence": "license", "licences": "licenses",
    "licenced": "licensed", "practise": "practice", "practised": "practiced", "practises": "practices",
    "practising": "practicing", "defence": "defense", "defences": "defenses", "offence": "offense",
    "pretence": "pretense", "whilst": "while", "amongst": "among", "learnt": "learned", "dreamt": "dreamed",
    "spelt": "spelled", "spoilt": "spoiled", "leant": "leaned", "storey": "story", "storeys": "stories",
    "plough": "plow", "ploughs": "plows", "ploughed": "plowed", "ploughing": "plowing", "sulphur": "sulfur",
    "aluminium": "aluminum", "catalogue": "catalog", "catalogues": "catalogs", "programme": "program",
    "programmes": "programs", "judgement": "judgment", "acknowledgement": "acknowledgment", "ageing": "aging",
    "tyre": "tire", "tyres": "tires", "sceptic": "skeptic", "sceptical": "skeptical", "artefact": "artifact",
    "artefacts": "artifacts", "enquire": "inquire", "enquiry": "inquiry", "speciality": "specialty",
    "cosy": "cozy", "draught": "draft", "draughts": "drafts", "kerb": "curb", "analogue": "analog",
    "anticlockwise": "counterclockwise", "anti-clockwise": "counterclockwise", "skilful": "skillful",
    "wilful": "willful", "fulfil": "fulfill", "fulfils": "fulfills", "fulfilment": "fulfillment",
    "instalment": "installment", "enrol": "enroll", "distil": "distill", "aeroplane": "airplane",
    "maths": "math", "orientated": "oriented", "moustache": "mustache", "woollen": "woolen",
    "jewellery": "jewelry", "marvellous": "marvelous", "focussed": "focused", "focussing": "focusing",
    "faeces": "feces", "mediaeval": "medieval", "manoeuvre": "maneuver", "manoeuvres": "maneuvers",
    "manoeuvred": "maneuvered", "manoeuvring": "maneuvering", "manoeuvrable": "maneuverable",
    "mould": "mold", "moulds": "molds", "moulded": "molded", "moulding": "molding", "mouldy": "moldy",
    "moult": "molt", "moults": "molts", "moulted": "molted", "moulting": "molting", "smoulder": "smolder",
    "smoulders": "smolders", "smouldering": "smoldering", "optimising": "optimizing",
}
RE_WORDS = [  # (pattern, replacement), applied to a lower-cased word; the first that matches wins
    (re.compile(r"^(.*)(%s)(.*)$" % "|".join(OUR)), lambda m: m.group(1) + m.group(2)[:-2] + "r" + m.group(3)),
    (re.compile(r"^(kilo|centi|milli|deci|nano|micro)?metre(s?)$"), lambda m: (m.group(1) or "") + "meter" + m.group(2)),
    (re.compile(r"^(.*)centre(s|line|lines|piece)?$"), lambda m: m.group(1) + "center" + (m.group(2) or "")),
    (re.compile(r"^(milli|centi)?litre(s?)$"), lambda m: (m.group(1) or "") + "liter" + m.group(2)),
    (re.compile(r"^(fib|calib|lust|somb|theat|spect|meag|sab)re(s?)$"), lambda m: m.group(1) + "er" + m.group(2)),
    (re.compile(r"^(%s)is(e|es|ed|ing|er|ers|ation|ations|able)$" % "|".join(ISE)), lambda m: m.group(1) + "iz" + m.group(2)),
    (re.compile(r"^(un|re|over)?(anal|paral|catal)ys(e|es|ed|ing)$"), lambda m: (m.group(1) or "") + m.group(2) + "yz" + m.group(3)),
    (re.compile(r"^(un|re|mis)?(%s)l(ed|ing|er|ers)$" % "|".join(ELL)), lambda m: (m.group(1) or "") + m.group(2) + m.group(3)),
    (re.compile(r"^(%s)wards$" % "|".join(WARDS)), lambda m: m.group(1) + "ward"),
]
AROUND = re.compile(r"\b(?:(?P<a>way|all|turn|turns|turned|turning|right|halfway|go|goes|going|get|gets|getting|"
                    r"got|came|come|comes|swing|swings|swung|swim|swims|walk|walks|fly|flies|led|lead|leads) round\b"
                    r"|round (?P<b>the|it|its|a|an|them|him|her|you|each|every|which|this|that|these|those|here|there|"
                    r"one|two|three|both|about|and round)\b)", re.I)
PERCENT = re.compile(r"\bper cent\b")
WORD = re.compile(r"[A-Za-z]+(?:-[A-Za-z]+)?")
# a broad net for "scan": what may be British and is not in the lists above
NET = re.compile(r"\b(\w*[a-z]{3,}is(?:e|es|ed|ing|ation|ations)|\w+ll(?:ed|ing)|\w+our(?:s|ed|ing)?|\w+[tb]re|\w*round)\b", re.I)


def american(word):
    """The American spelling of one word, or None if it is American already (or unknown)."""
    low = word.lower()
    new = PLAIN.get(low)
    if new is None:
        for rx, f in RE_WORDS:
            m = rx.match(low)
            if m:
                new = f(m)
                break
    if new is None or new == low:
        if "-" in word:   # each half of a hyphenated word by itself
            parts = [american(p) or p for p in word.split("-")]
            joined = "-".join(parts)
            return joined if joined != word else None
        return None
    if word.isupper():
        return new.upper()
    return new.capitalize() if word[0].isupper() else new


def convert(text, changed=None, guard=True):
    """A piece of prose in American spelling. With guard, words that look like code stay."""
    ticks = [m.span() for m in re.finditer(r"`[^`\n]*`", text)] if guard else []

    def is_code(a, b):
        if not guard:
            return False
        if any(s <= a and b <= e for s, e in ticks):
            return True
        before, after = text[a - 1:a] if a > 0 else "", text[b:b + 1]
        if before in ("_", ".", "/", "$", "%") or after in ("_", "(", "/"):
            return True
        return re.match(r"\.(gd|py|sh|png|jpg|glb|json|wav|tscn|md)\b", text[b:b + 6]) is not None

    def word(m):
        if is_code(m.start(), m.end()):
            return m.group(0)
        new = american(m.group(0))
        if new and changed is not None:
            changed[m.group(0).lower()] = changed.get(m.group(0).lower(), 0) + 1
        return new or m.group(0)

    def around(m):
        if changed is not None:
            changed["round (around)"] = changed.get("round (around)", 0) + 1
        return re.sub(r"\b[Rr]ound\b", lambda r: "Around" if r.group(0)[0] == "R" else "around", m.group(0), count=1)

    out = WORD.sub(word, text)
    out = AROUND.sub(around, out)
    return PERCENT.sub("percent", out)


# ---------------------------------------------------------------- where the comments are
def spans_hash(text, triple=True):
    """(start, end, kind) of comments and strings in GDScript or shell text."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            j = n if j < 0 else j
            out.append((i, j, "comment")); i = j
        elif c in "\"'":
            q = text[i:i + 3] if triple and text[i:i + 3] in ('"""', "'''") else c
            j = i + len(q)
            while j < n and not text.startswith(q, j):
                j += 2 if text[j] == "\\" else 1
                if len(q) == 1 and j < n and text[j] == "\n" and text[j - 1] != "\\":
                    break   # (an unclosed quote ends with its line: an apostrophe in shell text)
            j = min(n, j + len(q))
            out.append((i, j, "string")); i = j
        else:
            i += 1
    return out


def spans_shell(text):
    """Shell: only whole-line comments and ones after two spaces (quotes and $# are too many cases)."""
    out = []
    for m in re.finditer(r"(?m)^[ \t]*#(?!!).*$|(?<=  )# .*$", text):
        out.append((m.start(), m.end(), "comment"))
    return out


def spans_shader(text):
    out = []
    for m in re.finditer(r"//[^\n]*|/\*.*?\*/|\"(?:\\.|[^\"\\\n])*\"", text, re.S):
        out.append((m.start(), m.end(), "string" if m.group(0)[0] == '"' else "comment"))
    return out


def spans_python(text):
    out, lines = [], text.split("\n")
    offs = [0]
    for l in lines:
        offs.append(offs[-1] + len(l) + 1)
    pos = lambda rc: offs[rc[0] - 1] + rc[1]
    prev = None
    toks = [t for t in tokenize.generate_tokens(io.StringIO(text).readline)]
    for k, t in enumerate(toks):
        if t.type == tokenize.COMMENT:
            out.append((pos(t.start), pos(t.end), "comment"))
        elif t.type == tokenize.STRING:
            nxt = next((u for u in toks[k + 1:] if u.type not in (tokenize.COMMENT, tokenize.NL)), None)
            doc = (prev is None or prev in (tokenize.NEWLINE, tokenize.INDENT, tokenize.DEDENT)) \
                and nxt is not None and nxt.type == tokenize.NEWLINE
            out.append((pos(t.start), pos(t.end), "comment" if doc else "string"))
        if t.type not in (tokenize.COMMENT, tokenize.NL, tokenize.ENCODING):
            prev = t.type
    return out


def spans(path, text):
    if path.endswith(".py"):
        return spans_python(text)
    if path.endswith((".gdshader", ".gdshaderinc")):
        return spans_shader(text)
    if path.endswith(".sh"):
        return spans_shell(text)
    return spans_hash(text)


def files():
    for d in DIRS:
        full = os.path.join(ROOT, d)
        for f in sorted(os.listdir(full)):
            if f.endswith(EXTS) and os.path.isfile(os.path.join(full, f)) and f != "american.py":
                yield os.path.join(d, f)


def without(text, sp, kinds):
    out, last = [], 0
    for a, b, k in sp:
        if k in kinds:
            out.append(text[last:a]); last = b
    out.append(text[last:])
    return "".join(out)


# ---------------------------------------------------------------- the three jobs
def scan():
    total = {"comment": 0, "string": 0, "name": 0}
    for rel in files():
        text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
        sp = spans(rel, text)
        pieces = [(a, b, k) for a, b, k in sp]
        last = 0
        for a, b, k in sp + [(len(text), len(text), "end")]:
            if a > last:
                pieces.append((last, a, "name"))
            last = b
        for a, b, k in sorted(pieces):
            found = {}
            if k == "name":
                for m in re.finditer(r"[A-Za-z]+", text[a:b]):
                    if american(m.group(0)):
                        found[m.group(0).lower()] = 1
            else:
                convert(text[a:b], found)
            if found:
                total[k] += sum(found.values())
                line = text.count("\n", 0, a) + 1
                if k != "comment" or "-v" in sys.argv:
                    print("%s:%d: %s: %s   | %s" % (rel, line, k, ", ".join(sorted(found)), text[a:b].strip().replace("\n", " ")[:90]))
    print("British spellings: %(comment)d in comments, %(string)d in strings, %(name)d in names of the code" % total)
    if "--net" in sys.argv:
        seen = {}
        for rel in files():
            text = open(os.path.join(ROOT, rel), encoding="utf-8").read()
            for a, b, k in spans(rel, text):
                if k == "comment":
                    for m in NET.finditer(text[a:b]):
                        seen[m.group(0).lower()] = seen.get(m.group(0).lower(), 0) + 1
        print(" ".join("%s(%d)" % kv for kv in sorted(seen.items())))


def names(code, changed=None):
    """A stretch of code with the British parts of its names made American."""
    def word(m):
        new = american(m.group(0))
        if new and changed is not None:
            changed[m.group(0).lower()] = changed.get(m.group(0).lower(), 0) + 1
        return new or m.group(0)
    return re.sub(r"[A-Za-z]+", word, code)


def fix(everything=False):
    changed, nfiles, todo = {}, 0, []
    ident = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")
    for rel in files():
        path = os.path.join(ROOT, rel)
        text = open(path, encoding="utf-8").read()
        sp = spans(rel, text)
        out, last, code = [], 0, []
        for a, b, k in sp + [(len(text), len(text), "end")]:
            code.append(text[last:a])
            out.append(names(text[last:a], changed) if everything else text[last:a])
            if k == "comment" or (everything and k == "string"):
                out.append(convert(text[a:b], changed, guard=not everything))
            else:
                out.append(text[a:b])
            last = b
        new = "".join(out)
        if new == text:
            continue
        if everything:
            # a new name must not be one the file has already
            have = set(ident.findall("".join(code)))
            clash = sorted(i for i in have if names(i) != i and names(i) in have)
            if clash:
                print("STOPPED, nothing written: %s has both spellings of %s" % (rel, ", ".join(clash)))
                return
        elif without(text, sp, ("comment",)) != without(new, spans(rel, new), ("comment",)):
            # (the proof: with the comments taken out, the file is what it was)
            print("NOT WRITTEN (the code would change): " + rel)
            continue
        todo.append((path, new))
    for path, new in todo:
        open(path, "w", encoding="utf-8").write(new)
        nfiles += 1
    print("%d files rewritten; %d words: %s" % (nfiles, sum(changed.values()),
          ", ".join("%s %d" % kv for kv in sorted(changed.items(), key=lambda kv: -kv[1]))))


def text_files(paths):
    for p in paths:
        if "LICENSE" in os.path.basename(p).upper():
            print(p + ": not touched (a license's text is its authors')")   # (it happened once)
            continue
        s = open(p, encoding="utf-8").read()
        changed = {}
        t = convert(s, changed)
        if t != s:
            open(p, "w", encoding="utf-8").write(t)
        print(p, changed)


if __name__ == "__main__":
    job = sys.argv[1] if len(sys.argv) > 1 else "scan"
    if job == "fix":
        fix("--all" in sys.argv)
    elif job == "text":
        text_files(sys.argv[2:])
    else:
        scan()
