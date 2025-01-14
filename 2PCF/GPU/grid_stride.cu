/*
 * This project is dual licensed. You may license this software under one of the
   following licences:

   + Creative Commons Attribution-Share Alike 3.0 Unported License
     http://creativecommons.org/licenses/by-nc-sa/3.0/

   + GNU GENERAL PUBLIC LICENSE v3, designated as a "BY-SA Compatible License"
     as defined in BY-SA 4.0 on 8 October 2015

 * See the LICENSE file in the root directory of this source tree for full
   copyright disclosure, and other details.
 */


/* Header files */

#include <iostream>
#include <fstream>
#include <cuda.h>

#include "utils.hpp"


/* Constants */

#define threads 256 /* It's the number of threads we are going to use per block on the GPU */

using namespace std;


/* Kernels */

/* This kernel counts the number of pairs in the data file */
/* We will use this kernel to calculate real-real pairs and random-random pairs */

__global__ void binning(float *xd,float *yd,float *zd,float *ZZ,int number_lines,int points_per_degree, int number_of_degrees)
{

    /* We define variables (arrays) in shared memory */

    float angle;
    __shared__ float temp[threads];

    /* We define an index to run through these two arrays */

    int index = threadIdx.x;

    /* This variable is necesary to accelerate the calculation, it's due that "temp" was definied in the shared memory too */

    temp[index]=0;
    float x,y,z; //MCM
    float xx,yy,zz; //MCM

    /* We start the counting */

    for (int i=0;i<number_lines;i++)
    {
        x = xd[i];//MCM
        y = yd[i];//MCM
        z = zd[i];//MCM

        /* The "while" replaces the second for-loop in the sequential calculation case (CPU). We use "while" rather than "if" as recommended in the book "Cuda by Example" */

        for(int dim_idx = blockIdx.x * blockDim.x + threadIdx.x;
            dim_idx < number_lines;
            dim_idx += blockDim.x * gridDim.x)
        {
            xx = xd[dim_idx];//MCM
            yy = yd[dim_idx];//MCM
            zz = zd[dim_idx];//MCM

            /* We make the dot product */
            angle = x * xx + y * yy + z * zz;//MCM


            //angle[index]=xd[i]*xd[dim_idx]+yd[i]*yd[dim_idx]+zd[i]*zd[dim_idx];//MCM
            //__syncthreads();//MCM

            /* Sometimes "angle" is higher than one, due to numnerical precision, to solve it we use the next sentence */

            angle=fminf(angle,1.0);
            angle=acosf(angle)*180.0/M_PI;
            //__syncthreads();//MCM

            /* We finally count the number of pairs separated an angular distance "angle", always in shared memory */

            if(angle < number_of_degrees)
            {
                atomicAdd( &temp[int(angle*points_per_degree)], 1.0);
            }
            __syncthreads();
        }
    }

    /* We copy the number of pairs from shared memory to global memory */

    atomicAdd( &ZZ[threadIdx.x] , temp[threadIdx.x]);
    __syncthreads();
}

/* This kernel counts the number of pairs that there are between two data groups */
/* We will use this kernel to calculate real-random pairs and real_1-real_2 pairs (cross-correlation) */
/* NOTE that this kernel has NOT been merged with 'binning' above: this is for speed optimization, we avoid passing extra variables to the GPU */ 

