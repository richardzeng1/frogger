module project(
		SW,
		KEY,
		CLOCK_50,

		// The ports below are for the VGA output.  Do not change.
		VGA_CLK,   						//	VGA Clock
		VGA_HS,							//	VGA H_SYNC
		VGA_VS,							//	VGA V_SYNC
		VGA_BLANK_N,						//	VGA BLANK
		VGA_SYNC_N,						//	VGA SYNC
		VGA_R,   						//	VGA Red[9:0]
		VGA_G,	 						//	VGA Green[9:0]
		VGA_B   						//	VGA Blue[9:0]
	);

	input [9:0] SW;
	input [3:0] KEY;
	input CLOCK_50;

	// Declare your inputs and outputs here
	// Do not change the following outputs
	output			VGA_CLK;   				//	VGA Clock
	output			VGA_HS;					//	VGA H_SYNC
	output			VGA_VS;					//	VGA V_SYNC
	output			VGA_BLANK_N;				//	VGA BLANK
	output			VGA_SYNC_N;				//	VGA SYNC
	output	[9:0]	VGA_R;   				//	VGA Red[9:0]
	output	[9:0]	VGA_G;	 				//	VGA Green[9:0]
	output	[9:0]	VGA_B;   				//	VGA Blue[9:0]

	wire [7:0] x;
	wire [6:0] y;
	wire load;
	wire move;
	wire counter_en, counter_reset;
	wire erase;
	wire [7:0] x_out;
	wire [6:0] y_out;
	wire [2:0] colour;
	wire frames;
	wire resetn;
	assign resetn = KEY[0];
	wire draw;
	assign draw = KEY[1];
	wire writeEn;
	wire [1:0] add_x, add_y;

	// Create an Instance of a VGA controller - there can be only one!
	// Define the number of colours as well as the initial background
	// image file (.MIF) for the controller.
	vga_adapter VGA(
		.resetn(resetn),
		.clock(CLOCK_50),
		.colour(colour),
		.x(x_out[7:0]),
		.y(y_out[6:0]),
		.plot(writeEn),
		// Signals for the DAC to drive the monitor.
		.VGA_R(VGA_R),
		.VGA_G(VGA_G),
		.VGA_B(VGA_B),
		.VGA_HS(VGA_HS),
		.VGA_VS(VGA_VS),
		.VGA_BLANK(VGA_BLANK_N),
		.VGA_SYNC(VGA_SYNC_N),
		.VGA_CLK(VGA_CLK)
	);

	defparam VGA.RESOLUTION = "160x120";
	defparam VGA.MONOCHROME = "FALSE";
	defparam VGA.BITS_PER_COLOUR_CHANNEL = 1;
	defparam VGA.BACKGROUND_IMAGE = "black.mif";


	datapath d0(
	    .clock(CLOCK_50),
	    .resetn(resetn),
	    .x_in(x[7:0]),
	    .y_in(y[6:0]),
		.load(load),
	    .move(move),
	    .colour_in(SW[9:7]),
	    .counter_en(counter_en),
	    .counter_reset(counter_reset),
	    .erase(erase),
	    .x_out(x_out[7:0]),
	    .y_out(y_out[6:0]),
	    .colour(colour[2:0]),
	    .frames(frames),
		.add_x(add_x[1:0]),
		.add_y(add_y[1:0])
	);

	control c0(
	    .clock(CLOCK_50),
	    .resetn(resetn),
	    .draw(draw),
	    .frames(frames),
	    .x(x[7:0]),
	    .y(y[6:0]),
	    .erase(erase),
	    .load(load),
	    .move(move),
	    .counter_en(counter_en),
	    .counter_reset(counter_reset),
	    .plot(writeEn),
		.add_x(add_x[1:0]),
		.add_y(add_y[1:0])
    );
endmodule

