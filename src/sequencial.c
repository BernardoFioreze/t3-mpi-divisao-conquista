/*
 * T3: ordenação de um vetor, versão sequencial e rotinas para a versão paralela.
 *
 * O vetor começa em ordem decrescente (pior caso do Bubble Sort). Dois modos:
 *
 *   ./sequencial n         ordena o vetor inteiro com o Bubble Sort (T1)
 *   ./sequencial n delta   percorre a mesma árvore da versão paralela em um só
 *                          processo: divide enquanto o pedaço passa de delta,
 *                          ordena as folhas com o Bubble Sort e intercala na
 *                          volta (T1 com o mesmo delta)
 *
 * A diferença entre os dois tempos é o ganho de algoritmo: como o Bubble Sort
 * é quadrático, ordenar as folhas custa menos que ordenar o vetor inteiro.
 * As rotinas bubble_sort() e intercala() são as que a versão paralela usa.
 *
 * Compilação: gcc -O2 -o sequencial sequencial.c
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

/* Conquista: Bubble Sort com parada antecipada quando não houve troca. */
void bubble_sort(int *v, int n)
{
    int trocou = 1;
    for (int fim = n - 1; fim > 0 && trocou; fim--) {
        trocou = 0;
        for (int i = 0; i < fim; i++) {
            if (v[i] > v[i + 1]) {
                int t = v[i];
                v[i] = v[i + 1];
                v[i + 1] = t;
                trocou = 1;
            }
        }
    }
}

/*
 * Combinação: intercala as metades ordenadas v[0, n/2) e v[n/2, n), que são
 * as duas partes devolvidas pelos filhos. O resultado volta para v; aux é
 * área de trabalho com pelo menos n posições.
 */
void intercala(int *v, int n, int *aux)
{
    int meio = n / 2;
    int i = 0, j = meio, k = 0;

    while (i < meio && j < n)
        aux[k++] = (v[i] <= v[j]) ? v[i++] : v[j++];
    while (i < meio)
        aux[k++] = v[i++];
    while (j < n)
        aux[k++] = v[j++];

    memcpy(v, aux, (size_t)n * sizeof(int));
}

/*
 * A árvore da versão paralela, percorrida em um só processo. A metade
 * esquerda tem n/2 elementos, como a que o pai envia ao filho da esquerda.
 */
void ordena(int *v, int n, int delta, int *aux)
{
    if (n <= delta) {                   /* conquista */
        bubble_sort(v, n);
        return;
    }
    int meio = n / 2;                   /* divisão */
    ordena(v, meio, delta, aux);
    ordena(v + meio, n - meio, delta, aux + meio);
    intercala(v, n, aux);               /* combinação */
}

static double agora(void)
{
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec + t.tv_nsec * 1e-9;
}

int main(int argc, char **argv)
{
    if (argc != 2 && argc != 3) {
        fprintf(stderr, "uso: %s n [delta]\n", argv[0]);
        return 1;
    }
    int n = atoi(argv[1]);
    int delta = (argc == 3) ? atoi(argv[2]) : n;   /* sem delta: vetor inteiro */
    if (n < 1 || delta < 1) {
        fprintf(stderr, "n e delta devem ser positivos\n");
        return 1;
    }

    /* Na pilha, 10^6 ints estouram: aloca no heap. */
    int *v = malloc((size_t)n * sizeof(int));
    int *aux = malloc((size_t)n * sizeof(int));
    if (!v || !aux) {
        fprintf(stderr, "sem memória para n = %d\n", n);
        return 1;
    }

    for (int i = 0; i < n; i++)          /* fora da região medida */
        v[i] = n - i;

    double t0 = agora();
    ordena(v, n, delta, aux);            /* região medida; com delta = n, é só o Bubble Sort */
    double t1 = agora();

    /* Verificação: o resultado tem de ser exatamente 1, 2, ..., n. */
    long long erros = 0;
    for (int i = 0; i < n; i++)
        if (v[i] != i + 1)
            erros++;

    printf("n=%d delta=%d tempo=%.6f verificacao=%s\n",
           n, delta, t1 - t0, erros == 0 ? "OK" : "ERRO");

    free(v);
    free(aux);
    return erros != 0;
}
