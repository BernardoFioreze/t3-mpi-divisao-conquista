#!/bin/bash
# Referencias sequenciais: T1 (vetor inteiro) e T1^delta (mesma arvore em 1 processo).
# Roda em UM no do Atlantica (secao 5.2 do enunciado).
#
# Submeter a partir da raiz do projeto:  sbatch sbatch/seq.sbatch
# Calibrar N para T1 ficar entre 30 e 60 s no Atlantica (chute inicial ~1e5,
# pois 1e6 levou 74 min e o Bubble e' quadratico).
#
#SBATCH --job-name=t3-seq
#SBATCH --nodes=1
#SBATCH --exclusive
#SBATCH --output=resultados/seq-%j.out
## Fixe o mesmo no em todas as rodadas:
## #SBATCH --nodelist=<no1>

set -eu
N=${N:-100000}
REPS=${REPS:-10}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/sequencial

echo "# host=$(hostname)  N=$N  REPS=$REPS"
lscpu | grep -E 'Model name|Socket|Core\(s\)|Thread|^CPU\(s\)' || true

# T1: Bubble Sort do vetor inteiro
for r in $(seq 1 "$REPS"); do
  echo -n "serie=T1 P=1 rep=$r  "
  $BIN "$N"
done

# T1^delta da arvore ORIGINAL: um delta por valor de P (delta = ceil(2N/(P+1)))
for P in 3 7 15 31 63 127 255 511 1023; do
  delta=$(( (2*N + P) / (P + 1) ))
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=T1d_orig P=$P delta=$delta rep=$r  "
    $BIN "$N" "$delta"
  done
done

# T1^delta da arvore BALANCEADA (P potencia de 2: folha ~ N/P, delta = ceil(N/P))
for P in 2 4 8 16 32; do
  delta=$(( (N + P - 1) / P ))
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=T1d_bal P=$P delta=$delta rep=$r  "
    $BIN "$N" "$delta"
  done
done

# OBS: a versao balanceada com P=31 tem folhas de tamanhos diferentes; um delta
# unico nao reproduz a arvore. Para esse caso, adaptar o sequencial.c para
# percorrer exatamente a mesma arvore da versao balanceada antes de medir T1^delta.
