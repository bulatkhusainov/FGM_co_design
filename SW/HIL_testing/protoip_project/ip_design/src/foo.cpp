/* 
* icl::protoip
* Author: asuardi <https://github.com/asuardi>
* Date: November - 2014
*/


#include "foo_data.h"


void foo_user(  data_t_x_in_in x_in_in_int[X_IN_IN_LENGTH],
				data_t_y_out_out y_out_out_int[Y_OUT_OUT_LENGTH]);


void foo	(
				uint32_t byte_x_in_in_offset,
				uint32_t byte_y_out_out_offset,
				volatile data_t_memory *memory_inout)
{

	#ifndef __SYNTHESIS__
	//Any system calls which manage memory allocation within the system, for example malloc(), alloc() and free(), must be removed from the design code prior to synthesis. 

	data_t_interface_x_in_in *x_in_in;
	x_in_in = (data_t_interface_x_in_in *)malloc(X_IN_IN_LENGTH*sizeof(data_t_interface_x_in_in));
	data_t_interface_y_out_out *y_out_out;
	y_out_out = (data_t_interface_y_out_out *)malloc(Y_OUT_OUT_LENGTH*sizeof(data_t_interface_y_out_out));

	data_t_x_in_in *x_in_in_int;
	x_in_in_int = (data_t_x_in_in *)malloc(X_IN_IN_LENGTH*sizeof (data_t_x_in_in));
	data_t_y_out_out *y_out_out_int;
	y_out_out_int = (data_t_y_out_out *)malloc(Y_OUT_OUT_LENGTH*sizeof (data_t_y_out_out));

	#else
	//for synthesis

	data_t_interface_x_in_in  x_in_in[X_IN_IN_LENGTH];
	data_t_interface_y_out_out  y_out_out[Y_OUT_OUT_LENGTH];

	static data_t_x_in_in  x_in_in_int[X_IN_IN_LENGTH];
	data_t_y_out_out  y_out_out_int[Y_OUT_OUT_LENGTH];

	#endif

	#if FLOAT_FIX_X_IN_IN == 1
	///////////////////////////////////////
	//load input vectors from memory (DDR)

	if(!(byte_x_in_in_offset & (1<<31)))
	{
		memcpy(x_in_in,(const data_t_memory*)(memory_inout+byte_x_in_in_offset/4),X_IN_IN_LENGTH*sizeof(data_t_memory));

    	//Initialisation: cast to the precision used for the algorithm
		input_cast_loop_x_in:for (int i=0; i< X_IN_IN_LENGTH; i++)
			x_in_in_int[i]=(data_t_x_in_in)x_in_in[i];

	}
	

	#elif FLOAT_FIX_X_IN_IN == 0
	///////////////////////////////////////
	//load input vectors from memory (DDR)

	if(!(byte_x_in_in_offset & (1<<31)))
	{
		memcpy(x_in_in_int,(const data_t_memory*)(memory_inout+byte_x_in_in_offset/4),X_IN_IN_LENGTH*sizeof(data_t_memory));
	}

	#endif



	///////////////////////////////////////
	//USER algorithm function (foo_user.cpp) call
	//Input vectors are:
	//x_in_in_int[X_IN_IN_LENGTH] -> data type is data_t_x_in_in
	//Output vectors are:
	//y_out_out_int[Y_OUT_OUT_LENGTH] -> data type is data_t_y_out_out
	foo_user_top: foo_user(	x_in_in_int,
							y_out_out_int);


	#if FLOAT_FIX_Y_OUT_OUT == 1
	///////////////////////////////////////
	//store output vectors to memory (DDR)

	if(!(byte_y_out_out_offset & (1<<31)))
	{
		output_cast_loop_y_out: for(int i = 0; i <  Y_OUT_OUT_LENGTH; i++)
			y_out_out[i]=(data_t_interface_y_out_out)y_out_out_int[i];

		//write results vector y_out to DDR
		memcpy((data_t_memory *)(memory_inout+byte_y_out_out_offset/4),y_out_out,Y_OUT_OUT_LENGTH*sizeof(data_t_memory));

	}
	#elif FLOAT_FIX_Y_OUT_OUT == 0
	///////////////////////////////////////
	//write results vector y_out to DDR
	if(!(byte_y_out_out_offset & (1<<31)))
	{
		memcpy((data_t_memory *)(memory_inout+byte_y_out_out_offset/4),y_out_out_int,Y_OUT_OUT_LENGTH*sizeof(data_t_memory));
	}

	#endif




}
