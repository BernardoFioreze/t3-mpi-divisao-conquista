#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Analise dos tempos do T3 a partir das saidas do Slurm (resultados/*.out).

Le as linhas impressas pelos binarios (prefixadas pelo echo dos scripts sbatch),
agrupa por configuracao, e reporta mediana / minimo / maximo e os speed-ups.

Formato esperado de cada linha (tokens chave=valor, em qualquer ordem):
  serie=T1       P=1  ...                 n=.. delta=.. tempo=.. verificacao=OK
  serie=T1d_orig P=3  delta=50000 ...     n=.. delta=.. tempo=.. verificacao=OK
  serie=T1d_bal  P=4  delta=25000 ...     n=.. delta=.. tempo=.. verificacao=OK
  serie=orig     P=7  delta=12500 ...     versao=original  N=.. delta=.. P=.. tempo=.. verificacao=OK
  serie=bal      P=16 ...                 versao=balanceado N=.. P=.. tempo=.. verificacao=OK
  serie=oversub  mode=yield P=63 delta=.. versao=original  N=.. delta=.. P=.. tempo=.. verificacao=OK

Uso:  python3 analise.py [arquivos...]      (padrao: resultados/*.out)

Referencias (secao 6 do enunciado):
  S   = T1   / T_P      (vs Bubble do vetor inteiro; pode passar de P)
  S^d = T1^d / T_P      (so paralelismo)   e   E = S^d / P   (eficiencia)
  Na serie 63..1023 (acima das 32 threads de hardware), E = S^d / 32.
  Ganho de algoritmo = T1 / T1^d.
"""
import sys
import glob
from collections import defaultdict
from statistics import median


def parse_tokens(line):
    d = {}
    for tok in line.split():
        if "=" in tok:
            k, v = tok.split("=", 1)
            d[k] = v
    return d


def carrega(arquivos):
    recs = []
    for caminho in arquivos:
        try:
            f = open(caminho, encoding="utf-8", errors="replace")
        except OSError as e:
            print("aviso: nao consegui abrir %s (%s)" % (caminho, e), file=sys.stderr)
            continue
        with f:
            for linha in f:
                if "tempo=" not in linha:
                    continue
                d = parse_tokens(linha)
                try:
                    tempo = float(d["tempo"])
                except (KeyError, ValueError):
                    continue
                recs.append({
                    "serie": d.get("serie", "?"),
                    "mode": d.get("mode"),
                    "P": int(d["P"]) if "P" in d else None,
                    "delta": int(d["delta"]) if "delta" in d else None,
                    "N": int(d["N"]) if "N" in d else (int(d["n"]) if "n" in d else None),
                    "tempo": tempo,
                    "ver": d.get("verificacao", "?"),
                })
    return recs


def stats(tempos):
    return median(tempos), min(tempos), max(tempos), len(tempos)


def fmt(x, casas=6):
    return "-" if x is None else ("%.*f" % (casas, x))


def main():
    arquivos = sys.argv[1:] or sorted(glob.glob("resultados/*.out"))
    if not arquivos:
        print("nenhum arquivo. uso: python3 analise.py resultados/*.out")
        return 1
    recs = carrega(arquivos)
    if not recs:
        print("nenhuma linha com tempo= encontrada em: %s" % ", ".join(arquivos))
        return 1

    # --- verificacao ---
    falhas = [r for r in recs if r["ver"] != "OK"]
    print("== Verificacao ==")
    if falhas:
        print("  ATENCAO: %d execucao(oes) com verificacao != OK:" % len(falhas))
        for r in falhas[:20]:
            print("    serie=%s P=%s delta=%s ver=%s" %
                  (r["serie"], r["P"], r["delta"], r["ver"]))
    else:
        print("  todas as %d execucoes: OK" % len(recs))
    print()

    # --- N usado ---
    Ns = sorted({r["N"] for r in recs if r["N"]})
    N = Ns[-1] if Ns else None
    if len(Ns) > 1:
        print("aviso: mais de um N nos dados: %s (usando %s para ceil(N/P))\n" % (Ns, N))

    # --- medianas por configuracao ---
    def mediana_por(filtro, chave):
        grupos = defaultdict(list)
        for r in recs:
            if filtro(r):
                grupos[chave(r)].append(r["tempo"])
        return {k: stats(v) for k, v in grupos.items()}

    # referencias sequenciais
    T1 = mediana_por(lambda r: r["serie"] == "T1", lambda r: 1).get(1)
    t1d_orig = mediana_por(lambda r: r["serie"] == "T1d_orig", lambda r: r["delta"])
    t1d_bal = mediana_por(lambda r: r["serie"] == "T1d_bal", lambda r: r["delta"])

    t1_med = T1[0] if T1 else None

    print("== Referencias sequenciais ==   (N=%s)" % N)
    print("  %-10s %6s %9s %10s %10s %10s %5s  %s" %
          ("serie", "P", "delta", "med", "min", "max", "reps", "ganho T1/T1d"))
    if T1:
        print("  %-10s %6d %9s %10s %10s %10s %5d" %
              ("T1", 1, "-", fmt(T1[0]), fmt(T1[1]), fmt(T1[2]), T1[3]))
    for rotulo, tbl in (("T1d_orig", t1d_orig), ("T1d_bal", t1d_bal)):
        for delta in sorted(tbl):
            med, mn, mx, reps = tbl[delta]
            ganho = fmt(t1_med / med, 2) if (t1_med and med) else "-"
            print("  %-10s %6s %9d %10s %10s %10s %5d  %s" %
                  (rotulo, "-", delta, fmt(med), fmt(mn), fmt(mx), reps, ganho))
    print()

    def tabela_paralela(titulo, serie, ref_fn, eff_base_fn):
        grupos = defaultdict(list)
        extra = {}
        for r in recs:
            if r["serie"] != serie:
                continue
            k = (r["mode"], r["P"])
            grupos[k].append(r["tempo"])
            extra[k] = r  # guarda delta/N do grupo
        if not grupos:
            return
        print("== %s ==" % titulo)
        tem_modo = any(k[0] is not None for k in grupos)
        cab = ("  %-7s " % "mode") if tem_modo else "  "
        print(cab + "%5s %9s %10s %10s %10s %9s %9s %9s %5s" %
              ("P", "delta", "TP_med", "TP_min", "TP_max", "S", "S^d", "E", "reps"))
        for k in sorted(grupos, key=lambda x: (x[0] or "", x[1])):
            mode, P = k
            med, mn, mx, reps = stats(grupos[k])
            r = extra[k]
            S = (t1_med / med) if (t1_med and med) else None
            t1d = ref_fn(r)
            Sd = (t1d / med) if (t1d and med) else None
            base = eff_base_fn(P)
            E = (Sd / base) if (Sd and base) else None
            pref = ("  %-7s " % mode) if tem_modo else "  "
            print(pref + "%5d %9s %10s %10s %10s %9s %9s %9s %5d" %
                  (P, (str(r["delta"]) if r["delta"] else "-"),
                   fmt(med), fmt(mn), fmt(mx),
                   fmt(S, 2), fmt(Sd, 2), fmt(E, 3), reps))
        print()

    # original: referencia T1d casada pelo delta do run
    tabela_paralela(
        "Paralelo original", "orig",
        ref_fn=lambda r: (t1d_orig.get(r["delta"], (None,))[0]),
        eff_base_fn=lambda P: P,
    )

    # balanceado: referencia T1d_bal com delta = ceil(N/P) (P potencia de 2);
    # para P nao-potencia de 2 (ex.: 31) nao ha referencia de delta unico.
    def ref_bal(r):
        P = r["P"]
        if not N or not P or (P & (P - 1)) != 0:
            return None
        delta_bal = (N + P - 1) // P
        v = t1d_bal.get(delta_bal)
        return v[0] if v else None

    tabela_paralela(
        "Paralelo balanceado", "bal",
        ref_fn=ref_bal,
        eff_base_fn=lambda P: P,
    )
    print("  (P nao potencia de 2, p.ex. 31: S^d/E sem referencia de delta unico"
          " — use um sequencial adaptado a` arvore)")
    print()

    # oversubscription: eficiencia em relacao as 32 threads de hardware
    tabela_paralela(
        "Oversubscription (original, 63..1023)", "oversub",
        ref_fn=lambda r: (t1d_orig.get(r["delta"], (None,))[0]),
        eff_base_fn=lambda P: 32,
    )

    # avisos de repeticoes != 10
    contagem = defaultdict(int)
    for r in recs:
        contagem[(r["serie"], r["mode"], r["P"], r["delta"])] += 1
    ruins = [(k, c) for k, c in contagem.items() if c != 10]
    if ruins:
        print("aviso: configuracoes sem 10 repeticoes:")
        for k, c in sorted(ruins, key=lambda x: str(x[0])):
            print("  serie=%s mode=%s P=%s delta=%s -> %d reps" % (k[0], k[1], k[2], k[3], c))
    return 0


if __name__ == "__main__":
    sys.exit(main())
