#!/bin/bash
# =====================================================================
# Diagnostico: re-rodar SO P=2047 e P=4095 no N=1.000.000, com timeout
# FOLGADO, para ver se completam quando tem tempo (no teste full_1M eles
# foram cortados pelo timeout de 20 min e pelo limite de 6h do job).
#
# Dois modos (espera ativa =0 e cede o nucleo =1). delta casa com o
# sequencial do teste full_1M (977 e 489), entao, analisando junto,
#   python3 analise.py resultados_1M/*.out
# sai o S^delta/E deles tambem.
#
# Ajustaveis por ambiente:
#   REPS    (padrao 3)    -> p/ uma sondagem rapida: REPS=1 sbatch ...
#   TIMEOUT (padrao 3600) -> segundos por rodada (1h). Se uma rodada passar
#                            disso, e' morta e segue.
#
# Submeter da raiz do projeto:  sbatch sbatch/oversub_1M_highP.sbatch
#
#SBATCH --job-name=t3-1M-highP
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --overcommit
#SBATCH --time=10:00:00
#SBATCH --output=resultados_1M/oversub-highP-%j.out
## Use SEMPRE os mesmos 2 nos:
## #SBATCH --nodelist=<no1>,<no2>

set -u
N=${N:-1000000}
REPS=${REPS:-3}
TIMEOUT=${TIMEOUT:-3600}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/original

export PMIX_MCA_gds=hash
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
ulimit -u "$(ulimit -Hu)" 2>/dev/null || true

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS  TIMEOUT=${TIMEOUT}s  nofile=$(ulimit -n)  nproc=$(ulimit -u)"
lscpu | grep -E 'Model name|Socket|Core\(s\)|Thread|^CPU\(s\)' || true

# P externo: fecha P=2047 (os dois modos) antes de arriscar P=4095.
for P in 2047 4095; do
  delta=$(( (2*N + P) / (P + 1) ))
  for mode in default yield; do
    if [ "$mode" = yield ]; then
      export OMPI_MCA_mpi_yield_when_idle=1
    else
      export OMPI_MCA_mpi_yield_when_idle=0
    fi
    for r in $(seq 1 "$REPS"); do
      echo -n "serie=oversub mode=$mode P=$P delta=$delta rep=$r  "
      t0=$(date +%s)
      timeout "$TIMEOUT" mpirun --oversubscribe -np "$P" --map-by node \
             --mca opal_set_max_sys_limits 1 "$BIN" "$N" "$delta" \
        || echo "[FALHOU/timeout P=$P mode=$mode rep=$r apos $(( $(date +%s) - t0 ))s]"
    done
  done
done

echo "# FIM"
