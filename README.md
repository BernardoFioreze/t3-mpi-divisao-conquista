# T3 — Divisão e conquista com MPI (ordenação, Bubble Sort nas folhas)

Integrantes: _(preencher)_

Implementação do T3: ordenar um vetor grande (em ordem decrescente, pior caso do
Bubble Sort) com divisão e conquista em MPI, medir no cluster Atlântica (2 nós) e
analisar o desempenho.

## Estrutura

- `src/sequencial.c` — referências sequenciais T₁ e T₁^δ (código do professor).
- `src/original.c` — versão paralela SPMD (pai manda as duas metades e espera).
- `src/balanceado.c` — versão balanceada (pai fica com uma metade e ordena também).
- `sbatch/` — scripts de execução no cluster + `sbatch/README.md` (como rodar).
- `analise.py` — lê `resultados/*.out` e calcula mediana/mín/máx, S, S^δ e eficiência.
- `resultados/` — saídas do Slurm com os tempos brutos.
- `PLANO_DE_ACAO.md` — plano de trabalho com checkboxes.

## Compilar

```bash
gcc   -O2 -o src/sequencial  src/sequencial.c
mpicc -O2 -o src/original    src/original.c
mpicc -O2 -o src/balanceado  src/balanceado.c
```

## Rodar e analisar

Ver `sbatch/README.md`. Em resumo: calibrar o `N`, fixar os 2 nós, submeter os
jobs na ordem `seq → original → balanceado → oversub`, e rodar `python3 analise.py`.
