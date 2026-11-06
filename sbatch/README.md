# Scripts de execução no cluster (Atlântica, 2 nós)

Submeter **sempre a partir da raiz do projeto**, nos **mesmos 2 nós** (descomente e
preencha o `--nodelist` em cada script). Cada script roda **10 repetições** por
configuração (variável `REPS`) e imprime uma linha por repetição em
`resultados/<job>-<id>.out` — esses arquivos são os tempos brutos da entrega.

Antes de rodar, **calibrar o N**: `N` está no topo de cada script (padrão 100000).
Ajuste para que o T₁ (`seq.sbatch`) fique entre **30 e 60 s** no Atlântica.
Para mudar sem editar o arquivo: `sbatch --export=ALL,N=120000 sbatch/seq.sbatch`.

## Ordem de submissão

| Ordem | Script | Nós | Binário | Séries (P) |
|---|---|---|---|---|
| 1 | `seq.sbatch` | 1 | `src/sequencial` | T₁ e T₁^δ (um δ por P) |
| 2 | `original.sbatch` | 2 `--exclusive` | `src/original` | 1, 3, 7, 15, 31 |
| 3 | `balanceado.sbatch` | 2 `--exclusive` | `src/balanceado` | 2, 4, 8, 16, 32, 31 |
| 4 | `oversub.sbatch` | 2 `--exclusive --overcommit` | `src/original` | 63…1023, 2× (padrão e `yield`) |

## Contrato de linha de comando dos binários (ainda a implementar)

Os scripts assumem esta interface — a implementação do código paralelo tem que casar:

- `mpirun -np P src/original N delta` — δ passado na linha de comando
  (calculado no script como `ceil(2N/(P+1))`, igual à referência sequencial).
- `mpirun -np P src/balanceado N` — **sem** δ; o binário decide as divisões pelo
  tamanho do comunicador (ajudante = `rank + 2^nível`, divide enquanto houver
  ajudante livre).
- `src/sequencial N [delta]` — já pronto (código do professor).

Compilar (mesmas flags de otimização em tudo):

```bash
gcc    -O2 -o src/sequencial  src/sequencial.c
mpicc  -O2 -o src/original    src/original.c
mpicc  -O2 -o src/balanceado  src/balanceado.c
```

## Análise

Depois que os jobs rodarem, as saídas ficam em `resultados/*.out` (uma linha por
repetição). Para as tabelas de mediana/mín/máx e os speed-ups:

```bash
python3 analise.py                 # le resultados/*.out
python3 analise.py resultados/orig-123.out resultados/seq-120.out
```

O script casa cada série paralela com a referência sequencial pelo δ, calcula
`S = T1/T_P`, `S^δ = T1^δ/T_P`, `E = S^δ/P` (e `E = S^δ/32` na série 63–1023),
avisa se alguma `verificacao != OK` e se alguma configuração não teve 10 repetições.

## Notas

- `--map-by node` distribui os ranks alternando entre os nós; registre no relatório
  como os processos caíram nos 2 nós (item de análise).
- A série `oversub` só mostra ganho se o processo parado ceder o núcleo — por isso
  as duas rodadas (`default` vs `OMPI_MCA_mpi_yield_when_idle=1`).
- O δ da versão balanceada com **P=31** não é único (folhas desiguais); a
  referência T₁^δ desse caso exige um `sequencial` adaptado à mesma árvore.
