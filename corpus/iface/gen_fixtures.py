"""Write metis-lang corpus/iface/<case>/: a clean composition `mini` and one variant per interface check (spec/15 §6).
Usage: gen_fixtures.py CORPUS_IFACE_DIR"""
import os
import shutil
import sys

OUT = sys.argv[1]

CAP = """% capacity — the mini composition's types (spec/15 §6 fixture).
catalog cap 1.
type thing {t1 t2}.
type domain {a b}.
type resource {hand}.
"""
PROTO = """% proto — the fixture's protocol module: declarations only.
catalog proto 1.
types (domain resource).
namespace proto produce (dyn).
pred tick__grant(domain, resource) : proto.
"""
PROTO_YAML = "nature: {tick__grant: signal}\n"
IFACE = """% iface_mini — the fixture's crossing vocabulary: declarations only.
catalog iface_mini 1.
types (thing).
namespace mini produce (dyn).
pred seen(thing) : mini.
pred ask(thing) : mini.
pred answer(thing) : mini.
pred cmd(thing) : mini.
pred tally(thing) : mini.
"""
IFACE_YAML = "nature: {seen: signal, ask: signal, answer: signal, cmd: signal, tally: signal}\n"
COMP = """# composition — the spec/15 §6 fixture `{name}`
capacity: capacity.llp
protocol: proto.llp
interfaces: [iface_mini.llp]
specialists: [a, b]
direct: d
world: {{out: [{wout}], in: [cmd]}}
"""
HEAD = """catalog {n} 1.
layers (dyn).
stages (act).
include "../capacity.llp".
include "../proto.llp".
include "../iface_mini.llp".
"""
A_RULES = """stage act {
  %% a sees a thing and asks about it.
  look [dyn] : seen(T) -o ask(T).
  %% a takes the answer.
  take [dyn] : answer(T) -o ().
}
"""
B_RULES = """stage act {
  %% b answers and commands the world.
  reply [dyn] : ask(T) -o answer(T) * cmd(T).
}
"""
D = """catalog d 1.
layers (dyn).
stages (act).
include "../capacity.llp".
include "../proto.llp".
namespace dir produce (dyn).
pred free(resource) : dir.
pred holder(domain, resource) : dir.
pred want(domain) : dir.
stage act {
  %% d grants the hand to a wanting member.
  grant [dyn] : want(S) * free(R) -o holder(S, R) * tick__grant(S, R).
  %% d takes the hand back.
  back [dyn] : holder(S, R) -o free(R).
}
#init free(hand) 1
"""
A_MAN = "# a\nprogram: a.llp\nshared: {{{shared}}}\nstatus: {{success: [ask], failure: []}}\n"
B_MAN = "# b\nprogram: b.llp\nshared: {{{shared}}}\nstatus: {{success: [answer], failure: []}}\n"
D_MAN = "# d\nprogram: d.llp\nshared: {tick__grant: out}\nresources: {hand: {count: 1, free: free, held_by: [holder]}}\n"

BASE = dict(wout="seen", a_shared="seen: in, ask: out, answer: in, hand: resource", b_shared="ask: in, answer: out, cmd: out",
            a_extra="", a_rules=A_RULES, b_extra="", b_rules=B_RULES, d=D, iface_yaml=IFACE_YAML,
            b_head=None, comp=None, extra_files={})


def write(name, **kw):
    c = dict(BASE, **kw)
    d = os.path.join(OUT, name)
    shutil.rmtree(d, ignore_errors=True)
    for sub in ("a", "b", "d"):
        os.makedirs(os.path.join(d, sub))
    w = lambda p, t: open(os.path.join(d, p), "w").write(t)
    w("capacity.llp", CAP)
    w("proto.llp", PROTO)
    w("proto.yaml", PROTO_YAML)
    w("iface_mini.llp", IFACE)
    w("iface_mini.yaml", c["iface_yaml"])
    w("composition.yaml", c["comp"] or COMP.format(name=name, wout=c["wout"]))
    w("a/domain.yaml", A_MAN.format(shared=c["a_shared"]))
    w("a/a.llp", HEAD.format(n="a") + c["a_extra"] + c["a_rules"])
    w("b/domain.yaml", B_MAN.format(shared=c["b_shared"]))
    w("b/b.llp", (c["b_head"] or HEAD.format(n="b")) + c["b_extra"] + c["b_rules"])
    w("d/domain.yaml", D_MAN)
    w("d/d.llp", c["d"])
    for p, t in c["extra_files"].items():
        w(p, t)