module datapath(
		input clock,
		input resetn,
		// the x and y used to set the registers
		input [7:0] x_in,
		input [6:0] y_in,
		input load, move,
		input [2:0] colour_in,
		input counter_en,
		input counter_reset,
		input erase,
		// used for drawing the box
		input [1:0] add_x, add_y,
		output [7:0] x_out,
		output [6:0] y_out,
		output [2:0] colour,
		output frames
	);

  assign colour[2:0] = erase ? 3'b000 : colour_in[2:0];

	// the direction registers
	reg x_dir;
	reg y_dir;

	reg [7:0] x = 8'b00001111;
	reg [6:0] y;

	//assign x_out = x + add_x;
	assign y_out = y + add_y;

	// counters for x and y
	// direction registers
	always @ (posedge clock) begin
    	if (~resetn) begin
	      	x <= 0;
	      	y <= 0;

	      	y_dir <= 1'b0;
    	end
	    else if (load) begin
	    	x <= x_in;
	    	y <= y_in;

			// starts going down

			y_dir <= 1'b0;
    	end
    	else if (move) begin
    	//x <= x_dir ? x + 1'b1 : x - 1'b1;
    	y <= y_dir ? y - 1'b1 : y + 1'b1;

    	if ((x == 159 && x_dir == 1'b1) || (x == 0 && x_dir == 1'b0))
        	x_dir <= ~x_dir;
    	if ((y == 119 && y_dir == 1'b0))
    		y_dir <= y_dir;
    	end
   	end

	wire fps;

	frame_rate delay_counter(
		.clock(clock),
		.resetn(counter_reset),
		.enable(counter_en),
		.fps(fps)
	);

	frame_counter framed(
		.clock(fps),
		.resetn(counter_reset),
		.enable(counter_en),
		.frames_out(frames)
	);

endmodule

module control(
		input clock,
		input resetn,
		input draw,
		input frames,

		// the x and y used to set registers
		output reg [7:0] x,
		output reg [6:0] y,

		output reg erase,
		output reg load, move,
		output reg counter_en, counter_reset,
		output reg plot,
		output reg [1:0] add_x, add_y
	);

	reg [3:0] county;

	reg [2:0] current_state, next_state;

	localparam  S_DRAW =         4'd0,
				S_DRAW_WAIT =    4'd1,
				S_COUNT_DRAW =   4'd2,
	           	S_WAIT =         4'd3,
				S_COUNT_ERASE =  4'd4,
	           	S_MOVE =         4'd5;

	// state table
	always @(*)
	begin: state_table
		case (current_state)
			S_DRAW: next_state = draw ? S_DRAW_WAIT : S_DRAW;
      		S_DRAW_WAIT: next_state = draw ? S_DRAW_WAIT : S_COUNT_DRAW;
      		S_COUNT_DRAW: next_state = (county == 4'b1111) ? S_WAIT : S_COUNT_DRAW;
      		S_WAIT: next_state = frames ? S_COUNT_ERASE : S_WAIT;
     		S_COUNT_ERASE: next_state = (county == 4'b1111) ? S_MOVE : S_COUNT_ERASE;
      		S_MOVE: next_state = S_COUNT_DRAW;
			default: next_state = S_DRAW;
		endcase
	end // state table

	// output logic
	always @(*)
	begin
		// by default all should be 0
	    x = 0;
	    y = 0;
	    load = 0;
	    move = 0;
	    erase = 0;
	    counter_en = 0;
	    counter_reset = 1;
    	plot = 0;
	 	add_x = 0;
	 	add_y = 0;

		case (current_state)
      		S_DRAW:  // load up the starting position
	        begin
				x = 3'b111;
				y = 0;
				load = 1'b1;
	        end
      		S_COUNT_DRAW:
			begin
				add_x[1:0] = county[1:0];
				add_y[1:0] = county[3:2];
				counter_reset = 1'b0;
		        plot = 1'b1;
			end
      		S_WAIT:
				counter_en = 1'b1;
      		S_COUNT_ERASE:
	        begin
				add_x[1:0] = county[1:0];
				add_y[1:0] = county[3:2];
				erase = 1'b1;
				plot = 1'b1;
	        end
      		S_MOVE:
	        begin
				move = 1'b1;
	        end
		endcase
	end

	// 4-bit counter to count the pixels being drawn
	always@ (posedge clock) begin
		if (!resetn)
			county <= 4'b0000;
		else if (plot)
			county <= county + 1'b1;
	end


	// current_state registers
	always@ (posedge clock) begin
		if (!resetn)
			current_state <= S_DRAW;
		else
			current_state <= next_state;
	end
endmodule


module frame_rate(
		input clock,
		input resetn,
		input enable,
		output fps
	);

	reg [19:0] fps_count;

	always @ (posedge clock, negedge resetn) begin
	if (~resetn)
		fps_count <= 833332;
	else if (enable) begin
		if (fps_count == 0)
			fps_count <= 833332;
		else
			fps_count <= fps_count - 1'b1;
		end
	end

	assign fps = (fps_count == 0);
endmodule

module frame_counter(
	input clock,
	input resetn,
	input enable,
	output frames_out);

	reg [3:0] frames;

	always @ (posedge clock, negedge resetn) begin
		if (~resetn)
			frames <= 14;
		else if (enable) begin
			if (frames == 0)
				frames <= 14;
			else
				frames <= frames - 1'b1;
			end
		end

	assign frames_out = (frames == 0);

endmodule