__global__ void binning_mix(float *xd_real, float *yd_real, float *zd_real, float *xd_sim, float *yd_sim, float *zd_sim, float *ZY, int lines_number_1, int lines_number_2, int points_per_degree, int number_of_degrees)
{

    /* We define variables (arrays) in shared memory */

    float angle;
    __shared__ float temp[threads];

    /* We define an index to run through these two arrays */    

    int index = threadIdx.x;

    /* This variable is necesary to accelerate the calculation, it's due that "temp" was definied in the shared memory too */

    temp[index]=0;
    float x,y,z; //MCM
    float xx,yy,zz; //MCM

    /* We start the counting */

    for (int i=0;i<lines_number_1;i++)
    {
        x = xd_real[i];//MCM
        y = yd_real[i];//MCM
        z = zd_real[i];//MCM

        /* The "while" replaces the second for-loop in the sequential calculation case (CPU). We use "while" rather than "if" as recommended in the book "Cuda by Example" */

        for(int dim_idx = blockIdx.x * blockDim.x + threadIdx.x;
            dim_idx < lines_number_2;
            dim_idx += blockDim.x * gridDim.x)
        {
            xx = xd_sim[dim_idx];//MCM
            yy = yd_sim[dim_idx];//MCM
            zz = zd_sim[dim_idx];//MCM
            /* We make the dot product */ 
            angle = x * xx + y * yy + z * zz;//MCM

            //angle[index]=xd[i]*xd[dim_idx]+yd[i]*yd[dim_idx]+zd[i]*zd[dim_idx];//MCM
            //__syncthreads();//MCM

            /* Sometimes "angle" is higher than one, due to numnerical precision, to solve it we use the next sentence */
            
            angle=fminf(angle,1.0);
            angle=acosf(angle)*180.0/M_PI;
            //__syncthreads();//MCM

            /* We finally count the number of pairs separated an angular distance "angle", always in shared memory */

            if(angle < number_of_degrees)
            {
                atomicAdd( &temp[int(angle*points_per_degree)], 1.0);
            }
            __syncthreads();
        }
    }

    /* We copy the number of pairs from shared memory to global memory */

    atomicAdd( &ZY[threadIdx.x] , temp[threadIdx.x]);
    __syncthreads();
}

int copy2dev(float *gpu_xd, float *gpu_yd, float *gpu_zd, float *xd, float *yd, float *zd, int lines_number, float *gpu_ZZ, float *ZZ, dim3 dimGrid, int points_per_degree, int number_of_degrees){
         /* We copy the data in cartesian coordinates to the GPU */  

        cudaMemcpy(gpu_xd,xd,lines_number*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_yd,yd,lines_number*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_zd,zd,lines_number*sizeof(float),cudaMemcpyHostToDevice);

        /* We initialize pair variable (ZZ) on GPU, copying the initialize data on CPU */

        cudaMemcpy(gpu_ZZ, ZZ, threads*sizeof(float),cudaMemcpyHostToDevice);

        /* We call the needed kernel to calculate the number of pairs */ 

        binning <<< dimGrid, threads >>> (gpu_xd, gpu_yd, gpu_zd, gpu_ZZ, lines_number, points_per_degree, number_of_degrees);

        /* We recover the real pairs variables (DD) */

        cudaMemcpy(ZZ, gpu_ZZ, threads*sizeof(float),cudaMemcpyDeviceToHost);
       
        return(0);
}

int copy2dev_mix(float *gpu_xd_1, float *gpu_yd_1, float *gpu_zd_1, float *xd_1, float *yd_1, float *zd_1, int lines_number_1, float *gpu_xd_2, float *gpu_yd_2, float *gpu_zd_2, float *xd_2, float *yd_2, float *zd_2, int lines_number_2, float *gpu_ZY, float *ZY, dim3 dimGrid, int points_per_degree, int number_of_degrees){

        /* We copy again the real data and the random data in cartesian coordinates to the GPU. This step is not necesary, but it's recommended because we ensure there won't be any trouble with the memory on the GPU */

        /* We copy the real data and random data to make the correlation between both */

        cudaMemcpy(gpu_xd_1,xd_1,lines_number_1*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_yd_1,yd_1,lines_number_1*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_zd_1,zd_1,lines_number_1*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_xd_2,xd_2,lines_number_2*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_yd_2,yd_2,lines_number_2*sizeof(float),cudaMemcpyHostToDevice);
        cudaMemcpy(gpu_zd_2,zd_2,lines_number_2*sizeof(float),cudaMemcpyHostToDevice);

        /* We initialize real-random pair variable (ZY) on GPU, copying the initialize data on CPU */

        cudaMemcpy(gpu_ZY,ZY,threads*sizeof(float),cudaMemcpyHostToDevice);

        /* We call the needed kernel to calculate the number of pairs that there are between the real data and the random data */

        binning_mix <<< dimGrid, threads >>> (gpu_xd_1, gpu_yd_1, gpu_zd_1, gpu_xd_2, gpu_yd_2, gpu_zd_2, gpu_ZY, lines_number_1, lines_number_2, points_per_degree, number_of_degrees);

        /* We recover the real-random pairs variables (ZY) */

        cudaMemcpy(ZY,gpu_ZY,threads*sizeof(float),cudaMemcpyDeviceToHost);

        return(0);
}

