#!/bin/bash
# =====================================================================
# Teste EXTRA com N = 1.000.000, TUDO num unico job (o cluster so deixa
# rodar 2 por vez). Da para submeter e deixar rodando a noite toda.
#
# Escopo escolhido:
#   1. Sequencial: T1^delta SO dos niveis profundos 10..13 (sem T1 / vetor
#      inteiro). delta = 1954, 977, 489, 245.  Esses delta CASAM com o
#      oversub abaixo -> dao o S^delta do oversub.
#   2. Original     (P = 3, 7, 15, 31)      -> so tempo bruto (sem referencia)
#   3. Balanceado   (P = 2, 4, 8, 16, 32)   -> so tempo bruto (sem referencia)
#   4. Oversub      (P = 1023, 2047, 4095, 8191; niveis 10..13), modos =0 e =1
#   Todos com 3 repeticoes.
#
#   OBS: original/balanceado NAO tem S nem S^delta aqui (nao ha T1 nem
#   sequencial nos delta grandes deles) -- saem so com Tp, de proposito.
#   So o oversub tem S^delta (seu delta casa com o sequencial).
#
# Saida em resultados_1M/ para NAO misturar com o estudo N=200000.
# Analise:  python3 analise.py resultados_1M/*.out
#
# Submeter da raiz do projeto:  sbatch sbatch/full_1M.sbatch
#
#SBATCH --job-name=t3-1M
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --overcommit
#SBATCH --time=06:00:00
#SBATCH --output=resultados_1M/full1M-%j.out
## Use SEMPRE os mesmos 2 nos:
## #SBATCH --nodelist=<no1>,<no2>

set -u
N=${N:-1000000}
REPS=${REPS:-3}
cd "${SLURM_SUBMIT_DIR:-.}"
SEQ=src/sequencial
ORIG=src/original
BAL=src/balanceado

# Limites do SO para P alto (ate 8191 processos em 2 nos): datastore 'hash'
# do PMIx, teto de descritores e de processos no maximo permitido.
export PMIX_MCA_gds=hash
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true
ulimit -u "$(ulimit -Hu)" 2>/dev/null || true

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS  nofile=$(ulimit -n)  nproc=$(ulimit -u)"
lscpu | grep -E 'Model name|Socket|Core\(s\)|Thread|^CPU\(s\)' || true

# ===== 1. SEQUENCIAL: T1^delta so dos niveis profundos 10..13 =====
# delta = N / 2^(nivel-1), ajustado para casar EXATO com o delta do oversub:
#   1954 = nivel 10 (= P 1023)   977 = nivel 11 (= P 2047)
#    489 = nivel 12 (= P 4095)   245 = nivel 13 (= P 8191)
for delta in 1954 977 489 245; do
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=T1d_orig P=- delta=$delta rep=$r  "
    $SEQ "$N" "$delta"
  done
done

# ===== 2. ORIGINAL (so tempo bruto; P=1 = vetor inteiro fica de fora) =====
for P in 3 7 15 31; do
  delta=$(( (2*N + P) / (P + 1) ))
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=orig P=$P delta=$delta rep=$r  "
    mpirun -np "$P" --map-by node "$ORIG" "$N" "$delta"
  done
done

# ===== 3. BALANCEADO (so tempo bruto) =====
for P in 2 4 8 16 32; do
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=bal P=$P rep=$r  "
    mpirun -np "$P" --map-by node "$BAL" "$N"
  done
done

# ===== 4. OVERSUBSCRIPTION (P alto: 1023..8191; delta casa com o sequencial) =====
# 'timeout' protege a noite: se um P alto travar, mata em 20 min e segue.
for mode in default yield; do
  if [ "$mode" = yield ]; then
    export OMPI_MCA_mpi_yield_when_idle=1   # cede o nucleo enquanto espera
  else
    export OMPI_MCA_mpi_yield_when_idle=0   # espera ativa (explicito)
  fi
  for P in 1023 2047 4095 8191; do
    delta=$(( (2*N + P) / (P + 1) ))
    for r in $(seq 1 "$REPS"); do
      echo -n "serie=oversub mode=$mode P=$P delta=$delta rep=$r  "
      timeout 1200 mpirun --oversubscribe -np "$P" --map-by node \
             --mca opal_set_max_sys_limits 1 "$ORIG" "$N" "$delta" \
        || echo "[FALHOU/timeout P=$P mode=$mode rep=$r]"
    done
  done
done

echo "# FIM"
