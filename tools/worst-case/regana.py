# analyse regmatrix output: per case/format/mode/arm mean/p99/max, overruns (budget by format), CPU, frame types (trace_headers, round 1),
# re-encode rows (count/ runs); flags cells where an arm's p99 or overruns are worse than M (master) beyond noise (per-round paired t, 95%).
import re, statistics as st, sys, os, json, collections
sys.path.insert(0, '/home/obe/rack01-pds/wc'); from ftype import ftypes
O = sys.argv[1] if len(sys.argv) > 1 else '/home/obe/rack01-pds/wc/reg'; R = 3; T = {2: 4.303, 5: 2.571}[R-1]
CASES = "bcuts dimcuts dipcut flash2 flash4 strobe3 halffade fademotion flicker2 flicker10 ticker static2move textgfx grain xfade shake pfade".split()
BUD = {'p422_10': 1e6/60, 'p420_8': 1e6/50, 'i422_10': 1e6/25}
def p99(x): x = sorted(x); return x[min(len(x)-1, int(.99*len(x)))]
def ci(d): return (st.mean(d), T * st.stdev(d) / len(d) ** .5) if len(d) > 1 else (st.mean(d), 0)
ftc = os.path.join(O, 'ftypes.json'); FT = json.load(open(ftc)) if os.path.exists(ftc) else {}
flags = []
for c in CASES:
    for fm in ('p422_10', 'p420_8', 'i422_10'):
        for mode, arms in (('ll4', 'MSO'), ('ll8', 'MSO'), ('nw8', 'MS')):
            D = {}
            for a in arms:
                runs = []
                for r in range(1, R+1):
                    k = f'{c}.{fm}.{mode}.{a}.r{r}'
                    try: L = [float(x) for x in open(f'{O}/{k}.lat')][1:]; s = open(f'{O}/{k}.log', errors='replace').read()
                    except FileNotFoundError: continue
                    runs.append(dict(L=L, cpu=float(re.search(r'cpu_ms_per_frame ([\d.]+)', s)[1])))
                if runs: D[a] = runs
            if 'M' not in D: continue
            line = []
            for a, runs in D.items():
                v = [x for d in runs for x in d['L']]; b = BUD[fm]
                ft = FT.get(f'{c}.{fm}.{mode}.{a}.r1', '')
                cnt = ''
                if mode == 'll4' and os.path.exists(f'{O}/count/{c}.{fm}.ll4.{a}.log'):
                    m = re.search(r'REENC rows (\d+)', open(f'{O}/count/{c}.{fm}.ll4.{a}.log', errors='replace').read()); cnt = f" reenc {m[1] if m else '?'}"
                line.append(f"{a}: {st.mean(v)/1e3:5.2f}/{p99(v)/1e3:5.2f}/{max(v)/1e3:5.2f} ovr {sum(x>b for x in v)} cpu {st.mean(d['cpu'] for d in runs):5.1f}" + (f" I{ft.count('I')}/W{ft.count('W')}/P{ft.count('P')}" if ft else '') + cnt)
            print(f"{c:11s} {fm} {mode}: " + ' | '.join(line))
            for a in [x for x in D if x != 'M']:
                pm = ci([p99(y['L']) - p99(x['L']) for x, y in zip(D['M'], D[a])]); om = [sum(v > BUD[fm] for v in y['L']) - sum(v > BUD[fm] for v in x['L']) for x, y in zip(D['M'], D[a])]
                mm = ci([st.mean(y['L']) - st.mean(x['L']) for x, y in zip(D['M'], D[a])])
                worse_p99 = pm[0] - pm[1] > 0; worse_ovr = min(om) > 0
                if worse_p99 or worse_ovr: flags.append(f"{c} {fm} {mode} {a} vs M: p99 {pm[0]/1e3:+.2f} ±{pm[1]/1e3:.2f} ms, mean {mm[0]/1e3:+.2f} ±{mm[1]/1e3:.2f}, overruns per round {om}")
print('\nFLAGGED (worse than master beyond noise):'); print('\n'.join(flags) if flags else 'none')
