/*
 * T3: versao paralela BALANCEADA (divisao e conquista com MPI).
 *
 * Diferenca para a versao original: ao dividir, o processo NAO entrega as duas
 * metades e fica parado. Ele manda UMA metade para um ajudante e fica com a
 * outra, que ele mesmo ordena. Assim os processos internos tambem conquistam,
 * e quase ninguem fica ocioso (a arvore "abre para um lado so").
 *
 * Modelagem: um processo que ainda tem niveis abaixo manda a metade direita
 * para o ajudante
 *
 *     ajudante = rank + 2^nivel
 *
 * e ordena a metade esquerda sozinho, descendo para o nivel abaixo (onde o
 * proximo ajudante e' rank + 2^(nivel-1)). Um processo nao-raiz descobre em que
 * nivel foi criado pela posicao do bit menos significativo do seu rank:
 *
 *     nivel_inicial = ctz(rank) - 1      (ctz = contagem de zeros a` direita)
 *     pai           = rank & (rank - 1)  (rank sem o bit menos significativo)
 *
 * A DIVISAO SEMPRE PARTE O DADO AO MEIO. Com P potencia de 2, todas as folhas
 * terminam com N/P elementos; com P = 2^k - 1, alguns processos ficam sem
 * ajudante em um nivel e ordenam uma folha maior (folhas de tamanhos diferentes).
 *
 * Uso:   mpirun -np P ./balanceado N
 *   (nao recebe delta: as divisoes sao decididas pela quantidade de processos)
 *
 * Compilacao: mpicc -O2 -o balanceado balanceado.c
 *
 * Base: ideia do mpi_mergesort.c de A. Radenski (GPL), com as folhas trocadas
 * para Bubble Sort e o vetor em ordem decrescente (condicao 1 do enunciado).
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

/*
 * Ordena data[0, n) usando este processo e os ajudantes abaixo do nivel dado.
 * Tenta dividir no maior nivel possivel; se o ajudante daquele nivel nao existe
 * (rank + 2^nivel >= P), desce um nivel. Sem nenhum ajudante abaixo, vira folha.
 */
void sort_balanced(int *data, int n, int rank, int nivel, int P, int *aux)
{
    while (nivel >= 0) {
        int ajudante = rank + (1 << nivel);
        if (ajudante < P) {
            int meio = n / 2;
            /* Mando a metade DIREITA ao ajudante e sigo na esquerda. Isend para
             * nao bloquear; Request_free porque nao vou testar a conclusao: o
             * MPI_Recv abaixo (do mesmo ajudante) so retorna depois que ele
             * recebeu este envio, entao o envio ja terminou e data[meio..n)
             * pode ser reescrito com o resultado. */
            MPI_Request req;
            MPI_Isend(&data[meio], n - meio, MPI_INT, ajudante, TAG,
                      MPI_COMM_WORLD, &req);
            MPI_Request_free(&req);

            /* Ordeno a metade ESQUERDA eu mesmo (os niveis abaixo deste). */
            sort_balanced(data, meio, rank, nivel - 1, P, aux);

            /* Recebo a metade direita ja ordenada e intercalo. */
            MPI_Recv(&data[meio], n - meio, MPI_INT, ajudante, TAG,
                     MPI_COMM_WORLD, MPI_STATUS_IGNORE);
            intercala(data, n, aux);
            return;
        }
        nivel--;                 /* ajudante nao existe neste nivel: desce um */
    }
    bubble_sort(data, n);        /* sem ajudante abaixo: sou folha */
}

int main(int argc, char **argv)
{
    MPI_Init(&argc, &argv);

    int my_rank, num_procs;
    MPI_Comm_rank(MPI_COMM_WORLD, &my_rank);
    MPI_Comm_size(MPI_COMM_WORLD, &num_procs);

    if (argc < 2) {
        if (my_rank == 0)
            fprintf(stderr, "uso: mpirun -np P %s N\n", argv[0]);
        MPI_Finalize();
        return 1;
    }
    int N = atoi(argv[1]);
    if (N < 1) {
        if (my_rank == 0)
            fprintf(stderr, "N deve ser positivo\n");
        MPI_Finalize();
        return 1;
    }

    int n;
    int *data;

    if (my_rank == 0) {
        n = N;                                   /* raiz: gero o vetor */
        data = malloc((size_t)n * sizeof(int));
        for (int i = 0; i < n; i++)
            data[i] = n - i;                     /* ordem decrescente (pior caso) */
    } else {
        int pai = my_rank & (my_rank - 1);       /* rank sem o bit menos significativo */
        MPI_Status status;
        MPI_Probe(pai, TAG, MPI_COMM_WORLD, &status);
        MPI_Get_count(&status, MPI_INT, &n);
        data = malloc((size_t)n * sizeof(int));
        MPI_Recv(data, n, MPI_INT, pai, TAG, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    }
    int *aux = malloc((size_t)n * sizeof(int));
    if (!data || !aux) {
        fprintf(stderr, "rank %d: sem memoria para n = %d\n", my_rank, n);
        MPI_Abort(MPI_COMM_WORLD, 1);
    }

    if (my_rank == 0) {
        /* maior nivel L tal que o ajudante 2^L ainda existe (2^L < P) */
        int nivel_raiz = -1;
        for (int L = 0; (1 << L) < num_procs; L++)
            nivel_raiz = L;

        double t0 = MPI_Wtime();                 /* regiao medida: so a raiz */
        sort_balanced(data, n, 0, nivel_raiz, num_procs, aux);
        double t1 = MPI_Wtime();

        long long erros = 0;                     /* verificacao: 1,2,...,N */
        for (int i = 0; i < n; i++)
            if (data[i] != i + 1)
                erros++;

        printf("versao=balanceado N=%d P=%d tempo=%.6f verificacao=%s\n",
               N, num_procs, t1 - t0, erros == 0 ? "OK" : "ERRO");
    } else {
        int nivel_inicial = __builtin_ctz(my_rank) - 1;
        sort_balanced(data, n, my_rank, nivel_inicial, num_procs, aux);
        MPI_Send(data, n, MPI_INT, my_rank & (my_rank - 1), TAG, MPI_COMM_WORLD);
    }

    free(data);
    free(aux);
    MPI_Finalize();
    return 0;
}
