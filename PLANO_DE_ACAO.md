# Plano de ação — T3: Divisão e conquista com MPI

> Baseado em `t3-mpi-divisao-conquista.pdf`. Objetivo: ordenar um vetor grande
> (Bubble Sort nas folhas, vetor em ordem decrescente) com divisão e conquista
> em MPI, medir no cluster Atlântica (2 nós) e **analisar** o desempenho.

## Visão geral: 3 códigos, 4 séries de medição

**Códigos:**
1. `sequencial.c` — **já dado pelo professor**. Só compilar e rodar. Dá as referências T₁ e T₁^δ.
2. **Paralelo original** (SPMD) — implementar a partir do pseudocódigo (anexo, pág. 5). Pai manda as duas metades e espera.
3. **Paralelo balanceado** — implementar. Pai fica com uma metade e ordena também (base: Radenski `mpi_mergesort.c`, trocando para Bubble Sort + vetor decrescente).

**Regra do δ:** não é escolhido à mão. Sai do nº de processos: com `P = 2^k − 1`, há `(P+1)/2` folhas e `δ = ⌈2n / (P+1)⌉` (arredonda para **cima**).

---

## Fase 0 — Preparação
- [ ] Repositório **git público** criado (link vai no cabeçalho do relatório). Estrutura sugerida: `src/`, `sbatch/`, `resultados/`, `relatorio/`.
- [ ] Baixar do Moodle: `sequencial.c`, artigo do Radenski e `mpi_mergesort.c`.
- [ ] Acesso ao Atlântica confirmado; rodar `lscpu` e **registrar**: 2 processadores Xeon E5520, **8 núcleos físicos + 16 threads (HT) por nó**, 2 nós = 16 físicos / 32 threads.
- [ ] Definir flags de compilação únicas (ex.: `-O2`) usadas em **todos** os códigos (seq e paralelo).

## Fase 1 — Referências sequenciais
- [ ] Compilar: `gcc -O2 -o sequencial sequencial.c`.
- [ ] Dimensionar **n** para que `./sequencial n` (T₁) leve **entre 30 e 60 s** no Atlântica. Registrar o n escolhido.
- [ ] Medir **T₁** = `./sequencial n` (Bubble no vetor inteiro).
- [ ] Medir **T₁^δ** = `./sequencial n delta` para **cada δ** que as versões paralelas usarem (um δ por valor de P).
- [ ] 10 repetições; guardar mediana, mínimo e máximo.
- [ ] Ganho de algoritmo = **T₁ / T₁^δ** (explica por que o speed-up pode passar de P).

## Fase 2 — Implementar o paralelo original
- [ ] Modelagem da árvore a partir do `rank`: como achar **pai**, **filho_esquerda**, **filho_direita** e **nível**. (Item 1 da análise.)
- [ ] Seguir o pseudocódigo: `MPI_Probe` → `MPI_Get_count` → aloca → `MPI_Recv`; decide dividir/conquistar por `tam <= delta`.
- [ ] Divisão: `meio = tam/2`; metade direita fica com `tam - meio` (cobre n ímpar). Manda **as duas** metades **antes** de esperar (requisito 3).
- [ ] Folha: `bubble_sort`. Interno: recebe dos filhos e `intercala`.
- [ ] Ler `n` e `delta` (ou nº de níveis) da linha de comando.
- [ ] `MPI_Wtime()` na raiz: do início da distribuição até a raiz ter o vetor ordenado (init do vetor **fora** da medição).
- [ ] `Verifica()` na raiz: vetor final == 1,2,…,n; imprimir OK/ERRO.
- [ ] Testar com vetor pequeno (ex.: n=40, δ=10, 7 processos) antes de escalar.

## Fase 3 — Medições do original
- [ ] Rodar com **1, 3, 7, 15, 31** processos, 2 nós **`--exclusive`**, via **`sbatch`**. (15 = um por núcleo físico; 31 usa HT.)
- [ ] 10 repetições por configuração; registrar mediana/min/máx.
- [ ] Anotar **como os processos foram distribuídos entre os 2 nós**.
- [ ] Calcular por configuração:
  - **S = T₁ / T_P** (contra Bubble inteiro; pode passar de P).
  - **S^δ = T₁^δ / T_P** (só paralelismo) e **E = S^δ / P** (eficiência).

