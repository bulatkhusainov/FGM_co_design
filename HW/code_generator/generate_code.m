%% it is assumed that design parameters are in the workspace

if not( exist('current_design','var') && any(strcmp('Ts',fieldnames(current_design))) ); current_design.Ts = 0.05; end;  % sampling time
if not( exist('current_design','var') && any(strcmp('N',fieldnames(current_design))) ); current_design.N = 10; end;  % horizon length
current_design.n_bits_integer = 4; % number of integer bits
if not( exist('current_design','var') && any(strcmp('n_bits_fraction',fieldnames(current_design))) ); current_design.n_bits_fraction = 14; end;  % number of fraction bits  
current_design.clock_target_freq = 100;
if not( exist('current_design','var') && any(strcmp('n_iter',fieldnames(current_design))) ); current_design.n_iter = 100; end; % number of FGM iterations (required for PIL)
if not( exist('current_design','var') && any(strcmp('q_ratio',fieldnames(current_design))) ); current_design.q_ratio = 1; end;  % ratio of the weights position/velocity

%% calculate problem data based on design parameters
% generate LTI SS model
[model, model_c, current_design]= model_generator(current_design);
% formulate a QP by condensing
qp_problem = qp_generator(current_design, model, model_c);
 
if ~(qp_problem.mu > 0) 
    save ../src/prob_data.mat model model_c qp_problem current_design 
