"""The sidecar goldens (linker s-5908724a ruling 6): metispy's bundle (sidecar.json, ground.wire, tools.json) for every member of the four
corpus images, into OUT/<image>/<member>/. Run with a python that has metispy (cb3b742 made these), from corpus/iface:
    python ../goldens/sidecar/regen.py IMAGES_DIR $PWD OUT
where IMAGES_DIR holds `metisc --link C -o IMAGES_DIR` for the four compositions."""
import json, sys, yaml
from pathlib import Path
from metis.kernel import artifact
IMG, CORPUS, OUT = Path(sys.argv[1]), Path(sys.argv[2]), Path(sys.argv[3])
COMP = {"kitchen_pot": "kitchen_pot", "road": "road", "alfworld_hier": "alfworld/domains/hier", "minihack_hier": "minihack/domains/hier"}
for img in sorted(IMG.glob("*.image.v-*")):
    if img.suffix == ".tar": continue
    name = img.name.split(".image.")[0]
    j = json.loads((img / "image.json").read_text())
    for m in j["members"]:
        d = CORPUS / COMP[name] / m["name"]
        man = yaml.safe_load((d / "domain.yaml").read_text()) if (d / "domain.yaml").exists() else {}
        prog = d / m["program"]
        exts = [d / e for e in (man.get("extensions") or [])]
        o = OUT / name / m["name"]; o.mkdir(parents=True, exist_ok=True)
        try:
            files = artifact.build(prog, exts)
            for k, v in files.items(): (o / k).write_text(v)
            side = json.loads(files["sidecar.json"])
            mw = (img / m["bundle"] / "ground.wire").read_text()
            print("%-14s %-16s ok events %3d cards %d script %d ext %d  wire==metisc %s  key==wire_key %s" % (
                name, m["name"], len(side["events"]), len(side["cards"]), len(side["script"]), len(exts),
                files["ground.wire"] == mw, side["key"] == m.get("wire_key")))
        except Exception as e:
            print("%-14s %-16s ERROR %s: %s" % (name, m["name"], type(e).__name__, str(e)[:200]))
