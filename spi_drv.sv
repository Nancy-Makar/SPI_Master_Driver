/*
* MIT License
* 
* Copyright (c) 2023 Nancy Makar
* 
* Permission is hereby granted, free of charge, to any person obtaining a copy
* of this software and associated documentation files (the "Software"), to deal
* in the Software without restriction, including without limitation the rights
* to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
* copies of the Software, and to permit persons to whom the Software is
* furnished to do so, subject to the following conditions:
* 
* The above copyright notice and this permission notice shall be included in all
* copies or substantial portions of the Software.
* 
* THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
* IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
* FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
* AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
* LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
* OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
* SOFTWARE.
 */




// The clock divider: is a simple counter that counts CLK_DIVIDE cycles of clk.
// It ouputs 1 for counter < (CLK_DIVIDE - 1) and 0 otherwise. See clock_divider module for impelementaion

// Latching MOSI and MISO: Using the clock divider above, this module generates a clock, SCLK_DOUBLE, that is double the frequency of SCLK.
// An oscillation takes place every 2 SCLK_DOUBLE cycles, 
// on the first cycle SCLK set to 1 and MISO is recieved
// on the first cycle SCLK is set to 0 and MOSI is transmitted

module spi_drv #(
    parameter integer               CLK_DIVIDE  = 100, // Clock divider to indicate frequency of SCLK
    parameter integer               SPI_MAXLEN  = 32   // Maximum SPI transfer length
) (
    input                           clk,
    input                           sresetn,        // active low reset, synchronous to clk
    
    // Command interface 
    input                           start_cmd,     // Start SPI transfer
    output reg                      spi_drv_rdy,   // Ready to begin a transfer
    input  [$clog2(SPI_MAXLEN):0]   n_clks,        // Number of bits (SCLK pulses) for the SPI transaction
    input  [SPI_MAXLEN-1:0]         tx_data,       // Data to be transmitted out on MOSI
    output reg [SPI_MAXLEN-1:0]     rx_miso,       // Data read in from MISO
    
    // SPI pins
    output reg                      SCLK,          // SPI clock sent to the slave
    output reg                      MOSI,          // Master out slave in pin (data output to the slave)
    input                           MISO,          // Master in slave out pin (data input from the slave)
    output reg                      SS_N           // Slave select, will be 0 during a SPI transaction
);


	
	//////////////////////////////////////////
	// Registers for the TxRx state machine //
	//////////////////////////////////////////
	reg SCLK_double; 											// Clock that is double the frequency of SCLK
	reg [$clog2(SPI_MAXLEN): 0] counter; 				// Counter to count the number of bits transmitted/reseved
	reg [2:0] current_state_TxRx;							// Current state of state machine
	reg [2:0] next_state_TxRx;								// Next state of state machine
	reg transmission_complete;								// Signal to indicate that exchange of data is finished, will be set for one cyle of SCLK_double and will clear in the idle state
	reg reset_TxRx;											// Reset signal to erase rx_miso and MOSI, is set high when sresetn is low
	
	
	/////////////////////////////////////////////////////////////////
	// registers for the state machine communicating with the Host //
	/////////////////////////////////////////////////////////////////
	reg [$clog2(SPI_MAXLEN):0] n_clks_latch;			// register to latch n_clks when start_cmd is asserted before the start of the transmit/recieve cylce
	reg [SPI_MAXLEN-1:0] tx_data_latch;					// register to latch tx_data when start_cmd is asserted before the start of the transmit/recieve cylce
	reg [1:0] current_state;								
	reg [1:0] next_state;
	

	////////////////////
	// Initial states //
	////////////////////
	initial begin
		counter = 0;
		transmission_complete <= 0;
	end
	

	/////////////////////////////////////////////////////////////
	// States of the state machine communicating with the host //
	/////////////////////////////////////////////////////////////
	localparam H_IDLE = 2'b00;
	localparam H_START = 2'b01;
	localparam H_WAIT = 2'b10;
	
	
	//////////////////////////////////////////////
	// States of the transmission state machine //
	//////////////////////////////////////////////
	localparam T_IDLE = 3'b000;
	localparam T_WAIT1 = 3'b001;
	localparam T_WAIT2 = 3'b010;
	localparam TX = 3'b100;
	localparam RX = 3'b101;
	
	
	
	///////////////////////////////////////////////////////////
	// Generate a clock that is double the frequency pf SCLK //
	///////////////////////////////////////////////////////////
	clock_divider #( .DIVISOR(CLK_DIVIDE / 2))clk_div_1(
		.clk_in(clk),
		.rst(~sresetn),
		.clk_out(SCLK_double)
	);
		
		
	//////////////////////////////////////////////
	// Transmisison and Recieving state machine //
	//////////////////////////////////////////////
	
	// In this state machine, 
	// SS_N will be high for one SCLK before the first posedge of SCLK (before transmitting the first bit) 
	// and low for one SCLK cycle after the last posedge of SCLK (after transmitting the last bit to the slave) --> (1)
	// transmission_complete signal will be set for one SCLK_double cycle to indicate that exchange of data is complete,
	// but the host needs to wait for this state machine to go back to idel to allow for SS_N to stay low as mentioned in (1).
	always@(posedge SCLK_double)
		current_state_TxRx <= next_state_TxRx;
		
	
	always@(posedge SCLK_double, posedge reset_TxRx) begin	
		if(reset_TxRx) begin
			rx_miso <= 0;
			MOSI <= 0;
			SS_N <= 1;
			SCLK <= 0;
			counter <= 0;
			transmission_complete <= 0;
			next_state_TxRx <= T_IDLE;
		end
		
		else if(spi_drv_rdy) begin
			SS_N <= 1;
			SCLK <= 0;
			counter <= 0;
			next_state_TxRx <= T_IDLE;
			transmission_complete <= 0;
		end
		
		else begin
			case (next_state_TxRx)
				T_IDLE: begin
					SCLK <= 0;
					if(counter == n_clks_latch) begin
						next_state_TxRx <= T_IDLE;  	
						transmission_complete <= 1;
						SS_N <= 1;
					end
					else begin
						SS_N <= 0;
						next_state_TxRx <= T_WAIT1;
						transmission_complete <= 0;
					end
				end
				
				T_WAIT1: begin									// wait state to allow for the conditions of SS_N mentioned above
					SCLK <= 0;
					SS_N <= 0;
					transmission_complete <= 0;
					next_state_TxRx <= TX;
				end
				
				TX: begin
					rx_miso[n_clks_latch - counter - 1] <= MISO;
					SCLK <= 1;									// transmission on posedge of SCLK
					SS_N <= 0;
					transmission_complete <= 0;
					next_state_TxRx <= RX;
				end
				
				RX: begin
					MOSI <= tx_data_latch[n_clks_latch - counter - 1];
					SCLK <= 0;									// recieving on negedge of SCLK
					SS_N <= 0;
					next_state_TxRx <= TX;				// oscillate between transmission and recieving
					counter <= counter + 1; 
					transmission_complete <= 0;
					if(counter == n_clks_latch - 1)
						next_state_TxRx <= T_IDLE;		// after transmission of n_clk bits, go back to idle
					end
				
				default: begin
					SS_N <= 1;
					SCLK <= 0;
					counter <= 0;
					transmission_complete <= 0;
					next_state_TxRx <= T_IDLE;
				end
			endcase
		end
	end

	
	///////////////////////////////////////////////////
	// State machine that communicates with the host //
	///////////////////////////////////////////////////
	
	// This state machine handles signals to and from the host synchronously on posedge of clk
	always@(posedge clk) begin
		if(~sresetn) begin
			current_state <= H_IDLE;
			reset_TxRx <= 1;
		end
		else begin
			current_state <= next_state;
			reset_TxRx <= 0;
		end
	end
	
	always@(*) begin
		case (current_state)
			H_IDLE: begin
				spi_drv_rdy <= 1;						// indicatation of completion of the command by transitioning spi_drv_rdy from 0 to 1 and siganlling the TxRx stat machine idle
				
				if(start_cmd) begin 				
					next_state <= H_WAIT;
					n_clks_latch <= n_clks; 		// latch n_clks when start_cmd is high
					tx_data_latch <= tx_data;		// latch tx_data when start_cmd is high
						
				end
				else begin
					next_state <= H_IDLE;
				end
			end
			
															
			H_WAIT: begin 								// wait for transmission_complete signal to go low indicating that the transmission state machine is in idle state 
				if (~transmission_complete)		
					next_state <= H_START;
				else 
					next_state <= H_WAIT;
			end
				
			
			H_START: begin
				spi_drv_rdy <= 0;						// acknowledge receipt of command by issuing a transition on spi_drv_rdy from 1 to 0 and signal the TxRx state machine to start data exchange
				if(transmission_complete)			// upon recienving the transmission_complete signal, go back to idles 
					next_state <= H_IDLE;
				else
					next_state <= H_START;
			end
			
			default: begin
				spi_drv_rdy <= 1;
				next_state <= H_IDLE;
			end
		endcase
	end


endmodule: spi_drv
