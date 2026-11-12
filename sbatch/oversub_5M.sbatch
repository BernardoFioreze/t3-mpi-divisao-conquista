#!/bin/bash
# =====================================================================
# Teste focado: OVERSUBSCRIPTION com N = 5.000.000, comparando os dois modos
#   - espera ativa  (OMPI_MCA_mpi_yield_when_idle=0)
#   - cede o nucleo (OMPI_MCA_mpi_yield_when_idle=1)
# So os TEMPOS dos dois modos (sem sequencial, sem T1 -> sem S/S^delta/E).
# O que interessa aqui e' a razao yield/ativa, que sai direto do Tp.
#
# P = 63..1023 (teto viavel em 2 nos; no teste de 1M, P>=2047 deu
# timeout/falha de lancamento). 3 repeticoes, com 'timeout' de guarda.
#
# Saida em resultados_5M/ (nao mistura com os outros estudos).
# Analise:  python3 analise.py resultados_5M/*.out
#
# Submeter da raiz do projeto:  sbatch sbatch/oversub_5M.sbatch
#
#SBATCH --job-name=t3-5M-ovs
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --overcommit
#SBATCH --time=06:00:00
#SBATCH --output=resultados_5M/oversub5M-%j.out
## Use SEMPRE os mesmos 2 nos:
## #SBATCH --nodelist=<no1>,<no2>

set -u
N=${N:-5000000}
REPS=${REPS:-3}
cd "${SLURM_SUBMIT_DIR:-.}"
BIN=src/original

# Limites do SO para P alto (iguais aos outros oversub).
export PMIX_MCA_gds=hash
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
ulimit -u "$(ulimit -Hu)" 2>/dev/null || true

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS  nofile=$(ulimit -n)  nproc=$(ulimit -u)"
lscpu | grep -E 'Model name|Socket|Core\(s\)|Thread|^CPU\(s\)' || true

# 'timeout' de 30 min por rodada: se um P travar, mata e segue.
for mode in default yield; do
  if [ "$mode" = yield ]; then
    export OMPI_MCA_mpi_yield_when_idle=1   # cede o nucleo enquanto espera
  else
    export OMPI_MCA_mpi_yield_when_idle=0   # espera ativa (explicito)
  fi
  for P in 63 127 255 511 1023; do
    delta=$(( (2*N + P) / (P + 1) ))
    for r in $(seq 1 "$REPS"); do
      echo -n "serie=oversub mode=$mode P=$P delta=$delta rep=$r  "
      timeout 1800 mpirun --oversubscribe -np "$P" --map-by node \
             --mca opal_set_max_sys_limits 1 "$BIN" "$N" "$delta" \
        || echo "[FALHOU/timeout P=$P mode=$mode rep=$r]"
    done
  done
done

echo "# FIM"
