#!/bin/bash
# Balanceamento SEM alterar o codigo: versao ORIGINAL com muito mais processos
# que threads de hardware (63..1023) nos mesmos 2 nos. Cada P roda 2x:
#   - padrao (Open MPI em espera ativa: nao cede o nucleo)
#   - com OMPI_MCA_mpi_yield_when_idle=1 (cede o nucleo enquanto espera)
# A diferenca mostra o balanceamento que o escalonador do SO consegue fazer.
#
# Submeter a partir da raiz do projeto:  sbatch sbatch/oversub.sbatch
#
#SBATCH --job-name=t3-oversub
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --overcommit
#SBATCH --output=resultados/oversub-%j.out
## Use SEMPRE os mesmos 2 nos:
## #SBATCH --nodelist=<no1>,<no2>

set -u
N=${N:-100000}
REPS=${REPS:-10}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/original

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS"

for mode in default yield; do
  if [ "$mode" = yield ]; then
    export OMPI_MCA_mpi_yield_when_idle=1
  else
    unset OMPI_MCA_mpi_yield_when_idle
  fi
  for P in 63 127 255 511 1023; do
    delta=$(( (2*N + P) / (P + 1) ))
    for r in $(seq 1 "$REPS"); do
      echo -n "serie=oversub mode=$mode P=$P delta=$delta rep=$r  "
      mpirun --oversubscribe -np "$P" --map-by node "$BIN" "$N" "$delta"
    done
  done
done
