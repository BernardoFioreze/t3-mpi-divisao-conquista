#!/bin/bash
# Versao paralela ORIGINAL (pai manda as duas metades e espera).
# 2 nos exclusivos. P = 1, 3, 7, 15, 31 (15 = um por nucleo fisico; 31 usa HT).
#
# Submeter a partir da raiz do projeto:  sbatch sbatch/original.sbatch
# Contrato de linha de comando do binario:  mpirun -np P src/original N delta
#   (delta = ceil(2N/(P+1)), calculado aqui e passado para casar com a referencia)
#
#SBATCH --job-name=t3-orig
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --ntasks=31
#SBATCH --output=resultados/orig-%j.out
## Use SEMPRE os mesmos 2 nos:
## #SBATCH --nodelist=<no1>,<no2>

set -eu
N=${N:-200000}   # calibrado no Atlantica: T1 ~ 40s (mediana medida)
REPS=${REPS:-10}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/original

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS"

for P in 1 3 7 15 31; do
  delta=$(( (2*N + P) / (P + 1) ))
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=orig P=$P delta=$delta rep=$r  "
    mpirun -np "$P" --map-by node "$BIN" "$N" "$delta"
  done
done
