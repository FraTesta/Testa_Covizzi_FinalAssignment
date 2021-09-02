function MainDexrov
addpath('./simulation_scripts');
clc;
clear;
close all

% Simulation variables (integration and final time)
deltat = 0.005;
end_time = 20;
loop = 1;
maxloops = ceil(end_time/deltat);

% this struct can be used to evolve what the UVMS has to do
mission.phase = 1;
mission.phase_time = 0;

% Rotation matrix to convert coordinates between Unity and the <w> frame
% do not change
wuRw = rotation(0,-pi/2,pi/2);
vRvu = rotation(-pi/2,0,-pi/2);

% pipe parameters
u_pipe_center = [-10.66 31.47 -1.94]'; % in unity coordinates
pipe_center = wuRw'*u_pipe_center;     % in world frame coordinates
pipe_radius = 0.3;

% UDP Connection with Unity viewer v2
uArm = udp('127.0.0.1',15000,'OutputDatagramPacketSize',28);
uVehicle = udp('127.0.0.1',15001,'OutputDatagramPacketSize',24);
fopen(uVehicle);
fopen(uArm);



% initialize uvms structure
uvms = InitUVMS('DexROV');
% uvms.q 
% Initial joint positions. You can change these values to initialize the simulation with a 
% different starting position for the arm
uvms.q = [-0.0031 1.2586 0.0128 -1.2460 0.0137 0.0853-pi/2 0.0137]';
% uvms.p
% initial position of the vehicle
% the vector contains the values in the following order
% [x y z r(rot_x) p(rot_y) y(rot_z)]
% RPY angles are applied in the following sequence
% R(rot_x, rot_y, rot_z) = Rz (rot_z) * Ry(rot_y) * Rx(rot_x)
uvms.v_init_pose = [-1.9379 10.4813-6.1 -29.7242-0.1 0 0 0]';
uvms.p = uvms.v_init_pose;

% initial goal position definition
% slightly over the top of the pipe
distanceGoalWrtPipe = 0.3;
uvms.goalPosition = pipe_center + (pipe_radius + distanceGoalWrtPipe)*[0 0 1]';
uvms.wRg = rotation(pi,0,0);
uvms.wTg = [uvms.wRg uvms.goalPosition; 0 0 0 1];

offset = 1;
uvms.vgoalPosition = pipe_center + (pipe_radius + distanceGoalWrtPipe + offset)*[0 0 1]';
uvms.wRgv = rotation(0, -0.06 ,0.5); %1.2
uvms.wTgv = [uvms.wRgv uvms.vgoalPosition; 0 0 0 1]; % new matrix which rappresent the goal from the veichle

% defines the tool control point
uvms.eTt = eye(4);

% Preallocation
plt = InitDataPlot(maxloops, uvms);

tic
for t = 0:deltat:end_time
    % update all the involved variables
    uvms = UpdateTransforms(uvms);
    uvms = ComputeJacobians(uvms);
    uvms = ComputeTaskReferences(uvms, mission);
    uvms = ComputeActivationFunctions(uvms, mission);
   
    % main kinematic algorithm initialization
    % rhop order is [qdot_1, qdot_2, ..., qdot_7, xdot, ydot, zdot, omega_x, omega_y, omega_z]
    rhop = zeros(13,1);
    Qp = eye(13); 
    % add all the other tasks here!
    % the sequence of iCAT_task calls defines the priority
    if mission.phase == 1
%     [Qp, rhop] = iCAT_task(uvms.A.mu,   uvms.Jmu,   Qp, rhop, uvms.xdot.mu, 0.000001, 0.0001, 10);
    [Qp, rhop] = iCAT_task(uvms.A.ua,  uvms.Jua,    Qp, rhop, uvms.xdot.ua,  0.0001,   0.01, 10);
    [Qp, rhop] = iCAT_task(uvms.A.ha,   uvms.Jha,   Qp, rhop, uvms.xdot.ha, 0.0001,   0.01, 10);
    [Qp, rhop] = iCAT_task(uvms.A.t,    uvms.Jt,    Qp, rhop, uvms.xdot.t,  0.0001,   0.01, 10);
    [Qp, rhop] = iCAT_task(uvms.A.vpos,  uvms.Jvpos,    Qp, rhop, uvms.xdot.vpos,  0.0001,   0.01, 10); % Ex1 position control task to reach the goal with the <v> frame
    [Qp, rhop] = iCAT_task(uvms.A.vatt,  uvms.Jvatt,    Qp, rhop, uvms.xdot.vatt,  0.0001,   0.01, 10); % Ex1 altitude control task to reach the goal with the <v> frame
    
