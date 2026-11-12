#!/bin/bash
# =====================================================================
# Complemento do teste N=1.000.000: roda o SEQUENCIAL (T1^delta, 1 processo)
# nos MESMOS delta do original/balanceado, para eles finalmente terem S^delta/E.
#
# delta = 500000, 250000, 125000, 62500, 31250  (niveis 2..6, N=1M):
#   - original  P=3,7,15,31  usam 500000,250000,125000,62500
#   - balanceado P=2,4,8,16,32 usam 500000,250000,125000,62500,31250
# Rotulados como T1d_orig (o analise.py reaproveita o mesmo delta para o
# balanceado, pois T1^delta so depende de delta).
#
# Roda em 1 no (sequencial). Sem T1 (vetor inteiro) -> ainda sem S absoluto,
# mas com S^delta/E.  Os delta grandes sao lentos (~48 min no total, 3 reps).
#
# Saida em resultados_1M/ (junta com o resto). Analise:
#   python3 analise.py resultados_1M/*.out
#
# Submeter da raiz do projeto:  sbatch sbatch/seq_1M_deltas.sbatch
#
#SBATCH --job-name=t3-1M-seqd
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --time=02:00:00
#SBATCH --output=resultados_1M/seq1M-deltas-%j.out
## Fixe o mesmo no das outras medicoes sequenciais:
## #SBATCH --nodelist=<no1>

set -eu
N=${N:-1000000}
REPS=${REPS:-3}
cd "${SLURM_SUBMIT_DIR:-.}"
SEQ=src/sequencial

echo "# host=$(hostname)  N=$N  REPS=$REPS"

for delta in 500000 250000 125000 62500 31250; do
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=T1d_orig P=- delta=$delta rep=$r  "
    $SEQ "$N" "$delta"
  done
done

echo "# FIM"