## Fase 4 — Implementar e medir o balanceado
- [ ] Adaptar do Radenski: ao dividir, manda **uma** metade ao ajudante (`rank + 2^nível`) e **fica com a outra** para ordenar.
- [ ] Trocar o algoritmo das folhas para **Bubble Sort** e o vetor para **ordem decrescente** (condição 1 do enunciado).
- [ ] Saber explicar cada chamada MPI: por que o ajudante é `rank + 2^nível`, o que fazem `MPI_Isend` e `MPI_Request_free`, por que o buffer pode ser reaproveitado.
- [ ] Medir com **2, 4, 8, 16, 32 e 31** processos (16 = um por núcleo; 32 usa HT; 31 = comparação direta com o original).
- [ ] Olhar a **distribuição de carga com 31 processos** (P não é potência de 2 → folhas de tamanhos diferentes).

## Fase 5 — Balanceamento sem mexer no código (oversubscription)
- [ ] Rodar o **código original** com **63, 127, 255, 511, 1023** processos, 2 nós, `--overcommit`.
- [ ] Medir **cada** valor **duas vezes**:
  - padrão (Open MPI em **espera ativa** — não cede o núcleo);
  - com **`OMPI_MCA_mpi_yield_when_idle=1`** (cede o núcleo enquanto espera).
- [ ] Eficiência nessa série em relação às **32 threads**: `S^δ / 32`.
- [ ] A diferença entre as duas rodadas mostra o balanceamento que o **escalonador do SO** consegue fazer.

## Fase 6 — Análise (o que de fato vale nota)
> "Analisar = explicar o que causou os números", não repetir o gráfico. Cobrir os 7 pontos:
1. [ ] **Modelagem** da árvore (pai/filhos pelo rank) e o que muda na versão balanceada.
2. [ ] **Speed-up e eficiência** das duas versões, separando ganho de **paralelismo (S^δ)** do ganho de **algoritmo (T₁/T₁^δ)**; distribuição de carga no balanceado com 31.
3. [ ] **Balanceamento por nível** da árvore na versão original (quem fica ocioso e quando).
4. [ ] Ganho com **HT** (15 vs 31; 16 vs 32).
5. [ ] Ganho com **balanceamento**: sem código (mais processos) e com código (pai trabalha).
6. [ ] Desempenho **63→1023**, espera ativa vs núcleo cedido, e o que isso diz do escalonador.
7. [ ] Uso de **ferramentas de IA**, se houve.

## Fase 7 — Relatório, entrega e apresentação
- [ ] Relatório **PDF**: 1 página de análise + código nas páginas seguintes, coluna única, **com números de linha**; cabeçalho compacto com integrantes; toda figura/tabela com legenda e referenciada; trechos do código citados por nº de linha.
- [ ] Tabelas sempre com **mediana, mínimo e máximo**.
- [ ] Entregar no Moodle: o PDF; scripts `sbatch` + saídas do Slurm (tempos brutos) no repo git público ou em `.zip`.
- [ ] Apresentação ≤ 10 min, foco em modelagem e análise. **Cada integrante** tem que saber explicar qualquer chamada MPI e qualquer número. (Faltar/não apresentar = zero individual.)

---

## Matriz de medições (resumo)

| Série | Código | Processos (P) | Observações |
|---|---|---|---|
| Referência | sequencial | 1 | T₁ e T₁^δ (um T₁^δ por δ) |
| Original | paralelo v1 | 1, 3, 7, 15, 31 | 2 nós `--exclusive`, `sbatch` |
| Balanceado | paralelo v2 | 2, 4, 8, 16, 32, 31 | 16=1/núcleo, 32=HT |
| Oversubscription | paralelo v1 | 63, 127, 255, 511, 1023 | `--overcommit`, 2× (com/sem `OMPI_MCA_mpi_yield_when_idle=1`) |

Todas: **10 repetições**, verificação de ordenação obrigatória, `MPI_Wtime()` na raiz.

## Fórmulas
- `δ = ⌈2n / (P+1)⌉`  (P = 2^k − 1)
- `S  = T₁  / T_P`      (vs Bubble inteiro)
- `S^δ = T₁^δ / T_P`    (só paralelismo)
- `E  = S^δ / P`        (eficiência; na série 63–1023, usar `S^δ / 32`)
- Ganho de algoritmo = `T₁ / T₁^δ`
