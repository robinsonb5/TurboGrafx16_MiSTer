// Stereo Hybrid PWM / Sigma Delta converter
//
// Uses 5-bit PWM, wrapped within a 10-bit Sigma Delta, with the intention of
// increasing the pulse width, since narrower pulses seem to equate to more noise

module hybrid_pwm_sd_stereo
(
	input clk,
	input [15:0] d_l,
	input [15:0] d_r,
	output reg q_l,
	output reg q_r
);

reg [4:0] pwmcounter;
reg [4:0] pwmthreshold_l;
reg [4:0] pwmthreshold_r;
reg [33:0] scaledin_l;
reg [33:0] scaledin_r;
reg [15:0] sigma_l;
reg [15:0] sigma_r;

// Periodic dumping of the accumulator to kill standing tones.
reg [12:0] dumpcounter;
reg dump;

always @(posedge clk)
begin
	dumpcounter<=dumpcounter+1;
	dump<=dumpcounter==0 ? 1'b1 : 1'b0;
end

always @(posedge clk)
begin
	pwmcounter<=pwmcounter+5'b1;

	if(pwmcounter==pwmthreshold_l)
		q_l<=1'b0;

	if(pwmcounter==pwmthreshold_r)
		q_r<=1'b0;

	if(pwmcounter==5'b00000) // Update threshold when pwmcounter reaches zero
	begin
		// Pick a new PWM threshold using a Sigma Delta
		scaledin_l<=33'h8000000 // (1<<(16-5))<<16, offset to keep centre aligned.
			+({1'b0,d_l}*16'hf000); // 30<<(16-5)-1;
		sigma_l<=scaledin_l[31:16]+{5'b00000,sigma_l[10:0]};	// Will use previous iteration's scaledin value
		pwmthreshold_l<=sigma_l[15:11]; // Will lag 2 cycles behind, but shouldn't matter.
		q_l<=1'b1;

		scaledin_r<=33'h8000000 // (1<<(16-5))<<16, offset to keep centre aligned.
			+({1'b0,d_r}*16'hf000); // 30<<(16-5)-1;
		sigma_r<=scaledin_r[31:16]+{5'b00000,sigma_r[10:0]};	// Will use previous iteration's scaledin value
		pwmthreshold_r<=sigma_r[15:11]; // Will lag 2 cycles behind, but shouldn't matter.
		q_r<=1'b1;
	end

	if(dump)	// Falling edge of reset, dump the accumulator
	begin
		sigma_l[10:0]<=11'b100_00000000;
		sigma_r[10:0]<=11'b100_00000000;
	end

end

endmodule
