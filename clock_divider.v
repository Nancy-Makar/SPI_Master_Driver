module clock_divider #(
parameter integer DIVISOR = 100
)(
	input clk_in,
	input rst, //active high reset, synchronous to clk
	output reg clk_out
);

	reg[DIVISOR-1:0] counter = 0;
	
	always @(posedge clk_in) begin
		if(rst)
			clk_out <= 0;
		else begin
			counter <= counter + 1;
			if(counter >= (DIVISOR - 1))
				counter <= 0;
			clk_out <= (counter < DIVISOR / 2) ? 1'b1 : 1'b0;
		end
	end
	
endmodule
