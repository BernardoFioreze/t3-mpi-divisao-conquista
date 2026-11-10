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
N=${N:-200000}   # calibrado no Atlantica: T1 ~ 40s (mediana medida)
REPS=${REPS:-10}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/original

# Mitiga o 'PMIX ERROR ... gds_ds21_lock_pthread' ao lancar milhares de
# processos: usa o datastore 'hash' em vez do componente de memoria compartilhada.
export PMIX_MCA_gds=hash

# Com milhares de processos o Open MPI abre muitos pipes/descritores para
# encaminhar a saida de cada rank; em P=1023 isso estoura o limite do SO
# ("system limit on number of pipes ... was reached"). Sobe o numero de
# descritores ao maximo permitido e deixa o Open MPI elevar os limites do SO.
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
echo "# ulimit -n (apos ajuste) = $(ulimit -n)  Hn = $(ulimit -Hn)"

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS"

# A errata da v2 do enunciado pede as DUAS series com a variavel definida
# EXPLICITAMENTE (=0 e =1), porque, dependendo do lancamento, deixa-la sem
# definir pode ja ceder o nucleo e as duas medirem a mesma coisa.
for mode in default yield; do
  if [ "$mode" = yield ]; then
    export OMPI_MCA_mpi_yield_when_idle=1   # cede o nucleo enquanto espera
  else
    export OMPI_MCA_mpi_yield_when_idle=0   # espera ativa (explicito, nao 'unset')
  fi
  for P in 63 127 255 511 1023; do
    delta=$(( (2*N + P) / (P + 1) ))
    for r in $(seq 1 "$REPS"); do
      echo -n "serie=oversub mode=$mode P=$P delta=$delta rep=$r  "
      mpirun --oversubscribe -np "$P" --map-by node \
             --mca opal_set_max_sys_limits 1 "$BIN" "$N" "$delta"
    done
  done
done
