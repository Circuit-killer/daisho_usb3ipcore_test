
module ddr_sync_dc_1x_clk_to_2x_clk #(
	parameter SRC_WIDTH = 32,
	parameter DST_WIDTH = SRC_WIDTH / 2,
	parameter PHASE = 0
 ) (
	input	wire							src_1x_clk /* synthesis syn_isclock = 1 */,
	input	wire	[SRC_WIDTH-1:0]			src_1x_data,
	
	input	wire							dst_2x_clk /* synthesis syn_isclock = 1 */,
	output	reg		[DST_WIDTH-1:0]			dst_2x_data
);
	reg [SRC_WIDTH-1:0] src_1x_data_q;

	always_ff @(posedge src_1x_clk) begin
		src_1x_data_q <= src_1x_data;
	end

	always_ff @(posedge dst_2x_clk) begin
		if (src_1x_clk ^ PHASE) begin
			dst_2x_data <= src_1x_data_q[SRC_WIDTH - 1:DST_WIDTH];
		end else begin
			dst_2x_data <= src_1x_data_q[DST_WIDTH - 1:0];
		end
	end
endmodule

module ddr_sync_dc_2x_clk_to_1x_clk #(
	parameter SRC_WIDTH = 16,
	parameter DST_WIDTH = SRC_WIDTH * 2,
	parameter PHASE = 0
 ) (
	input	wire							src_2x_clk /* synthesis syn_isclock = 1 */,
	input	wire	[SRC_WIDTH-1:0]			src_2x_data,
	
	input	wire							dst_1x_clk /* synthesis syn_isclock = 1 */,
	output	reg		[DST_WIDTH-1:0]			dst_1x_data
);
	reg [DST_WIDTH-1:0] dst_1x_data_staging;

	always_ff @(posedge dst_1x_clk) begin
		dst_1x_data <= dst_1x_data_staging;
	end

	always_ff @(posedge src_2x_clk) begin
		if (dst_1x_clk ^ PHASE) begin
			dst_1x_data_staging[DST_WIDTH-1:SRC_WIDTH] <= src_2x_data;
		end else begin
			dst_1x_data_staging[SRC_WIDTH-1:0] <= src_2x_data;
		end
	end
endmodule