/* Main Function*/

int main(int argc, char *argv[])
{
    /* Checking if the input files and call to script meet the requirements */

    const int mode = verification(argc, argv);
    if (mode == 0)
    {
        exit(1);
    }

    /* Definition of variables, these variables are the same for the auto-correlation and the cross-correlation */

    int points_per_degree;
    int number_of_degrees;
    char *input_real_file_1, *input_real_file_2, *input_random_file, *output_file;
    double W, angle_theta, poissonian_error, norm_cost_1, norm_cost_2;

    int real_lines_number_1, real_lines_number_2, random_lines_number, max_lines;

    float *xd_real_1,*yd_real_1,*zd_real_1;
    float *xd_real_2,*yd_real_2,*zd_real_2;
    float *xd_rand,*yd_rand,*zd_rand;

    float *gpu_xd_real_1;
    float *gpu_yd_real_1;
    float *gpu_zd_real_1;
    float *gpu_xd_real_2;
    float *gpu_yd_real_2;
    float *gpu_zd_real_2;
    float *gpu_xd_rand;
    float *gpu_yd_rand;
    float *gpu_zd_rand;

    /* Assignment of Variables with inputs */

    input_real_file_1 = argv[1];
    input_real_file_2 = argv[2];
    input_random_file = argv[3];
    points_per_degree = atoi(argv[4]);
    number_of_degrees = int(float(threads)/float(points_per_degree));
    output_file=argv[5];

    /* Counting lines in every input file */

    real_lines_number_1 = count_lines(input_real_file_1);
    if(real_lines_number_1 == -1)
        std::cerr << "Incorrectly formatted file: " << input_real_file_1 << std::endl;

    /* const int mode = (std::string(argv[1]) == std::string(argv[2])) ? AUTO : CROSS; */

    if(mode == CROSS){
        real_lines_number_2 = count_lines(input_real_file_2);
        if(real_lines_number_2 == -1)
            std::cerr << "Incorrectly formatted file: " << input_real_file_2 << std::endl;
    }

    random_lines_number = count_lines(input_random_file);
    if(random_lines_number == -1)
        std::cerr << "Incorrectly formatted file: " << input_random_file << std::endl;

    /* We define variables to store the real,random data */

    xd_real_1 = (float *)malloc(real_lines_number_1 * sizeof (float));
    yd_real_1 = (float *)malloc(real_lines_number_1 * sizeof (float));
    zd_real_1 = (float *)malloc(real_lines_number_1 * sizeof (float));
    xd_rand = (float *)malloc(random_lines_number * sizeof (float));
    yd_rand = (float *)malloc(random_lines_number * sizeof (float));
    zd_rand = (float *)malloc(random_lines_number * sizeof (float));

    if(mode == CROSS)
    {
        xd_real_2 = (float *)malloc(real_lines_number_2 * sizeof (float));
        yd_real_2 = (float *)malloc(real_lines_number_2 * sizeof (float));
        zd_real_2 = (float *)malloc(real_lines_number_2 * sizeof (float));
    }

    /* Opening the first input file */

    eq2cart(input_real_file_1,real_lines_number_1,xd_real_1,yd_real_1,zd_real_1);

    /* Opening the second input file */

    if(mode == CROSS)
    {
        eq2cart(input_real_file_2,real_lines_number_2,xd_real_2,yd_real_2,zd_real_2);
    }

    /* Opening the third input file */

    eq2cart(input_random_file,random_lines_number,xd_rand,yd_rand,zd_rand);

    /* We define variables to send to the GPU */

    /* For real data */

    cudaMalloc( (void**)&gpu_xd_real_1,real_lines_number_1 * sizeof(float));
    cudaMalloc( (void**)&gpu_yd_real_1,real_lines_number_1 * sizeof(float));
    cudaMalloc( (void**)&gpu_zd_real_1,real_lines_number_1 * sizeof(float));
    if(mode == CROSS)
    {
        cudaMalloc( (void**)&gpu_xd_real_2,real_lines_number_2 * sizeof(float));
        cudaMalloc( (void**)&gpu_yd_real_2,real_lines_number_2 * sizeof(float));
        cudaMalloc( (void**)&gpu_zd_real_2,real_lines_number_2 * sizeof(float));
    }

    /* For random data */

    cudaMalloc( (void**)&gpu_xd_rand,random_lines_number * sizeof(float));
    cudaMalloc( (void**)&gpu_yd_rand,random_lines_number * sizeof(float));
    cudaMalloc( (void**)&gpu_zd_rand,random_lines_number * sizeof(float));

    /* We define variables to store the pairs between real data (DD), random data (RR) and both together (DR) */

    /* on CPU */
    float *DD;
    float *DR;
    float *RR;
    float *D1D2;
    float *D1R;
    float *D2R;
    RR = (float *)malloc(threads*sizeof(float));
    if(mode == CROSS)
    {
        D1D2 = (float *)malloc(threads*sizeof(float));
        D1R = (float *)malloc(threads*sizeof(float));
        D2R = (float *)malloc(threads*sizeof(float));
        for (int i=0; i< threads; i++)
        {
            D1D2[i] = 0.0;
            RR[i] = 0.0;
            D1R[i] = 0.0;
            D2R[i] = 0.0;
        }
    }
    else
    {
        DD = (float *)malloc(threads*sizeof(float));
        DR = (float *)malloc(threads*sizeof(float));
        for (int i=0; i< threads; i++)
        {
           DD[i] = 0.0;
           RR[i] = 0.0;
           DR[i] = 0.0;
        }
    }

    /* on GPU */
    float *gpu_DD;
    float *gpu_DR;
    float *gpu_RR;
    float *gpu_D1D2;
    float *gpu_D1R;
    float *gpu_D2R;
    cudaMalloc( (void**)&gpu_RR, threads*sizeof(float));
    if(mode == CROSS)
    {
        cudaMalloc( (void**)&gpu_D1D2, threads*sizeof(float));
        cudaMalloc( (void**)&gpu_D1R, threads*sizeof(float));
        cudaMalloc( (void**)&gpu_D2R, threads*sizeof(float));
    }
    else
    {
        cudaMalloc( (void**)&gpu_DD, threads*sizeof(float));
        cudaMalloc( (void**)&gpu_DR, threads*sizeof(float));
    }

    /* We determine which is the maximum number of lines */
    max_lines = max(real_lines_number_1,random_lines_number);
    if(mode == CROSS)
    {
        max_lines = max(max_lines,real_lines_number_2);
    }

    /* We define the GPU-GRID size, it's really the number of blocks we are going to use on the GPU */

    // dim3 dimGrid((max_lines/threads)+1);
    int numSMs;
    cudaDeviceGetAttribute(&numSMs, cudaDevAttrMultiProcessorCount, 0);
    dim3 dimGrid(64*numSMs);


    if(mode == CROSS)
    {
        copy2dev(gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_RR,RR,dimGrid,points_per_degree,number_of_degrees);
        copy2dev_mix(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_xd_real_2,gpu_yd_real_2,gpu_zd_real_2,xd_real_2,yd_real_2,zd_real_2,real_lines_number_2,gpu_D1D2,D1D2,dimGrid,points_per_degree,number_of_degrees);
        copy2dev_mix(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_D1R,D1R,dimGrid,points_per_degree,number_of_degrees);
        copy2dev_mix(gpu_xd_real_2,gpu_yd_real_2,gpu_zd_real_2,xd_real_2,yd_real_2,zd_real_2,real_lines_number_2,gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_D2R,D2R,dimGrid,points_per_degree,number_of_degrees);
    }
    else
    {
        copy2dev(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_DD,DD,dimGrid,points_per_degree,number_of_degrees);
        copy2dev(gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_RR,RR,dimGrid,points_per_degree,number_of_degrees);
        copy2dev_mix(gpu_xd_real_1,gpu_yd_real_1,gpu_zd_real_1,xd_real_1,yd_real_1,zd_real_1,real_lines_number_1,gpu_xd_rand,gpu_yd_rand,gpu_zd_rand,xd_rand,yd_rand,zd_rand,random_lines_number,gpu_DR,DR,dimGrid,points_per_degree,number_of_degrees);
    }

    /* Opening the output file */

    std::ofstream f_out(output_file);

   /* We calculate the normalization factor */

   norm_cost_1=float(random_lines_number)/float(real_lines_number_1);
   if(mode == CROSS)
   {
       norm_cost_2=float(random_lines_number)/float(real_lines_number_2);
   }

   if(mode == CROSS)
   {

        for (int i=1;i<threads;i++)
        {
            /* The angle corresponding to the W value */

            angle_theta=(1.0/points_per_degree)/2.0+(i*(1.0/points_per_degree));

            /* We are calculating the Landy & Szalay estimator */

            W=(norm_cost_1)*(norm_cost_2)*(D1D2[i]/RR[i])-(norm_cost_1)*(D1R[i]/RR[i])-(norm_cost_2)*(D2R[i]/RR[i])+1.0;
            poissonian_error=(1.0+W)/sqrt(D1D2[i]);
            f_out<<angle_theta<<"\t"<<W<<"\t"<<poissonian_error<<"\t"<<D1D2[i]<<"\t"<<D1R[i]<<"\t"<<D2R[i]<<"\t"<<RR[i]<<endl;
        }
    }
    else
    {
        for (int i=0;i<threads;i++)
        {
            /* The angle corresponding to the W value */

            angle_theta=(1.0/points_per_degree)/2.0+(i*(1.0/points_per_degree));
            W=(((pow(norm_cost_1,2)*DD[i])-(2*norm_cost_1*DR[i]))/RR[i])+1.0;
            poissonian_error=(1.0+W)/sqrt(DD[i]);
            f_out<<angle_theta<<"\t"<<W<<"\t"<<poissonian_error<<"\t"<<DD[i]<<"\t"<<DR[i]<<"\t"<<RR[i]<<endl;
        }
    }

    /* Closing output files */

    f_out.close();

    /* Freeing memory on the GPU */

    cudaFree( gpu_xd_rand );
    cudaFree( gpu_yd_rand );
    cudaFree( gpu_zd_rand );
    cudaFree( gpu_xd_real_1 );
    cudaFree( gpu_yd_real_1 );
    cudaFree( gpu_zd_real_1 );

    if(mode == CROSS)
    {
        cudaFree( gpu_xd_real_2 );
        cudaFree( gpu_yd_real_2 );
        cudaFree( gpu_zd_real_2 );
        cudaFree( gpu_D1D2 );
        cudaFree( gpu_D1R );
        cudaFree( gpu_D2R );
    }
    else
    {

        cudaFree( gpu_DD );
        cudaFree( gpu_DR );
        cudaFree( gpu_RR );
    }

    /* Freeing memory on the CPU */

    free(xd_real_1);
    free(yd_real_1);
    free(zd_real_1);
    free(xd_rand);
    free(yd_rand);
    free(zd_rand);

    if(mode == CROSS)
    {
        free(xd_real_2);
        free(yd_real_2);
        free(zd_real_2);
        free(D1D2);
        free(D1R);
        free(D2R);
    }
    else
    {
        free(DD);
        free(DR);
        free(RR);
    }

    return(0);
}
