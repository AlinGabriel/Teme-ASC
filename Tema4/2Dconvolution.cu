/*
 * Copyright 1993-2006 NVIDIA Corporation.  All rights reserved.
 *
 * NOTICE TO USER:
 *
 * This source code is subject to NVIDIA ownership rights under U.S. and
 * international Copyright laws.
 *
 * This software and the information contained herein is PROPRIETARY and
 * CONFIDENTIAL to NVIDIA and is being provided under the terms and
 * conditions of a Non-Disclosure Agreement.  Any reproduction or
 * disclosure to any third party without the express written consent of
 * NVIDIA is prohibited.
 *
 * NVIDIA MAKES NO REPRESENTATION ABOUT THE SUITABILITY OF THIS SOURCE
 * CODE FOR ANY PURPOSE.  IT IS PROVIDED "AS IS" WITHOUT EXPRESS OR
 * IMPLIED WARRANTY OF ANY KIND.  NVIDIA DISCLAIMS ALL WARRANTIES WITH
 * REGARD TO THIS SOURCE CODE, INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY, NONINFRINGEMENT, AND FITNESS FOR A PARTICULAR PURPOSE.
 * IN NO EVENT SHALL NVIDIA BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL,
 * OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
 * OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE
 * OR OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE
 * OR PERFORMANCE OF THIS SOURCE CODE.
 *
 * U.S. Government End Users.  This source code is a "commercial item" as
 * that term is defined at 48 C.F.R. 2.101 (OCT 1995), consisting  of
 * "commercial computer software" and "commercial computer software
 * documentation" as such terms are used in 48 C.F.R. 12.212 (SEPT 1995)
 * and is provided to the U.S. Government only as a commercial end item.
 * Consistent with 48 C.F.R.12.212 and 48 C.F.R. 227.7202-1 through
 * 227.7202-4 (JUNE 1995), all U.S. Government End Users acquire the
 * source code with only those rights set forth herein.
 */

// includes, system
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <math.h>

#include <helper_cuda.h>
#include <helper_timer.h>
#include <helper_functions.h>
#include <helper_math.h>

// includes, project
#include "2Dconvolution.h"

////////////////////////////////////////////////////////////////////////////////
// declarations, forward

extern "C"
void computeGold(float*, const float*, const float*, unsigned int, unsigned int);

Matrix AllocateDeviceMatrix(int width, int height);
Matrix AllocateMatrix(int width, int height);
void FreeDeviceMatrix(Matrix* M);
void FreeMatrix(Matrix* M);

void ConvolutionOnDevice(const Matrix M, const Matrix N, Matrix P);
void ConvolutionOnDeviceShared(const Matrix M, const Matrix N, Matrix P);

////////////////////////////////////////////////////////////////////////////////
// Înmulțirea fără memorie partajată
////////////////////////////////////////////////////////////////////////////////
__global__ void ConvolutionKernel(Matrix M, Matrix N, Matrix P)
{
	int i = blockIdx.y * blockDim.y + threadIdx.y;	
	int j = blockIdx.x * blockDim.x + threadIdx.x;
	int hB=N.height;
	int wB=N.width;
	float sum = 0;
	// For each element in the result matrix matrix
	if ( i< N.height && j<N.width)
	{
	// check the start and end values of m and n to prevent overrunning the matrix edges
		unsigned int mbegin = (i < 2)? 2 - i : 0;
		unsigned int mend = (i > (hB - 3))? hB - i + 2 : 5;
		unsigned int nbegin = (j < 2)? 2 - j : 0;
		unsigned int nend = (j > (wB - 3))? (wB-j) + 2 : 5;
		// overlay A over B centered at element (i,j).  For each 
		//  overlapping element, multiply the two and accumulate
		for(unsigned int m = mbegin; m < mend; ++m) 
			for(unsigned int n = nbegin; n < nend; n++) 
				sum += M.elements[m * 5 + n] * N.elements[wB*(i + m - 2) + (j+n - 2)];

		// store the result
		P.elements[i*wB + j] = (float)sum;
        }

}

///// functii ajutatoare:

// Get a matrix element
__device__ float GetElement(const Matrix A, int row, int col)
{
  return A.elements[row * A.pitch + col];
}

