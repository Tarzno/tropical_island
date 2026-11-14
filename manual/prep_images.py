"""Cuts the manual's pictures (images/) out of screenshots of the game.
  python3 prep_images.py              from sources/ (the screenshots chosen, kept as JPEG)
  python3 prep_images.py <folder>     from a folder of fresh batches (manual/capture/*.py write
                                      theirs to manual/capture/shots/): PNG, else JPEG
Each entry: slug -> (batch/file, zoom, center x, center y); the cut keeps 3:2. A new picture:
take it with a capture script, look at it, enter it here, and copy the screenshot into
sources/<batch>/ as JPEG so that this can be run again later."""
import os, sys
from PIL import Image
HERE = os.path.dirname(os.path.abspath(__file__))
P = {
 # plants
 "coconut": ("b4/palm30_0", 1, .5, .5), "naupaka": ("b4/BushAb_0", 1, .5, .5), "pemphis": ("b4/BushEb_0", 1, .5, .5),
 "glory": ("b4/glory_1", .9, .5, .55), "takamaka": ("b4/Taka0_1", 1, .5, .5), "badamier": ("b4/Bad0_1", 1, .5, .5),
 "jackfruit": ("b4/Jack1_2", .8, .5, .5), "pisonia": ("b4/Pis0_0", 1, .5, .5), "vacoa": ("b4/Vacoa0_0", 1, .5, .5),
 "cocodemer": ("b14/CocoB_11_0", 1, .5, .5), "cocodemer_m": ("b14/CocoA_6_0", 1, .5, .5), "cocodemer_nut": ("b11/seed1_0", .7, .5, .5),
 "latanier": ("b14/LatA_8_0", 1, .5, .5), "palmiste": ("b11/PalmB_4_0", 1, .5, .5), "fern": ("b11/fern15_0", 1, .5, .5),
 "nestfern": ("b16/nestfern600_0", .85, .5, .5), "mangrove": ("b4/Mangrove0_0", 1, .5, .5), "pitcher": ("b1/pitcher_2", 1, .5, .5),
 "orchid": ("b5/orchid1_0", 1, .5, .5), "vanilla": ("b5/vanilla2_1", .8, .5, .5), "seagrass": ("b12/grass_0", 1, .5, .5),
 # land animals
 "tortoise": ("b1/tortoise_2", 1, .5, .5), "skink": ("b1/skink_2", 1, .5, .5), "gecko": ("b16/geckow_4", .8, .5, .5),
 "flyingfox": ("b1/roost_0", .8, .5, .45), "frog": ("b1/frog_0", .7, .5, .5), "ghostcrab": ("b1/ghostcrab_3", .7, .5, .5),
 "rockcrab": ("b1/rockcrab_1", .6, .5, .5), "hermit": ("b10/herm2_0", .5, .55, .47), "spider": ("b1/spider_1", .8, .55, .5),
 "termites": ("b1/termites_2", 1, .5, .5), "millipede": ("b10/milli_2", .9, .5, .5), "snail": ("b5/snail_1", .7, .5, .5),
 "dragonfly": ("b5/dragon0_0", .5, .5, .47), "butterfly": ("b10/bfly5_0", .72, .36, .46), "mudskipper": ("b1/mudskipper_2", .7, .5, .5),
 # birds
 "crestedtern": ("b2/tern_1", .8, .5, .5), "noddy": ("nod/g7_0", 1, .5, .5), "whitetern": ("b2/wternfly_1", .6, .5, .47),
 "frigate": ("b10/frigd1_3", 1, .5, .5), "tropicbird": ("b10/tropfly5_2", .8, .5, .5), "sooty": ("b2/sooty_1", 1, .5, .5),
 "turnstone": ("b2/turnstone_2", .8, .5, .5), "crabplover": ("b2/crabplover_3", 1, .5, .5), "heron": ("b2/heron_2", .7, .5, .55),
 "myna": ("b2/mynah_1", .75, .5, .5), "dove": ("b2/dove_2", .7, .5, .5), "fody": ("b5/fody_2", .6, .5, .52), "robin": ("b2/robin_3", .8, .5, .5),
 # shore
 "rockskipper": ("b7/skipper1_2", .7, .5, .5), "barnacles": ("b7/barn700_0", 1, .5, .5),
 # sea
 "blacktip": ("b3/pup_2", 1, .5, .5), "tigershark": ("b3/shark_3", .8, .5, .5), "eagleray": ("b3/rays_1", 1, .5, .5),
 "manta": ("b3/manta_3", 1, .5, .5), "greenturtle": ("b3/green_1", 1, .5, .5), "hawksbill": ("b3/hawks_0", 1, .5, .5),
 "nesting": ("b7/nest_7", 1, .5, .5), "hatchlings": ("b7/hatch_3", 1, .5, .5), "dolphin": ("b10/leap1_0", .6, .68, .42),
 "grouper": ("b3/grouper_3", .8, .5, .5), "barracuda": ("b3/barra_3", .7, .47, .5), "titan": ("b3/titan_3", .8, .55, .5),
 "clown": ("b3/clown_1", .8, .5, .45), "lionfish": ("b3/lion_3", .8, .5, .5), "honeycomb": ("b6/moray4_0", 1, .5, .5),
 "giantmoray": ("b6/moray3_2", 1, .5, .5), "gardeneels": ("b15/eel3_1", 1, .5, .5), "octopus": ("b3/octo_2", 1, .5, .5),
 "anemonefish": ("b3/anem0_0", 1, .5, .5), "skunk": ("b3/anem1_2", 1, .5, .5), "bluetang": ("b6/schoolb0_1", .8, .5, .55),
 "convict": ("i4/convict1_0", .8, .52, .62), "idol": ("i8/pair_2", .85, .5, .5), "sergeant": ("b6/schoolb2_1", .8, .55, .42), "parrotfish": ("b6/school3_0", 1, .5, .5),
 "chromis": ("b6/schoolb4_1", 1, .5, .5), "jellyfish": ("b3/jelly_0", .8, .5, .5),
 # reef
 "urchin": ("b6/urchin300_0", 1, .5, .5), "bluestar": ("b15/bluest1_0", 1, .5, .5), "redknob": ("b6/star3_0", .8, .5, .5),
 "cushion": ("b15/cush9_0", 1, .5, .5), "clam": ("b3/clam_3", .8, .5, .5), "staghorn": ("b10/c_stag20_1", 1, .5, .5),
 "table": ("b12/tab4_1", 1, .5, .5), "finger": ("b10/c_finger3_1", 1, .5, .5), "cauliflower": ("b10/c_cauli0_1", 1, .5, .5),
 "boulder": ("b12/bould5_1", 1, .5, .5), "brain": ("b10/c_brain3_1", 1, .5, .5), "plate": ("b12/plate1_0", 1, .5, .5),
 "fire": ("b10/c_fire0_0", 1, .5, .5), "leather": ("b10/c_leather0_1", 1, .5, .5), "seafan": ("b10/c_fan0_2", 1, .5, .5),
 # the island and its states
 "cover": ("b17/cov0_beach", 1, .5, .5), "map": ("b13/map_pm", 1, .5, .5), "day_noon": ("b8/beach_mid2", 1, .5, .5),
 "day_golden": ("b9/golden2", 1, .5, .5), "day_sunset": ("b9/sunset4", 1, .5, .5), "day_night": ("b9/moonpath", 1, .5, .5),
 "moon": ("b9/fullmoon_-90", .9, .5, .55), "stars": ("b9/stars_up", 1, .5, .5), "bat": ("b9/bat_4", .9, .5, .5),
 "tide_high": ("b8/tide_high3", 1, .5, .5), "tide_low": ("b8/tide_low3", 1, .5, .5), "pool": ("b7/pool0_0", 1, .5, .5),
 "rain": ("b8/rain_beach", 1, .5, .5), "rainbow": ("b10/rc_90", .9, .5, .45), "glow": ("b9/glow2", 1, .5, .5),
 "snorkel": ("b8/snorkel2", 1, .5, .5), "grotto": ("b8/grotto_in1", 1, .5, .5), "summit": ("b8/summit_e", 1, .5, .5),
 "pond": ("b8/pond", 1, .5, .5), "sunset_wide": ("b9/sunset3", 1, .5, .5),
}
LIFT = {"snail": 0.72, "millipede": 0.75, "dragonfly": 0.8, "fody": 0.85}