write("mini")
# I1: a pred both a and b declare themselves; a shares it, b does not
write("i1_unlisted", a_extra="namespace na produce (dyn).\npred note(thing) : na.\n",
      a_shared=BASE["a_shared"] + ", note: out",
      a_rules=A_RULES.replace("look [dyn] : seen(T) -o ask(T).", "look [dyn] : seen(T) -o ask(T) * note(T)."),
      b_extra="namespace nb produce (dyn).\npred note(thing) : nb.\n",
      b_rules=B_RULES.replace("reply [dyn] : ask(T) -o answer(T) * cmd(T).", "reply [dyn] : ask(T) * note(T) -o answer(T) * cmd(T)."))
# I2: a declares out a pred it only consumes
write("i2_direction", a_shared="seen: in, ask: out, answer: out, hand: resource")
# I3: a's in `seen` has no producer: the world no longer emits it
write("i3_unproduced", wout="")
# I4: a and b both consume and produce `tally`
write("i4_multiwriter", a_shared=BASE["a_shared"] + ", tally: out", b_shared=BASE["b_shared"] + ", tally: out",
      a_rules=A_RULES.replace("}\n", "  %% a counts.\n  count [dyn] : tally(T) -o tally(T).\n}\n"),
      b_rules=B_RULES.replace("}\n", "  %% b counts.\n  count [dyn] : tally(T) -o tally(T).\n}\n"))
# I5: d leaks the token
write("i5_resource", d=D.replace("  back [dyn] : holder(S, R) -o free(R).", "  back [dyn] : holder(S, R) -o ()."))
# I6: b is built over another capacity: the type thing differs
write("i6_types", b_head=HEAD.format(n="b").replace('include "../capacity.llp".', 'include "../capacity2.llp".'),
      extra_files={"capacity2.llp": CAP.replace("type thing {t1 t2}.", "type thing {t1 t3}.")})
# I7: a declares a pred with the reserved `__`
write("i7_reserved", a_extra="namespace na produce (dyn).\npred my__x(thing) : na.\n",
      a_rules=A_RULES.replace("take [dyn] : answer(T) -o ().", "take [dyn] : answer(T) -o my__x(T)."))
# I8: a names member b in a rule
write("i8_naming", a_rules=A_RULES.replace("take [dyn] : answer(T) -o ().", "take [dyn] : answer(T) * $tick__grant(b, hand) -o ()."),
      a_shared=BASE["a_shared"] + ", tick__grant: in")
# I9: a bwd static listed as a port
write("i9_static", a_extra="bwd near(thing).\nnear(t1).\n",
      a_shared=BASE["a_shared"] + ", near: in",
      a_rules=A_RULES.replace("look [dyn] : seen(T) -o ask(T).", "look [dyn] : seen(T) * $near(T) -o ask(T)."))
# I10: a shares a pred it declares itself
write("i10_local", a_extra="namespace na produce (dyn).\npred extra(thing) : na.\n",
      a_shared=BASE["a_shared"] + ", extra: out",
      a_rules=A_RULES.replace("take [dyn] : answer(T) -o ().", "take [dyn] : answer(T) -o extra(T)."))
# I11: `seen` is a report, a takes it in
write("i11_nature", iface_yaml=IFACE_YAML.replace("seen: signal", "seen: report"))
# I12: b includes another copy of the interface package, with a different key
write("i12_keys", b_head=HEAD.format(n="b").replace('include "../iface_mini.llp".', 'include "iface_mini.llp".'),
      extra_files={"b/iface_mini.llp": IFACE + "pred more(thing) : mini.\n"})
# the reader: block YAML is refused with its line
write("yaml_block", comp="# composition — the reader's refusal\ncapacity: capacity.llp\nspecialists:\n  - a\n  - b\ndirect: d\n")
print("ok")