// Set a matrix element
__device__ void SetElement(Matrix A, int row, int col, float value)
{
  A.elements[row * A.pitch + col] = value;
}

////////////////////////////////////////////////////////////////////////////////
// Înmulțirea cu memorie partajată
////////////////////////////////////////////////////////////////////////////////
__global__ void ConvolutionKernelShared(Matrix M, Matrix N, Matrix P)
{
	// Shared memory used to store M and part of N:
	__shared__ float Mds[KERNEL_SIZE][KERNEL_SIZE];
	__shared__ float Nds[BLOCK_SIZE+4][BLOCK_SIZE+4];

	int by = blockIdx.y;		// Block row and column
	int bx = blockIdx.x;	
	
	int tx = threadIdx.x;		// Thread row and column within submatrix
	int ty = threadIdx.y;

	int row = by*BLOCK_SIZE + ty;	// indecsi in matricea mare.
	int col = bx*BLOCK_SIZE + tx;

	// Load in shared memory kernel matrix M 
	for(int i = 0; i <= KERNEL_SIZE/BLOCK_SIZE; i++)
		for(int j = 0; j <= KERNEL_SIZE/BLOCK_SIZE; j++)
			// If address is inside the kernel , load it into shared memory:
			if(tx+i*BLOCK_SIZE < KERNEL_SIZE && ty+j*BLOCK_SIZE < KERNEL_SIZE)
				Mds[ty+j*BLOCK_SIZE][tx+i*BLOCK_SIZE] = GetElement(M,ty+j*BLOCK_SIZE, tx+i*BLOCK_SIZE);

	// Load in shared memory matrix N , and zeroes around the block where necesarly:
	for(int i = 1; i <= (KERNEL_SIZE/2)/BLOCK_SIZE; i++)
		for(int j = 1; j <= (KERNEL_SIZE/2)/BLOCK_SIZE; j++)
			// If index is a valid element of N and if it is needed
			// It will be needed if it fits into our Nds[20][20]
			if(tx+i*BLOCK_SIZE+2 < BLOCK_SIZE+4 && ty+j*BLOCK_SIZE+2 < BLOCK_SIZE+4)
				if(col+i*BLOCK_SIZE < N.width && row+j*BLOCK_SIZE < N.height)
					// Load in the index
					Nds[ty+j*BLOCK_SIZE+2][tx+i*BLOCK_SIZE+2] = GetElement(N,row+j*BLOCK_SIZE,col+i*BLOCK_SIZE);
				else
					Nds[ty+j*BLOCK_SIZE+2][tx+i*BLOCK_SIZE+2] = 0;
			
	float sum = 0;
	// Don't do anything if we aren't operating on a valid pixel
	if(row < P.height && col < P.width)
	{
		// Load in an entire block to shared memory
		Nds[ty+2][tx+2] = GetElement(N,row,col);
		// Synchronize to make sure the sub-matrices are loaded
		// before starting the computation
		__syncthreads();

		unsigned int m_begin = (row < 2)? 2 - row : 0;
		unsigned int m_end = (row > (N.height - 3))? N.height - row + 2 : 5;
		unsigned int n_begin = (col < 2)? 2 - col : 0;
		unsigned int n_end = (col > (N.width - 3))? N.width - col + 2 : 5;

		for(int m = m_begin; m < m_end; m++)
			for(int n = n_begin; n < n_end; n++)
				sum += Mds[m][n]*GetElement(N,m+row-2 ,n+col-2);

		// Synchronize to make sure that the preceding
		// computation is done before loading new
		// sub-matrice of N in the next iteration		
		__syncthreads();
		// Write sum to device memory
		// Each thread writes one element
		SetElement(P,row,col, sum);
	}

}

////////////////////////////////////////////////////////////////////////////////
// Returnează 1 dacă matricele sunt ~ egale
////////////////////////////////////////////////////////////////////////////////
int CompareMatrices(Matrix A, Matrix B)
{
    int i;
    if(A.width != B.width || A.height != B.height || A.pitch != B.pitch)
        return 0;
    int size = A.width * A.height;
    for(i = 0; i < size; i++)
        if(fabs(A.elements[i] - B.elements[i]) > MAX_ERR)
            return 0;
    return 1;
}
void GenerateRandomMatrix(Matrix m)
{
    int i;
    int size = m.width * m.height;

    srand(time(NULL));

    for(i = 0; i < size; i++)
        m.elements[i] = rand() / (float)RAND_MAX;
}

