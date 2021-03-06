
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% icl::protoip
% Authors: asuardi <https://github.com/asuardi>, bulatkhusainov <https://github.com/bulatkhusainov
% Date: November - 2014
%% %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%



function test_HIL(project_name)


addpath('../../.metadata');
mex FPGAclientMATLAB.c
load_configuration_parameters(project_name)

load ../../../../src/prob_data.mat

rng('shuffle');


% determine if remainder exists
N_sim = floor(sim_par.Tsim/current_design.Ts);
Ts_last = sim_par.Tsim - N_sim*current_design.Ts;
if Ts_last > 1e-10
    N_sim = N_sim + 1;
end



for k = 1:size(sim_par.x_hat,2) % perform simulations was several initial conditions
    soc_x_hat_in = (sim_par.x_hat(1:end,k))'; % initial condition is defined in generate_code.m
    settling_time = sim_par.Tsim; % this value will be used in case if system does not settle
    system_settled = 0;

    for i=1:N_sim
        tmp_disp_str=strcat('Test number ',num2str(i));
        disp(tmp_disp_str)


        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% generate random stimulus vector soc_x_hat_in. (-5<=x_hat_in <=5)
        %soc_x_hat_in=rand(1,SOC_X_HAT_IN_LENGTH)*10-5;

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %save soc_x_hat_in_log
        if (TYPE_TEST==0)
            filename = strcat('../test/results/', project_name ,'/soc_x_hat_in_log.dat');
        else
            filename = strcat('../test/results/', project_name ,'/x_hat_in_log.dat');
        end
        fid = fopen(filename, 'a+');

        for j=1:length(soc_x_hat_in)
            fprintf(fid, '%2.18f,',soc_x_hat_in(j));
        end
        fprintf(fid, '\n');

        fclose(fid);


        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% Start Matlab timer
        tic

        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% send the stimulus to the FPGA simulation model when IP design test or to FPGA evaluation borad when IP prototype, execute the algorithm and read back the results
        % reset IP
        Packet_type=1; % 1 for reset, 2 for start, 3 for write to IP vector packet_internal_ID, 4 for read from IP vector packet_internal_ID of size packet_output_size
        packet_internal_ID=0;
        packet_output_size=1;
        data_to_send=1;
        FPGAclientMATLAB(data_to_send,Packet_type,packet_internal_ID,packet_output_size);


        % send data to FPGA
        % send soc_x_hat_in
        Packet_type=3; % 1 for reset, 2 for start, 3 for write to IP vector packet_internal_ID, 4 for read from IP vector packet_internal_ID of size packet_output_size
        packet_internal_ID=0;
        packet_output_size=1;
        data_to_send=soc_x_hat_in;
        FPGAclientMATLAB(data_to_send,Packet_type,packet_internal_ID,packet_output_size);


        % start FPGA
        Packet_type=2; % 1 for reset, 2 for start, 3 for write to IP vector packet_internal_ID, 4 for read from IP vector packet_internal_ID of size packet_output_size
        packet_internal_ID=0;
        packet_output_size=1;
        data_to_send=0;
        FPGAclientMATLAB(data_to_send,Packet_type,packet_internal_ID,packet_output_size);


        % read data from FPGA
        % read fpga_soc_u_opt_out
        Packet_type=4; % 1 for reset, 2 for start, 3 for write to IP vector packet_internal_ID, 4 for read from IP vector packet_internal_ID of size packet_output_size
        packet_internal_ID=0;
        packet_output_size=SOC_U_OPT_OUT_LENGTH;
        data_to_send=0;
        [output_FPGA, time_IP] = FPGAclientMATLAB(data_to_send,Packet_type,packet_internal_ID,packet_output_size);
        fpga_soc_u_opt_out=output_FPGA;
        % Stop Matlab timer
        time_matlab=toc;
        time_communication=time_matlab-time_IP;



        % apply the optimal input
        if (i < N_sim) || (Ts_last < 1e-10)
            x_hat_prev = soc_x_hat_in;
            soc_x_hat_in = (model.a*soc_x_hat_in' + model.b*fpga_soc_u_opt_out(1:current_design.m_inputs))';

            if system_settled == 0
                Ts_sim_fine = current_design.Ts;
                system_energy = norm(soc_x_hat_in);
                while system_energy < sim_par.epsilon_settling
                    system_settled = 1;

                    model_remainder = c2d(model_c, Ts_sim_fine);
                    x_next_local = (model_remainder.a*x_hat_prev' + model_remainder.b*fpga_soc_u_opt_out(1:current_design.m_inputs))';

                    system_energy = norm(x_next_local);
                    Ts_sim_fine = 0.9*Ts_sim_fine;

                    settling_time = (i-1)*current_design.Ts + Ts_sim_fine/(0.9^2);
                end

            end
        else
             % hadndle the remainder
             model_remainder = c2d(model_c, Ts_last);
             soc_x_hat_in = (model_remainder.a*soc_x_hat_in' + model_remainder.b*fpga_soc_u_opt_out(1:current_design.m_inputs))';     
             
             % do not check system settling in the remainder
        end


        %save fpga_soc_u_opt_out_log.dat
        if (TYPE_TEST==0)
            filename = strcat('../test/results/', project_name ,'/fpga_soc_u_opt_out_log.dat');
        else
            filename = strcat('../test/results/', project_name ,'/fpga_u_opt_out_log.dat');
        end
        fid = fopen(filename, 'a+');

        for j=1:length(fpga_soc_u_opt_out)
            fprintf(fid, '%2.18f,',fpga_soc_u_opt_out(j));
        end
        fprintf(fid, '\n');

        fclose(fid);



        %save fpga_time_log.dat
        if (TYPE_TEST==0)
            filename = strcat('../test/results/', project_name ,'/fpga_time_log.dat');
        else
            filename = strcat('../test/results/', project_name ,'/fpga_time_log.dat');
        end
        fid = fopen(filename, 'a+');

        fprintf(fid, '%2.18f, %2.18f \n',time_IP, time_communication);

        fclose(fid);


        %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
        %% compute with Matlab and save in a file simulation results
    %	[matlab_u_opt_out] = foo_user(project_name,x_in_in);

    end

    % print the last state
        %save soc_x_hat_in_log
        if (TYPE_TEST==0)
            filename = strcat('../test/results/', project_name ,'/soc_x_hat_in_log.dat');
        else
            filename = strcat('../test/results/', project_name ,'/x_hat_in_log.dat');
        end
        fid = fopen(filename, 'a+');

        for j=1:length(soc_x_hat_in)
            fprintf(fid, '%2.18f,',soc_x_hat_in(j));
        end
        fprintf(fid, '\n');
        fclose(fid);

    % print the settling time
        %save settling_time.dat
        if (TYPE_TEST==0)
            filename = strcat('../test/results/', project_name ,'/settling_time.dat');
        else
            filename = strcat('../test/results/', project_name ,'/settling_time.dat');
        end
        fid = fopen(filename, 'a+');

        fprintf(fid, '%2.18f \n',settling_time);

        fclose(fid);
    
end



%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%write a dummy file to tell tcl script to continue with the execution

filename = strcat('_locked');
fid = fopen(filename, 'w');
fprintf(fid, 'locked write\n');
fclose(fid);

if strcmp(TYPE_DESIGN_FLOW,'vivado')
	quit;
end

end
