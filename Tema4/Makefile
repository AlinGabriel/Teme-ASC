CFLAGS += 

a.out: *.cu *.cpp
	nvcc -arch=sm_20 -I$(CUDA_PATH)/samples/common/inc/ $^ 

clean:
	rm a.out

.PHONY: clean