////////////////////////////////////////////////////////////////////////////////
// main
////////////////////////////////////////////////////////////////////////////////
int main(int argc, char** argv) 
{
    int width = 0, height = 0;
    FILE *f, *out;
    if(argc < 2)
    {
        printf("Argumente prea puține, trimiteți id-ul testului care trebuie rulat\n");
        return 0;
    }
    char name[100];//for(int i =0 ; i<P.width*P.height;i++)
	//printf("%f ",P.elements[i]);
    sprintf(name, "./tests/test_%s.txt", argv[1]);
    f = fopen(name, "r");
    out = fopen("out.txt", "a");
    fscanf(f, "%d%d", &width, &height);
    Matrix M;//kernel de pe host
    Matrix N;//matrice inițială de pe host
    Matrix P;//rezultat fără memorie partajată calculat pe GPU
    Matrix PS;//rezultatul cu memorie partajată calculat pe GPU
    
    M = AllocateMatrix(KERNEL_SIZE, KERNEL_SIZE);
    N = AllocateMatrix(width, height);        
    P = AllocateMatrix(width, height);
    PS = AllocateMatrix(width, height);

    GenerateRandomMatrix(M);
    GenerateRandomMatrix(N);

    // M * N pe device
    ConvolutionOnDevice(M, N, P);
    
    // M * N pe device cu memorie partajată
    ConvolutionOnDeviceShared(M, N, PS);

    // calculează rezultatul pe CPU pentru comparație
    Matrix reference = AllocateMatrix(P.width, P.height);
    computeGold(reference.elements, M.elements, N.elements, N.height, N.width);
        
    // verifică dacă rezultatul obținut pe device este cel așteptat
    int res = CompareMatrices(reference, P);
    printf("Test global %s\n", (1 == res) ? "PASSED" : "FAILED");
    fprintf(out, "Test global %s %s\n", argv[1], (1 == res) ? "PASSED" : "FAILED");

    // verifică dacă rezultatul obținut pe device cu memorie partajată este cel așteptat
  //  int ress = CompareMatrices(reference, PS);
    int ress = CompareMatrices(reference, PS);
    printf("Test shared %s\n", (1 == ress) ? "PASSED" : "FAILED");
    fprintf(out, "Test shared %s %s\n", argv[1], (1 == ress) ? "PASSED" : "FAILED");
   
    // Free matrices
    FreeMatrix(&M);
    FreeMatrix(&N);
    FreeMatrix(&P);
    FreeMatrix(&PS);

    fclose(f);
    fclose(out);
    return 0;
}


//Copie matrice de pe host pe device:
void CopyToDeviceMatrix(Matrix Md, Matrix M)
{
	Md.width = Md.pitch = M.width;
	Md.height = M.height;
	int size = M.width * M.height * sizeof(float);
	cudaMemcpy(Md.elements,M.elements,size,cudaMemcpyHostToDevice);
}

//Copie matrice de pe device pe host:
void CopyToHostMatrix(Matrix M,Matrix Md) 
{
	int size = Md.width * Md.height * sizeof(float);
	cudaMemcpy(M.elements,Md.elements,size,cudaMemcpyDeviceToHost);
}