else% the remaining code will not make sense if Hessian is not convex
    %% simulation parameters
    % initial condition
    %a = -0.2; b = 0.2; % states intervals 
    %sim_par.x_hat = a + (b-a).*rand(5,current_design.n_states); 
    %sim_par.x_hat = sim_par.x_hat';
    load x_init_cond_set
    sim_par.x_hat = x_init_cond_set;
    sim_par.Tsim = 20; % simulation time
    sim_par.epsilon_settling = 0.02;

    %% save data from matlab workspace
    save ../src/prob_data.mat model model_c qp_problem current_design sim_par

    %% generate C code for a HW implementation
    % header file
    fileID = fopen('../src/user_fgm_mpc.h','w');

    fprintf(fileID,'#ifndef USER_FGM_MPC \n');
    fprintf(fileID,'#define USER_FGM_MPC \n\n');


    fprintf(fileID,'#define n_iter    %d\n', current_design.n_iter);
    fprintf(fileID,'#define n_states  %d\n', size(model.a,1));
    fprintf(fileID,'#define m_inputs  %d\n', size(model.b,2));
    fprintf(fileID,'#define n_opt_var %d\n', current_design.N*size(model.b,2));
    fprintf(fileID,'//#define N         %d\n\n', current_design.N);

    fprintf(fileID,'#include "user_protoip_definer.h"\n');
    fprintf(fileID,'#ifdef PROTOIP\n');
    fprintf(fileID,'\t#include "foo_data.h"\n');
    fprintf(fileID,'\ttypedef data_t_x_hat_in d_fgm;\n');
    fprintf(fileID,'#else\n');
    fprintf(fileID,'\ttypedef float d_fgm;\n');
    fprintf(fileID,'#endif\n\n');


    fprintf(fileID,'void fgm_mpc(d_fgm x_hat[n_states], d_fgm u_opt[n_opt_var]);\n\n');

    fprintf(fileID,'#endif \n');

    fclose(fileID);

    % C file
    fileID = fopen('../src/user_fgm_mpc.cpp','w');

    fprintf(fileID,'#include "user_fgm_mpc.h"\n');
    fprintf(fileID,'#include "math.h"\n');
    fprintf(fileID,'//#include "mex.h"\n\n');

    fprintf(fileID,'void fgm_mpc(d_fgm x_hat[n_states], d_fgm u_opt[n_opt_var])\n');
    fprintf(fileID,'{\n');

    fprintf(fileID,'\t int i,j,k;\n\n');

    fprintf(fileID,'\t //data arrays\n');
    H_diff_negative = qp_problem.H_diff_negative; fprintf(fileID,strcat('\t',variables_declaration('2d',H_diff_negative), '\n'));
    h_x = qp_problem.h_x; fprintf(fileID,strcat('\t',variables_declaration('2d',h_x), '\n'));
    b_upper = qp_problem.b_upper; fprintf(fileID,strcat('\t',variables_declaration('1d',b_upper), '\n'));
    b_lower = qp_problem.b_lower; fprintf(fileID,strcat('\t',variables_declaration('1d',b_lower), '\n'));
    beta_var = qp_problem.beta_var; fprintf(fileID,strcat('\t',variables_declaration('var',beta_var),'\n'));
    beta_plus = qp_problem.beta_plus; fprintf(fileID,strcat('\t',variables_declaration('var',beta_plus),'\n\n'));



    fprintf(fileID,'\td_fgm Z_new[n_opt_var],Z[n_opt_var];\n');
    fprintf(fileID,'\td_fgm Y_new[n_opt_var], Y[n_opt_var];\n');
    fprintf(fileID,'\td_fgm h[n_opt_var];\n');
    fprintf(fileID,'\td_fgm T[n_opt_var];\n\n');

    fprintf(fileID,'\td_fgm iter_error;\n\n');

    fprintf(fileID,'\treset_grad: for(i = 0; i < n_opt_var; i++) \n');
    fprintf(fileID,'\t{\n');
    fprintf(fileID,'\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\th[i] = 0;\n');
    fprintf(fileID,'\t}\n');

    fprintf(fileID,'\tgrad: for(j = 0; j < n_states; j++)\n');
    fprintf(fileID,'\t{\n');
    fprintf(fileID,'\t\tgrad_1: for(i = 0; i < n_opt_var; i++) \n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\t#pragma HLS LOOP_FLATTEN\n');
    fprintf(fileID,'\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\th[i] += x_hat[j] * h_x[j][i];\n');
    fprintf(fileID,'\t\t}\n');
    fprintf(fileID,'\t}\n\n');


    fprintf(fileID,'\tguess_initialization: for(i = 0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t{\n');
    fprintf(fileID,'\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\tZ[i] = 0;\n');
    fprintf(fileID,'\t\tY[i] = 0;\n');
    fprintf(fileID,'\t}\n\n');

    fprintf(fileID,'\titeration_loop: for(k = 0; k < n_iter; k++)\n');
    fprintf(fileID,'\t{\n');

    fprintf(fileID,'\t\treset_output:for(i = 0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\tT[i] = 0;\n');
    fprintf(fileID,'\t\t}\n\n');

    fprintf(fileID,'\t\tmv_mult:for(j = 0; j < n_opt_var; j++)\n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\tvv_mult: for(i = 0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t\t\t{\n');
    fprintf(fileID,'\t\t\t\t#pragma HLS LOOP_FLATTEN\n');
    fprintf(fileID,'\t\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\t\tT[i] += -H_diff_negative[i][j] * Y[j];\n');
    fprintf(fileID,'\t\t\t}\n');
    fprintf(fileID,'\t\t}\n\n');

    fprintf(fileID,'\t\tsubtract_gradient:for(i = 0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\tT[i] = T[i] - h[i];\n');
    fprintf(fileID,'\t\t}\n\n');

    fprintf(fileID,'\t\tprojection_loop: for(i = 0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\tif(T[i] > b_upper[i])\n');
    fprintf(fileID,'\t\t\t{\n');
    fprintf(fileID,'\t\t\t\tZ_new[i] = b_upper[i];\n');
    fprintf(fileID,'\t\t\t}\n');
    fprintf(fileID,'\t\t\telse if (T[i] < b_lower[i])\n');
    fprintf(fileID,'\t\t\t{\n');
    fprintf(fileID,'\t\t\t\tZ_new[i] = b_lower[i];\n');
    fprintf(fileID,'\t\t\t}\n');
    fprintf(fileID,'\t\t\telse\n');
    fprintf(fileID,'\t\t\t{\n');
    fprintf(fileID,'\t\t\t\tZ_new[i] = T[i];\n');
    fprintf(fileID,'\t\t\t}\n');
    fprintf(fileID,'\t\t}\n\n');

    fprintf(fileID,'\t\tfgm_step:for(i = 0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\tY_new[i] = beta_plus * Z_new[i] - beta_var * Z[i];		\n');
    fprintf(fileID,'\t\t}\n\n');

    fprintf(fileID,'\t\t//iter_error = 0;\n');
    fprintf(fileID,'\t\tupdate_loop: for(i=0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t\t{\n');
    fprintf(fileID,'\t\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\t\t//iter_error += fabs(Y[i] - Y_new[i]);\n');
    fprintf(fileID,'\t\t\tZ[i] = Z_new[i];\n');
    fprintf(fileID,'\t\t\tY[i] = Y_new[i];\n');
    fprintf(fileID,'\t\t}\n');
    fprintf(fileID,'\t\t//printf("error[%%d] = %%f \\n",k,iter_error);\n');
    fprintf(fileID,'\t}\n\n');

    fprintf(fileID,'\toutput_loop: for(i=0; i < n_opt_var; i++)\n');
    fprintf(fileID,'\t{\n');
    fprintf(fileID,'\t\t#pragma HLS PIPELINE\n');
    fprintf(fileID,'\t\tu_opt[i] = Y_new[i];\n');
    fprintf(fileID,'\t}\n');


    fprintf(fileID,'}\n');
end


