#!/bin/bash
# Versao paralela BALANCEADA (ao dividir, manda uma metade ao ajudante
# rank + 2^nivel e fica com a outra; processos internos tambem ordenam).
# 2 nos exclusivos. P = 2, 4, 8, 16, 32 e 31 (16 = um por nucleo; 32 = HT;
# 31 = comparacao direta com a versao original).
#
# Submeter a partir da raiz do projeto:  sbatch sbatch/balanceado.sbatch
# Contrato de linha de comando:  mpirun -np P src/balanceado N
#   (o binario decide as divisoes pelo tamanho do comunicador; nao recebe delta)
#
#SBATCH --job-name=t3-bal
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --ntasks=32
#SBATCH --output=resultados/bal-%j.out
## Use SEMPRE os mesmos 2 nos:
## #SBATCH --nodelist=<no1>,<no2>

set -eu
N=${N:-200000}   # calibrado no Atlantica: T1 ~ 40s (mediana medida)
REPS=${REPS:-10}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/balanceado

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS"

for P in 2 4 8 16 32 31; do
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=bal P=$P rep=$r  "
    mpirun -np "$P" --map-by node "$BIN" "$N"
  done
done
