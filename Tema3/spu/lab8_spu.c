/* Tema 3 ASC
 * Arhip Alin-Gabriel 333CC
 * Mai 2014
 * lab8_spu.c - SPU implementation
 */
#include <stdio.h>
#include <spu_intrinsics.h>
#include <spu_mfcio.h>
#include <math.h>
#include <stdlib.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <string.h>
#include <sys/time.h>

uint32_t tag_id;

#include "../ppu/btc.h"

struct block2 bl __attribute__ ((aligned(16)));

pointers_t p __attribute__ ((aligned(16)));

void compres_and_decompres(pointers_t p,struct block2 bl) {
	
	int i,j,dim,a,b,k,l=0,width,row,col,bt_index,q,tmp;	
	double f1,f2,mean,stdev;
	short int A[M] __attribute__ ((aligned(16)));
	short int C[M] __attribute__ ((aligned(16)));

	// citim in Local Store datele necesare (width si dim)
	width = p.width;

	for(dim=p.dim; dim > 0; dim -= BLOCK_SIZE) {	
		for (k=0; k*BLOCK_SIZE < width;k++) {
			// realizam compresia:
			for(i=0;i<BLOCK_SIZE;i++) {
		
				mfc_get(A+BLOCK_SIZE*i, (unsigned int)(p.A+k*BLOCK_SIZE+(l+i)*width),BLOCK_SIZE*sizeof(short int),tag_id, 0,0);
				waittag(tag_id);
			}

			
			// mare parte din codul urmator l-am luat din main.c varianta seriala:
			//compute mean
			mean = 0; 	// mean=media aritmetica
			for (i = 0; i < BLOCK_SIZE*BLOCK_SIZE; i++){
				mean += A[i];	
				}
			mean /= (BLOCK_SIZE * BLOCK_SIZE);

			//compute standard deviation
			stdev = 0;	// stdev=deviatia standard
			for (row = 0; row < BLOCK_SIZE; row++){
				for (col = 0; col < BLOCK_SIZE; col++){
					stdev += (A[row * BLOCK_SIZE + col] - mean) * (A[row * BLOCK_SIZE + col] - mean);
				}
			}
			stdev /= (BLOCK_SIZE * BLOCK_SIZE);
			stdev = sqrt (stdev);

			//compute bitplane
			bt_index = 0;
			q = 0;
			for (i = 0; i < BLOCK_SIZE*BLOCK_SIZE; i++){
					tmp = (A[i] > mean ? 1 : 0);
					bl.bitplane[i] = tmp;
					q += tmp;
				}

			//compute a and b
		    	if (q == 0){
		        	a = b = (int)mean;
		    	}
		    	else {
		    		f1 = sqrt((float)q / (M - q));
		        	f2 = sqrt((float)(M - q) / q);
				a = (int)(mean - stdev * f1);
	    			b = (int)(mean + stdev * f2);
		    	}
	  		
			//avoid conversion issues due to precision errors
			if (a < 0)
		        	a = 0;
		   	if (b > 255)
		        	b = 255;	
	
			bl.a = (unsigned char)a;
			bl.b = (unsigned char)b;
			
			// realizam acum decompresia:
			for (i=0; i < BLOCK_SIZE * BLOCK_SIZE; i++)
				C[i] = (bl.bitplane[i] ? bl.b : bl.a);

			for (j=0; j < BLOCK_SIZE ; j++)	{
				mfc_put(C+BLOCK_SIZE*j, (unsigned int)(p.C+k*BLOCK_SIZE+(l+j)*width),BLOCK_SIZE*sizeof(short int),tag_id, 0,0);
				waittag(tag_id);
				}	
			
			}
		l += BLOCK_SIZE;
	}
}

int main(unsigned long long speid, unsigned long long argp, unsigned long long envp) {


	if ((tag_id = mfc_tag_reserve())== MFC_TAG_INVALID){
		printf("SPU: ERROR can't allocate tag ID\n"); 
		return -1;
	}
	// obtinem prin DMA structura cu pointeri si dimensiunea transferurilor:
	mfc_get(&p, argp, sizeof(pointers_t), tag_id, 0, 0);
	waittag(tag_id);
	// realizam compresia si decompresia in acelasi pas:
	compres_and_decompres(p,bl);
	// gata
	return 0;
}
