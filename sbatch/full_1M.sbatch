#!/bin/bash
# =====================================================================
# Teste EXTRA com N = 1.000.000, TUDO num unico job (o cluster so deixa
# rodar 2 por vez). Da para submeter e deixar rodando a noite toda.
#
# Ordem dentro do job:
#   1. Sequencial: T1 (vetor inteiro) + T1^delta so dos niveis PROFUNDOS
#      (nivel 10 em diante). Os niveis baixos (delta grande) levariam horas
#      no Bubble e foram deixados de fora de proposito.
#   2. Original      (P = 1, 3, 7, 15, 31)
#   3. Balanceado    (P = 2, 4, 8, 16, 32)
#   4. Oversubscription (P = 63..1023, modos =0 e =1)
#   Todos com 3 repeticoes.
#
# Saida em resultados_1M/ para NAO misturar com o estudo N=200000.
# Analise depois:  python3 analise.py resultados_1M/*.out
#
# Observacao sobre S^delta: como o sequencial so cobre o nivel 10+, apenas
# o oversub P=1023 (delta=1954, nivel 10) tem referencia T1^delta casada;
# original e balanceado saem com tempo bruto e S (= T1/TP), sem S^delta/E.
#
# Submeter da raiz do projeto:  sbatch sbatch/full_1M.sbatch
#
#SBATCH --job-name=t3-1M
#SBATCH --nodes=2
#SBATCH --exclusive
#SBATCH --overcommit
#SBATCH --time=10:00:00
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

# Correcoes para o oversubscription em P alto (iguais ao oversub.sbatch):
# datastore 'hash' do PMIx e teto de descritores no maximo, senao P=1023
# estoura no lancamento / no limite de pipes.
export PMIX_MCA_gds=hash
ulimit -n "$(ulimit -Hn)" 2>/dev/null || true

echo "# nodelist=${SLURM_JOB_NODELIST:-?}  N=$N  REPS=$REPS  ulimit -n=$(ulimit -n)"
lscpu | grep -E 'Model name|Socket|Core\(s\)|Thread|^CPU\(s\)' || true

# ===== 1. SEQUENCIAL: T1 + niveis profundos (10+) =====
# T1: Bubble do vetor inteiro (nivel 1). CARO (~15-20 min por rodada).
for r in $(seq 1 "$REPS"); do
  echo -n "serie=T1 P=1 rep=$r  "
  $SEQ "$N"
done
# T1^delta so dos niveis profundos.  delta ~ N / 2^(nivel-1):
#   1954 = nivel 10  (casa com o oversub P=1023 -> da o S^delta dele)
#    977 = nivel 11      488 = nivel 12      244 = nivel 13      122 = nivel 14
for delta in 1954 977 488 244 122; do
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=T1d_orig P=- delta=$delta rep=$r  "
    $SEQ "$N" "$delta"
  done
done

# ===== 2. ORIGINAL (pai manda as duas metades e espera) =====
for P in 1 3 7 15 31; do
  delta=$(( (2*N + P) / (P + 1) ))
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=orig P=$P delta=$delta rep=$r  "
    mpirun -np "$P" --map-by node "$ORIG" "$N" "$delta"
  done
done

# ===== 3. BALANCEADO (pai fica com uma metade e tambem ordena) =====
for P in 2 4 8 16 32; do
  for r in $(seq 1 "$REPS"); do
    echo -n "serie=bal P=$P rep=$r  "
    mpirun -np "$P" --map-by node "$BAL" "$N"
  done
done

# ===== 4. OVERSUBSCRIPTION (versao original com muito mais P que threads) =====
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
      mpirun --oversubscribe -np "$P" --map-by node \
             --mca opal_set_max_sys_limits 1 "$ORIG" "$N" "$delta"
    done
  done
done

echo "# FIM"
