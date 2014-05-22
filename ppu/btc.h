#define BUF_SIZE 		256
#define BLOCK_SIZE 		8
#define BITS_IN_BYTE		8
#define MAX_SPU_THREADS   	16
#define N 		  	8
#define M 			64

//macro for easily getting how much time has passed between two events
#define GET_TIME_DELTA(t1, t2) ((t2).tv_sec - (t1).tv_sec + \
		((t2).tv_usec - (t1).tv_usec) / 1000000.0)

// macro de waittag
#define waittag(t) mfc_write_tag_mask(1<<t); mfc_read_tag_status_all();	

struct img {
	//regular image
	int width, height;
	short int* pixels;
};

struct block{
	//data for a block from the compressed image
	unsigned char a, b;
	unsigned char bitplane[BLOCK_SIZE * BLOCK_SIZE];
	//one byte for each bit in the bitplane
	//quite memory inefficient, but let's keep it simple
};


struct block2{
	unsigned char a,b;
	unsigned char bitplane[BLOCK_SIZE * BLOCK_SIZE];
	int x,y;		// x,y,z pusi pe post de 'padding' ca dimensiunea 
	short int z;
};				// structurii sa fie Multiplu de 16
				// sizeof(block2)=80

struct c_img{
	//compressed image
	int width, height;
	struct block* blocks;
};

struct bits{
	unsigned bit0 : 1;
	unsigned bit1 : 1;
	unsigned bit2 : 1;
	unsigned bit3 : 1;
	unsigned bit4 : 1;
	unsigned bit5 : 1;
	unsigned bit6 : 1;
	unsigned bit7 : 1;
};

typedef struct {
	short int* A;		// pointer la pixelii imaginii initiale, aliniata la 16B 
	struct block2* B; 	// pointer la blocurile imaginii comprimate
	short int* C; 		// pointer la pixelii imaginii decomprimate
	int dim; 		//  dimensiune transfer DMA(nr.de linii pe care il primeste fiecare spu)
	int width,height;	// latimea si lungimea imaginii.
	int thread_id,D;	// D e pus pe post de 'padding' ca dimensiunea structurii sa fie Multiplu de 16
} pointers_t;			// structura folosita ptr a primi adresele de la ppu 

// ciudat insa sizeof(pointers_t)=48 pe laptopul personal
// pe cluster logat pe cell obtin sizeof(pointers_t)=32 

//utils
void* _alloc(int size);
void _read_buffer(int fd, void* buf, int size);
void _write_buffer(int fd, void* buf, int size);
int _open_for_write(char* path);
int _open_for_read(char* path);
//read_btc
void read_btc(char* path, struct c_img* out_img);
void write_btc(char* path, struct c_img* out_img);
void free_btc(struct c_img* out_img);
//read_pgm
void read_pgm(char* path, struct img* in_img);
void write_pgm(char* path, struct img* out_img);
void free_pgm(struct img* out_img);