def main(src):
    out = os.path.join(HERE, "images"); os.makedirs(out, exist_ok=True)
    for slug, (f, zoom, cx, cy) in P.items():
        path = os.path.join(src, f + ".png")
        if not os.path.exists(path): path = os.path.join(src, f + ".jpg")
        if not os.path.exists(path): path = os.path.join(HERE, "sources", f + ".jpg")
        im = Image.open(path).convert("RGB")
        W, H = im.size
        if slug == "map":
            # (taken with -z up; in the game +z is north: turned, so that north is up)
            im.resize((1500, 1500), Image.LANCZOS).rotate(180).save(os.path.join(out, slug + ".jpg"), quality=88); continue
        if slug == "cover":
            # the whole portrait picture, with a veil of deep sea color rising from its foot (for the title)
            import numpy as np
            a = np.asarray(im).astype(np.float32); yy = np.linspace(0.0, 1.0, H)[:, None, None]
            k = np.clip((yy - 0.52) / 0.48, 0.0, 1.0) ** 1.5 * 0.82
            a = a * (1 - k) + np.array([8.0, 52.0, 64.0]) * k
            Image.fromarray(a.astype(np.uint8)).save(os.path.join(out, slug + ".jpg"), quality=90); continue
        w = W * zoom; h = w * 2 / 3
        if h > H: h = H; w = h * 1.5
        x0 = min(max(cx * W - w / 2, 0), W - w); y0 = min(max(cy * H - h / 2, 0), H - h)
        im = im.crop((int(x0), int(y0), int(x0 + w), int(y0 + h)))
        size = (900, 600)
        if slug in LIFT:        # (taken in deep shade: the shadows lifted a little)
            im = im.point(lambda v: int(255.0 * (v / 255.0) ** LIFT[slug]))
        if im.size[0] > size[0]: im = im.resize(size, Image.LANCZOS)
        im.save(os.path.join(out, slug + ".jpg"), quality=87)
    print(len(P), "pictures")
if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "sources"))
