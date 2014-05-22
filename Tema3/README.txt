*** Arhip Alin-Gabriel 333CC ***
*** Tema 3 ASC ***
*** Mai 2014 ***
*** Block Truncation Coding pe Cell Broad-Band Engine ***

** Introducere **
	Tema constă în implementarea comprimarii de tip Block Truncation Coding pe 
Cell Broad-Band Engine a unei imagini, folosind o dimensiune a blocului de 
8x8(N=8), precum si reconstructia imaginii originale din imaginea comprimata. 
	Se dorește utilizarea arhitecturii Cell Broad-Band Engine pentru 
paralelizarea operatiilor de comprimare si decomprimare.

** Implementare **
	Am folosit laboratorul 8 de CELL ca schelet pentru tema mea.
	Am modificat btc.h (i-am adaugat 2 structuri in plus)si l-am adaugat in /ppu. 
	In lab8_spu.c am implementat partea de spu si are binarul lab8_spu.
	In lab8_ppu.c am implementat partea de ppu si are executabilul tema3.

	Am copiat pixelii imaginii citite cu functia read_pgm intr-un 
vector short int A aliniat la 16. Din PPU trimit fiecarui SPU "dim" linii din matricea 
pixelilor imaginii. thread_arg[i].A -> adresa de inceput a partii de prelucrat pentru SPU cu nr i,
ultimul SPU va primi restul de linii in caz ca dimensiunile imaginii nu sunt multiplu de 16.

Transferurile DMA:
	Fiecare SPU face un transfer DMA pentru a lua informațiile despre locațiile 
de memorie ale diverselor structuri din PPU.
	In while iau cate un bloc(de 8 pe 8), il comprim, il pun in Main Storage.
dupa care il decomprim si inapoi in in Main Storage. In total fac 8 transferuri DMA,
deoarece fac un transfer pentru fiecare linie. (si cum sunt 8 linii e evident de ce).
). Apoi la comprimare fac un transfer DMA pentru a pune blocul inapoi in Main Storage.
	In fine, la decomprimare iau acel bloc si fac  alte 8 transferuri DMA. 

	Pentru a trimite adresele catre spu-uri am folosit o structura:
typedef struct {
	short int* A;		// pointer la pixelii imaginii initiale, aliniata la 16B 
	struct block2* B; 	// pointer la blocurile imaginii comprimate
	short int* C; 		// pointer la pixelii imaginii decomprimate
	int dim; 		//  dimensiune transfer DMA(nr.de linii pe care il primeste fiecare spu)
	int width,height;	// latimea si lungimea imaginii.
	int thread_id,D;	// ca dimensiunea structurii sa fie Multiplu de 16
} pointers_t;			// structura folosita ptr a primi adresele de la ppu 
	
	Mentionez ca pe laptopul personal sizeof(pointers_t)=48=16*3 ,
pe cell obtin sizeof(pointers_t)=32=16*2 , dar oricum ar fi, ambii sunt multipli de 16. :-)	
	Mai folosesc structura block2 care este identica cu structura block din btc.h , 
doar ca i-am adaugat inca 2 variabile pentru ca sa am dimensiunea multiplu de 16 pentru 
a putea face usor transferul DMA:

struct block2{
	unsigned char a,b;
	unsigned char bitplane[BLOCK_SIZE * BLOCK_SIZE];
	int x,y;		// x1,x2 pentru ca dimensiunea structurii sa fie Multiplu de 16
	short int z;
};
Astfel sizeof(block2)=80=16*5.

Analiza performantei:
Pentru aceste rezultate am rezervat un blade(12 sloturi) folosind comanda:
qsub -cwd -q ibm-cell-qs22.q -pe openmpi*12 12 run_all.sh

Pentru in1.pgm:
	cu 1 spu: Encoding / Decoding time: 0.915038 
 		  Total time: 1.345688 
	cu 2 spu: Encoding / Decoding time: 0.458245 
 		  Total time: 0.773556 
	cu 4 spu: Encoding / Decoding time: 0.230640 
 		  Total time: 0.587261 
	cu 8 spu: Encoding / Decoding time: 0.162943 
 		  Total time: 0.515979 

Se observa ca scaleza bine, timpul total fiind de 
aproape 3 ori mai bun cu 8 spu-uri decat cu 1 spu.

Pentru in2.pgm:
	cu 1 spu: Encoding / Decoding time: 1.858840 
 	Total time: 2.704158 
	cu 2 spu: Encoding / Decoding time: 0.929141 
 	Total time: 1.648055 
	cu 4 spu: Encoding / Decoding time: 0.583540 
 	Total time: 1.218432 
	cu 8 spu: Encoding / Decoding time: 0.291640 
 	Total time: 0.971519 

Din nou se observa ca scaleaza bine, 
cu 8 spu-ri mergand de 3 ori mai repede decat cu 1 spu.

Pentru in3.pgm:
	cu 1 spu: Encoding / Decoding time: 2.561952 
 		  Total time: 3.766068 
	cu 2 spu: Encoding / Decoding time: 1.583151 
 		  Total time: 2.714182 
	cu 4 spu: Encoding / Decoding time: 0.790956 
 		  Total time: 1.916802 
	cu 8 spu: Encoding / Decoding time: 0.397269 
 	  	  Total time: 1.657594 

Am observat urmatoarele:
-comprimarea si decomprimarea scaleaza foarte bine,
de 7-8 ori mai bine cu 8 spu fata de 1 spu in toate imaginile,
-in timp ce timpul total scaleaza undeva de 3-4 ori mai bine 
cu 8 spu-uri decat cu 1 spu. 

Feedback:

	Consider că tema nu este foarte utilă având în vedere că arhitectura
Cell este aproape moartă și nefolosită de nimeni. Mai mult, erorile provocate
de transferurile DMA sunt absolut neintuitive, și provoacă dureri de cap
datorită faptului că nu știi exact ce anume a provocat acele erori, programul
putând să moară în orice loc.
	Aș fi preferat să studiem arhitecturi precum CUDA ce folosesc instrucțiuni
SIMD într-un mod mult mai eficient și este mult mai ușor de scris cod pe
aceste arhitecturi.

Timp rezolvare:

	Estimez că pentru rezolvarea temei am avut nevoie de peste 24 de ore efective
de lucru (adică vreo 4 zile a câte 6 ore pe zi), ceea ce nu este ok,
ținând cont de faptul că avem și alte teme, plus însăși prezența la facultate.
	Sugerez să schimbați pe viitor acest gen de teme și însăși arhitectura
studiată, deoarece nu mai este folosită de aproape nimeni. De exemplu, consola
Sony Play Station ce va apărea va trece pe arhitecturi X86, și practic PS3
	va rămâne deja istorie cu CELL-ul lui.