%     [Qp, rhop] = iCAT_task(uvms.A.ps,    uvms.Jps,    Qp, rhop, uvms.xdot.ps,  0.0001,   0.01, 10);
    [Qp, rhop] = iCAT_task(eye(13),     eye(13),    Qp, rhop, zeros(13,1),  0.0001,   0.01, 10);    % this task should be the last one
    
    % get the two variables for integration
    uvms.q_dot = rhop(1:7);
    uvms.p_dot = rhop(8:13);
    
    else
        % TPIK1
        
        [Qp1, rhop1] = iCAT_task(uvms.A.ha,   uvms.Jha,   Qp, rhop, uvms.xdot.ha, 0.0001,   0.01, 10);
        [Qp1, rhop1] = iCAT_task(uvms.A.vpos,  uvms.Jvpos,    Qp1, rhop1, uvms.xdot.vpos,  0.0001,   0.01, 10); % Ex1 position control task to reach the goal with the <v> frame
        [Qp1, rhop1] = iCAT_task(uvms.A.vatt,  uvms.Jvatt,    Qp1, rhop1, uvms.xdot.vatt,  0.0001,   0.01, 10); % Ex1 altitude control task to reach the goal with the <v> frame
        [Qp1, rhop1] = iCAT_task(uvms.A.t,    uvms.Jt,    Qp1, rhop1, uvms.xdot.t,  0.0001,   0.01, 10);
        [Qp1, rhop1] = iCAT_task(uvms.A.ps,    uvms.Jps,    Qp1, rhop1, uvms.xdot.ps,  0.0001,   0.01, 10);
        [Qp1, rhop1] = iCAT_task(eye(13),     eye(13),    Qp1, rhop1, zeros(13,1),  0.0001,   0.01, 10); 
        
        % TPIK2
        [Qp2, rhop2] = iCAT_task(uvms.A.ua,  uvms.Jua,    Qp, rhop, uvms.xdot.ua,  0.0001,   0.01, 10);
        [Qp2, rhop2] = iCAT_task(uvms.A.ha,   uvms.Jha,   Qp2, rhop2, uvms.xdot.ha, 0.0001,   0.01, 10);
        [Qp2, rhop2] = iCAT_task(uvms.A.t,    uvms.Jt,    Qp2, rhop2, uvms.xdot.t,  0.0001,   0.01, 10);
        [Qp2, rhop2] = iCAT_task(uvms.A.vpos,  uvms.Jvpos,    Qp2, rhop2, uvms.xdot.vpos,  0.0001,   0.01, 10); % Ex1 position control task to reach the goal with the <v> frame
        [Qp2, rhop2] = iCAT_task(uvms.A.vatt,  uvms.Jvatt,    Qp2, rhop2, uvms.xdot.vatt,  0.0001,   0.01, 10); % Ex1 altitude control task to reach the goal with the <v> frame        
        [Qp2, rhop2] = iCAT_task(uvms.A.ps,    uvms.Jps,    Qp2, rhop2, uvms.xdot.ps,  0.0001,   0.01, 10);
        [Qp2, rhop2] = iCAT_task(eye(13),     eye(13),    Qp2, rhop2, zeros(13,1),  0.0001,   0.01, 10);
        
        uvms.q_dot = rhop2(1:7);
        uvms.p_dot = rhop1(8:13);
    end
    
    % Integration
	uvms.q = uvms.q + uvms.q_dot*deltat;
    % disturbances on wx of the vehicle
    uvms.p_dot(4) = uvms.p_dot(4) + 0.2*sin(2*pi*0.5*t);
    % beware: p_dot should be projected on <v>
    uvms.p = integrate_vehicle(uvms.p, uvms.p_dot, deltat);
    
    % check if the mission phase should be changed
    [uvms, mission] = UpdateMissionPhase(uvms, mission);
    
    % send packets to Unity viewer
    SendUdpPackets(uvms,wuRw,vRvu,uArm,uVehicle);
        
    % collect data for plots
    plt = UpdateDataPlot(plt,uvms,t,loop);
    loop = loop + 1;
   
    % add debug prints here
    if (mod(t,0.1) == 0)
        t
%         uvms.p'
        mission.phase
    end
    
    % enable this to have the simulation approximately evolving like real
    % time. Remove to go as fast as possible
    SlowdownToRealtime(deltat);
end

fclose(uVehicle);
fclose(uArm);

PrintPlot(plt);

end