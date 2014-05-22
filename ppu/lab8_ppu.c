/* Tema 3 ASC
 * Arhip Alin-Gabriel 333CC
 * Mai 2014
 * lab8_ppu.c - Implementation on PPU
 */
#include <stdlib.h>
#include <stdio.h>
#include <errno.h>
#include <libspe2.h>
#include <pthread.h>
#include <libmisc.h>
#include <sys/time.h>
#include <time.h>
#include <math.h>
#include <string.h>

#include "btc.h"

extern spe_program_handle_t lab8_spu;

void *ppu_pthread_function(void *thread_arg) {

	spe_context_ptr_t ctx;
	pointers_t *arg = (pointers_t *) thread_arg;

	/* Create SPE context */
	if ((ctx = spe_context_create (0, NULL)) == NULL) {
            perror ("Failed creating context");
            exit (1);
        }

	/* Load SPE program into context */
	if (spe_program_load (ctx, &lab8_spu)) {
            perror ("Failed loading program");
            exit (1);
        }

	/* Run SPE context */
	unsigned int entry = SPE_DEFAULT_ENTRY;
	if (spe_context_run(ctx, &entry, 0,(void*)arg, (void*)sizeof(pointers_t), NULL) < 0) {  

		perror ("Failed running context");
		exit (1);
	}

	/* Destroy context */
	if (spe_context_destroy (ctx) != 0) {
            perror("Failed destroying context");
            exit (1);
        }

	pthread_exit(NULL);
}


int main(int argc,char* argv[]) {
	
	// sizeof(pointers_t)= 32 
	// sizeof(struct block2)= 80
	// cod propriu-zis
	struct timeval start,end;
	struct timeval de_la,pana_la;
	double timp_total=0,timp_scalat=0;
	int i,no_elems,j;

	gettimeofday(&start,NULL);

	if (argc != 6) {
		fprintf(stderr, "Usage: ./tema3 mod spu_threads in.pgm out.btc out.pgm\n");
		exit(1);
	}
	int mod = atoi(argv[1]);
	int spu_threads = atoi(argv[2]);	// Gives the number of SPE threads to create	
	if (mod == 1 ) {
		fprintf(stderr, "Varianta cu double buffering neimplementat! \n");
		exit(1);
	}
	
	pthread_t threads[spu_threads];
    	pointers_t thread_arg[spu_threads] __attribute__ ((aligned(16)));
	struct img imagine __attribute__ ((aligned(16)));	 	// imaginea intiala;
	struct c_img imag_comp;				 	// imaginea comprimata
   	read_pgm(argv[3],&imagine);			// citim imaginea 
	int size = imagine.width * imagine.height;		// size e dimensiunea imaginii (aria ei)
	short int A[size] __attribute__ ((aligned(16)));
	for (i=0 ; i< size ;i++) 
		A[i] = imagine.pixels[i];			// o incarcam in matricea A aliniata 

	no_elems = imagine.height/(N*spu_threads); // cate blocuri trimit fiecarui spu 
	int dim = no_elems * N; 		 // dim bytes, cate linii de pixeli trimit fiecarui spu  
	
	struct img imag_dec __attribute__ ((aligned(16))); 	// imaginea decomprimata(refacuta)
	struct block2* blocks= malloc_align(sizeof(struct block2)*(size/M),4);
	imag_dec.width = imagine.width;
	imag_dec.height = imagine.height;
	imag_dec.pixels = malloc_align(sizeof(short int)*size,4);
	
	
	for(i = 0; i < spu_threads; i++) {
		if (i == spu_threads-1) // ultimul spu ia restul liniilor ramase in caz ca height nu e multiplu de 16
			dim=imagine.height-((spu_threads-1)*no_elems*N);
		// populez structura de tip pointers_t pentru fiecare thread in parte:
		thread_arg[i].A = A + i*no_elems*N*imagine.width;
		thread_arg[i].B = blocks + i*no_elems*imagine.width/BLOCK_SIZE;
		thread_arg[i].C = imag_dec.pixels + i*no_elems*N*imagine.width;
		thread_arg[i].width = imagine.width;
		thread_arg[i].height = imagine.height;
		thread_arg[i].dim = dim;
		thread_arg[i].thread_id = i;	
	}
	//de aici incepe timpul de comprimare + decomprimare efectiv(realizat in spu)
	gettimeofday(&de_la,NULL);
	for(i = 0; i < spu_threads; i++) {
       		/* Create thread for each SPE context */
        	if (pthread_create (&threads[i], NULL, &ppu_pthread_function, &thread_arg[i]))  {
           		perror ("Failed creating thread");
            		exit (1);
        		}
		}
    	/* Wait for SPU-thread to complete execution.  */
	for (i = 0; i < spu_threads; i++) {
       		if (pthread_join (threads[i], NULL)) {
            		perror("Failed pthread_join");
        		exit (1);
        		}
    		}
	gettimeofday(&pana_la,NULL);
	i=0;
	int nr_blocks = imagine.width * imagine.height / M;
	imag_comp.blocks = (struct block*) _alloc(sizeof(struct block) * nr_blocks);
	imag_comp.width = imagine.width;
	imag_comp.height = imagine.height;
	while(i< imagine.width * imagine.height / M ) { // pentru toate blocurile
		j=0; // transfer valorile calculate din struct block2 catre struct block din imag_comp
		while(j<M) { 
			imag_comp.blocks[i].bitplane[j]=blocks[i].bitplane[j];
			j++;
			}
		imag_comp.blocks[i].a=blocks[i].a;
		imag_comp.blocks[i].b=blocks[i].b;
		i++;
	}	
	
	write_btc(argv[4],&imag_comp);
	write_pgm(argv[5],&imag_dec);
	gettimeofday(&end,NULL);
	// calculez timpii si ii afisez:
	timp_total  = GET_TIME_DELTA(start,end);
	timp_scalat = GET_TIME_DELTA(de_la,pana_la);
	printf("Encoding / Decoding time: %lf \n Total time: %lf \n", timp_scalat,timp_total);
	// gata
	return 0;
}
