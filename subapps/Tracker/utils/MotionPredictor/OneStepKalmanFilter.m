function [PoX, PoP] = OneStepKalmanFilter(A, Q, R, Y, PrX, PrP, C)
%ONESTEPKALMANFILTER This function uses one step ahead Kalman filter to
%calculate the best system state estimation
%
%% [System Model]:
% X(t+1) = A(t)X(t)+W(t)                    - X:System State, A:Transformation Matrix
% Y(t) = CX(t)+V(t)                          - Y:Observed State
% W~N(0,Q), V~N(0,R), COV(W,V)=0            - W:System Process Noise, V:Observation Noise
%
%% [one-step Kalman Filter Update]:
% K(t) = P(t)C'(CP(t)C'+R)^(-1)              - Kalman Gain
% X(t+1) = A(t)(X(t)+K(t)(Y(t)-CX(t)))       - Posterior System State
% P(t+1) = A(t)(I-K(t)C)P(t)A(t)'+Q          - Posterior Error
% X(0) = mean(eX(t<0)), P(0) = var(eX(t<0)) - Initial Value
%
%% [Using]:
% Input:
%   - A: n-ny-n double matrix, indicate system state transformation
%   - Q: n-ny-n nonnegtive double matrix, indicate system noise covariance
%   - R: m-ny-m nonnegtive double matrix, indicate measurement noise covariance
%   - Y: m-ny-1 double vector, indicate measurement value
%   - PrX: n-by-1 double vector, previous filtered value, indicate system state
%   - PrP: n-by-1 double vector, previous estimated system error
%   - C: 
% Output:
%   - PoX: n-by-1 double vector, predicted filtered value, indicate system state
%   - PoP: n-by-1 double vector, predicted estimated system error

%% Calculation
K = PrP*pinv(PrP+R, 1e-8);  % consider PrP+R too close singular matrix

PoX = A*(PrX + K*(Y-PrX));

PoP = A*(eye(size(K))-K)*PrP*A' + Q;
end