////////////////////////////////////////////////////////////////////////////////
//! Run a simple test for CUDA
////////////////////////////////////////////////////////////////////////////////
void ConvolutionOnDevice(const Matrix M, const Matrix N, Matrix P)
{
    Matrix Md, Nd, Pd; //matricele corespunzătoare de pe device

    //pentru măsurarea timpului de execuție în kernel
    StopWatchInterface *kernelTime = NULL;
    sdkCreateTimer(&kernelTime);
    sdkResetTimer(&kernelTime);
    //TODO: alocați matricele de pe device
    Md = AllocateDeviceMatrix(M.width, M.height);
    Nd = AllocateDeviceMatrix(N.width, N.height);
    Pd = AllocateDeviceMatrix(P.width, P.height);

    //TODO: copiați datele de pe host (M, N) pe devtodice (MD, Nd)
	CopyToDeviceMatrix(Md,M);
	CopyToDeviceMatrix(Nd,N);


    //TODO: setați configurația de rulare a kernelului
	dim3 dimBlock(BLOCK_SIZE,BLOCK_SIZE); 				// 256 threads per block
	dim3 dimGrid(ceil((float) N.width/dimBlock.x ), ceil((float) N.height/dimBlock.y )); 	// no. of thread blocks

    sdkStartTimer(&kernelTime);
    //TODO: lansați în execuție kernelul 
	ConvolutionKernel<<< dimGrid,dimBlock >>>(Md, Nd, Pd);  
	// grila unidimensionala de dimGrid blocuri, dimBlock threaduri per bloc 
    cudaThreadSynchronize();
    sdkStopTimer(&kernelTime);
    printf ("Timp execuție kernel: %f ms\n", sdkGetTimerValue(&kernelTime));
    //TODO: copiaţi rezultatul pe host
    CopyToHostMatrix(P,Pd);

    //TODO: eliberați memoria matricelor de pe device
    FreeDeviceMatrix(&Md);
    FreeDeviceMatrix(&Nd);
    FreeDeviceMatrix(&Pd);
}


void ConvolutionOnDeviceShared(const Matrix M, const Matrix N, Matrix P)
{
    Matrix Md, Nd, Pd; //matricele corespunzătoare de pe device

    //pentru măsurarea timpului de execuție în kernel
    StopWatchInterface *kernelTime = NULL;
    sdkCreateTimer(&kernelTime);
    sdkResetTimer(&kernelTime);
    //TODO: alocați matricele de pe device
	Md = AllocateDeviceMatrix(M.width, M.height);
	Nd = AllocateDeviceMatrix(N.width, N.height);
	Pd = AllocateDeviceMatrix(P.width, P.height);

    //TODO: copiați datele de pe host (M, N) pe device (MD, Nd)
	CopyToDeviceMatrix(Md,M);
	CopyToDeviceMatrix(Nd,N);

    //TODO: setați configurația de rulare a kernelului
	dim3 dimBlock(BLOCK_SIZE,BLOCK_SIZE); 	// 256 threads per block
	dim3 dimGrid(ceil((float) N.width/dimBlock.x ), ceil((float) N.height/dimBlock.y )); // nr. of thread blocks

    sdkStartTimer(&kernelTime);
    //TODO: lansați în execuție kernelul    
	ConvolutionKernelShared<<< dimGrid, dimBlock>>>(Md, Nd, Pd);  
	// grila unidimensionala de dimGrid blocuri, dimBlock threaduri per bloc 	

    cudaThreadSynchronize();
    sdkStopTimer(&kernelTime);
    printf ("Timp execuție kernel cu memorie partajată: %f ms\n", sdkGetTimerValue(&kernelTime));
    //TODO: copiaţi rezultatul pe host
	CopyToHostMatrix(P,Pd);


    //TODO: eliberați memoria matricelor de pe device
    FreeDeviceMatrix(&Md);
    FreeDeviceMatrix(&Nd);
    FreeDeviceMatrix(&Pd);
}


// Alocă o matrice de dimensiune height*width pe device
Matrix AllocateDeviceMatrix(int width, int height)
{
    Matrix m;
    //TODO: alocați matricea și setați width, pitch și height
    m.width = m.pitch = width;
    m.height = height;
    int size = m.width * m.height * sizeof(float);
    cudaMalloc((void**)&m.elements,size);
    return m;
}

// Alocă matrice pe host de dimensiune height*width
Matrix AllocateMatrix(int width, int height)
{
    Matrix M;
    M.width = M.pitch = width;
    M.height = height;
    int size = M.width * M.height;    
    M.elements = (float*) malloc(size*sizeof(float));
    return M;
}    

// Eliberează o matrice de pe device
void FreeDeviceMatrix(Matrix* M)
{
    cudaFree(M->elements);
    M->elements = NULL;
}

// Eliberează o matrice de pe host
void FreeMatrix(Matrix* M)
{
    free(M->elements);
    M->elements = NULL;
}
