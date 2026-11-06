/*
 * T3: versao paralela ORIGINAL (divisao e conquista com MPI), modelo da Figura 1.
 *
 * SPMD: todos os processos rodam este mesmo binario. O papel de cada um (raiz,
 * interno ou folha), seu pai e seus filhos saem do rank, com a arvore numerada
 * como na Figura 1 (p0 -> p1,p2 ; p1 -> p3,p4 ; p2 -> p5,p6 ...). Essa numeracao
 * e a indexacao de um heap binario:
 *
 *     filho_esquerda(rank) = 2*rank + 1
 *     filho_direita(rank)  = 2*rank + 2
 *     pai(rank)            = (rank - 1) / 2
 *
 * Um processo e FOLHA quando seus filhos nao existem no comunicador. Com
 * P = 2^k - 1 processos e delta = ceil(2N/(P+1)), as folhas recebem pedacos
 * <= delta e a arvore ocupa exatamente os P processos.
 *
 * Uso:   mpirun -np P ./original N [delta]
 *   N      tamanho do vetor
 *   delta  limite para conquistar; se omitido, usa ceil(2N/(P+1))
 *
 * Compilacao: mpicc -O2 -o original original.c
 */
#include <mpi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TAG 0

/* Conquista: Bubble Sort com parada antecipada quando nao houve troca. */
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

/* Combinacao: intercala as metades ordenadas v[0, n/2) e v[n/2, n). */
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

int main(int argc, char **argv)
{
    MPI_Init(&argc, &argv);

    int my_rank, num_procs;
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &num_procs);

    if (argc != 2 && argc != 3) {
        if (my_rank == 0)
            fprintf(stderr, "uso: mpirun -np P %s N [delta]\n", argv[0]);
        MPI_Finalize();
        return 1;
    }
    int N = atoi(argv[1]);
    /* delta padrao: ceil(2N/(P+1)), que faz a arvore caber nos P processos. */
    int delta = (argc == 3) ? atoi(argv[2])
                            : (2 * N + num_procs) / (num_procs + 1);
    if (N < 1 || delta < 1) {
        if (my_rank == 0)
            fprintf(stderr, "N e delta devem ser positivos\n");
        MPI_Finalize();
        return 1;
    }

    /* Quem sou eu na arvore. */
    int pai            = (my_rank - 1) / 2;
    int filho_esquerda = 2 * my_rank + 1;
    int filho_direita  = 2 * my_rank + 2;

    int tam_vetor;
    int *vetor;

    /* --- recebo (ou gero, se sou a raiz) o meu pedaco --- */
    if (my_rank != 0) {
        MPI_Status status;
        MPI_Probe(pai, TAG, MPI_COMM_WORLD, &status);   /* espero a mensagem do pai */
        MPI_Get_count(&status, MPI_INT, &tam_vetor);    /* descubro o tamanho */
        vetor = malloc((size_t)tam_vetor * sizeof(int));
        MPI_Recv(vetor, tam_vetor, MPI_INT, pai, TAG, MPI_COMM_WORLD,
                 MPI_STATUS_IGNORE);
    } else {
        tam_vetor = N;                                   /* sou a raiz: gero o vetor */
        vetor = malloc((size_t)tam_vetor * sizeof(int));
        for (int i = 0; i < tam_vetor; i++)
            vetor[i] = tam_vetor - i;                    /* ordem decrescente (pior caso) */
    }
    int *aux = malloc((size_t)tam_vetor * sizeof(int));
    if (!vetor || !aux) {
        fprintf(stderr, "rank %d: sem memoria para tam = %d\n", my_rank, tam_vetor);
        MPI_Abort(MPI_COMM_WORLD, 1);
    }

    /* Regiao medida: so a raiz cronometra, do inicio da distribuicao ate ter
     * o vetor inteiro ordenado. A geracao do vetor fica de fora. */
    double t0 = 0.0;
    if (my_rank == 0)
        t0 = MPI_Wtime();

    /* --- dividir ou conquistar? --- */
    if (tam_vetor <= delta) {
        bubble_sort(vetor, tam_vetor);                   /* conquisto (folha) */
    } else {
        int meio = tam_vetor / 2;                        /* divido */
        /* Mando as DUAS metades antes de esperar qualquer resultado, para que
         * os dois filhos trabalhem ao mesmo tempo (requisito 3). */
        MPI_Send(&vetor[0],    meio,             MPI_INT, filho_esquerda, TAG, MPI_COMM_WORLD);
        MPI_Send(&vetor[meio], tam_vetor - meio, MPI_INT, filho_direita,  TAG, MPI_COMM_WORLD);
        /* Recebo de volta os dois pedacos ordenados. */
        MPI_Recv(&vetor[0],    meio,             MPI_INT, filho_esquerda, TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        MPI_Recv(&vetor[meio], tam_vetor - meio, MPI_INT, filho_direita,  TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        intercala(vetor, tam_vetor, aux);                /* combino */
    }

    /* --- devolvo ao pai; se sou a raiz, o vetor ja esta inteiro e ordenado --- */
    if (my_rank != 0) {
        MPI_Send(vetor, tam_vetor, MPI_INT, pai, TAG, MPI_COMM_WORLD);
    } else {
        double t1 = MPI_Wtime();

        long long erros = 0;                             /* verificacao: 1,2,...,N */
        for (int i = 0; i < tam_vetor; i++)
            if (vetor[i] != i + 1)
                erros++;

        printf("versao=original N=%d delta=%d P=%d tempo=%.6f verificacao=%s\n",
               N, delta, num_procs, t1 - t0, erros == 0 ? "OK" : "ERRO");
    }

    free(vetor);
    free(aux);
    MPI_Finalize();
    return 0;
}
