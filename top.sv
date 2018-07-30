module top (
	input 	wire			clk_p_200mhz,
	input 	wire			clk_n_200mhz,
	
	input	wire			ext_clk,
	input	wire			reset_n,

	input	wire	[8:0]	buf_in_addr,
	input	wire	[31:0]	buf_in_data,
	input	wire			buf_in_wren,
	output	wire			buf_in_request,
	output	wire			buf_in_ready,
	input	wire			buf_in_commit,
	input	wire	[10:0]	buf_in_commit_len,
	output	wire			buf_in_commit_ack,

	input	wire	[8:0]	buf_out_addr,
	output	wire	[31:0]	buf_out_q,
	output	wire	[10:0]	buf_out_len,
	output	wire			buf_out_hasdata,
	input	wire			buf_out_arm,
	output	wire			buf_out_arm_ack,

	output	wire			vend_req_act,
	output	wire	[7:0]	vend_req_request,
	output	wire	[15:0]	vend_req_val,
	output  wire    [5:0]	dbg_pipe_state,
	output  wire    [4:0]	dbg_ltssm_state
);

	wire			clk_200mhz;
	wire			clk_250mhz;
	
	wire			phy_pipe_half_clk;        // 125MHz:  1/2 PCLK
	wire			phy_pipe_half_clk_phase;  // 125MHz:  1/2 PCLK, phase shift 90
	wire			phy_pipe_quarter_clk;     // 62.5MHz: 1/4 PCLK
	
	wire	[15:0]	phy_pipe_rx_data_2x; 
	wire	[1:0]	phy_pipe_rx_datak_2x; 
	wire			phy_pipe_rx_valid_2x; 
	wire	[15:0]	phy_pipe_tx_data_2x; 
	wire	[1:0]	phy_pipe_tx_datak_2x; 

	wire			phy_reset_n;
	wire			phy_out_enable;
	wire			phy_phy_reset_n;
	wire			phy_tx_detrx_lpbk;
	wire			phy_tx_elecidle;
	wire			phy_rx_elecidle;
	wire	[2:0]	phy_rx_status_2x;
	wire	[1:0]	phy_power_down;
	wire			phy_phy_status_2x;
	wire			phy_pwrpresent;

	wire			phy_tx_oneszeros;
	wire	[1:0]	phy_tx_deemph;
	wire	[2:0]	phy_tx_margin;
	wire			phy_tx_swing;
	wire			phy_rx_polarity;
	wire			phy_rx_termination;
	wire			phy_rate;
	wire			phy_elas_buf_mode;
	
	wire	[31:0]	phy_pipe_tx_data;
	wire	[3:0]	phy_pipe_tx_datak;
	
	wire	[31:0]	phy_pipe_rx_data;
	wire	[3:0]	phy_pipe_rx_datak;
	wire	[1:0]	phy_pipe_rx_valid;
	wire	[1:0]	phy_phy_status;
	wire	[5:0]	phy_rx_status;
	
	// need to instantiate this for external PCIe/USB3 reference clock
	/*
	extref extref_inst (
		.refclkp(clk_p_200mhz),
		.refclkn(clk_n_200mhz),
		.refclk0(clk_200mhz)
	);
	*/
	assign clk_200mhz = clk_p_200mhz;

	// FIXME: this may need to be replaced/augmented with SERDES TX PLL
	usb3_core_pll usb3_core_pll_inst (
		.CLKI(clk_200mhz), 
		.CLKOP(clk_250mhz), 
		.CLKOS(phy_pipe_half_clk),			// 125MHz:  1/2 PCLK
		.CLKOS2(phy_pipe_half_clk_phase),	// 125MHz:  1/2 PCLK, phase shift 90
		.CLKOS3(phy_pipe_quarter_clk)		// 62.5MHz: 1/4 PCLK
	);


	usb3_top usb3_inst (.*);
	
	///////////////////////////////////////////////////////////////////////////
	// Convert 32-bit 125MHz PIPE TX to 16-bit 250MHz PIPE TX
	ddr_sync_dc_1x_clk_to_2x_clk #(
		.SRC_WIDTH(32),
		.PHASE(0)
	 ) phy_pipe_tx_data_32_to_16 (
		.src_1x_clk(phy_pipe_half_clk),
		.src_1x_data(phy_pipe_tx_data),
		.dst_2x_clk(clk_250mhz),
		.dst_2x_data(phy_pipe_tx_data_2x)
	);
	
	ddr_sync_dc_1x_clk_to_2x_clk #(
		.SRC_WIDTH(4),
		.PHASE(0)
	 ) phy_pipe_tx_datak_4_to_2 (
		.src_1x_clk(phy_pipe_half_clk),
		.src_1x_data(phy_pipe_tx_datak),
		.dst_2x_clk(clk_250mhz),
		.dst_2x_data(phy_pipe_tx_datak_2x)
	);
	
	///////////////////////////////////////////////////////////////////////////
	// Convert 16-bit 250MHz PIPE RX to 32-bit 125MHz PIPE RX
	ddr_sync_dc_2x_clk_to_1x_clk #(
		.SRC_WIDTH(16),
		.PHASE(0)
	 ) phy_pipe_rx_data_16_to_32 (
		.src_2x_clk(clk_250mhz),
		.src_2x_data(phy_pipe_rx_data_2x),
		.dst_1x_clk(phy_pipe_half_clk),
		.dst_1x_data(phy_pipe_rx_data)
	);
	
	ddr_sync_dc_2x_clk_to_1x_clk #(
		.SRC_WIDTH(2),
		.PHASE(0)
	 ) phy_pipe_rx_datak_2_to_4 (
		.src_2x_clk(clk_250mhz),
		.src_2x_data(phy_pipe_rx_datak_2x),
		.dst_1x_clk(phy_pipe_half_clk),
		.dst_1x_data(phy_pipe_rx_datak)
	);

	ddr_sync_dc_2x_clk_to_1x_clk #(
		.SRC_WIDTH(1),
		.PHASE(0)
	 ) phy_pipe_rx_valid_1_to_2 (
		.src_2x_clk(clk_250mhz),
		.src_2x_data(phy_pipe_rx_valid_2x),
		.dst_1x_clk(phy_pipe_half_clk),
		.dst_1x_data(phy_pipe_rx_valid)
	);

	ddr_sync_dc_2x_clk_to_1x_clk #(
		.SRC_WIDTH(1),
		.PHASE(0)
	 ) phy_phy_status_1_to_2 (
		.src_2x_clk(clk_250mhz),
		.src_2x_data(phy_phy_status_2x),
		.dst_1x_clk(phy_pipe_half_clk),
		.dst_1x_data(phy_phy_status)
	);

	ddr_sync_dc_2x_clk_to_1x_clk #(
		.SRC_WIDTH(3),
		.PHASE(0)
	 ) phy_rx_status_3_to_6 (
		.src_2x_clk(clk_250mhz),
		.src_2x_data(phy_rx_status_2x),
		.dst_1x_clk(phy_pipe_half_clk),
		.dst_1x_data(phy_rx_status)
	);
	
	ecp5_pipe ecp5_pipe_inst (.*);
endmodule;