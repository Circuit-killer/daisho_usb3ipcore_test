module ecp5_pipe (
	//output	wire			phy_clk_250mhz,
	//output	wire			phy_clk_125mhz,

	output	wire	[15:0]	phy_pipe_rx_data_2x, // internal PHY
	output	wire	[1:0]	phy_pipe_rx_datak_2x, // internal PHY
	output	wire			phy_pipe_rx_valid_2x, // internal PHY
	input	wire	[15:0]	phy_pipe_tx_data_2x, // internal PHY
	input	wire	[1:0]	phy_pipe_tx_datak_2x, // internal PHY


	input	wire			phy_reset_n,
	input	wire			phy_out_enable,
	input	wire			phy_phy_reset_n,
	input	wire			phy_tx_detrx_lpbk,
	input	wire			phy_tx_elecidle, // NOTE: this is pipelined with the data by the ECP5 SERDES/PCS
	output	wire			phy_rx_elecidle,
	output	wire	[2:0]	phy_rx_status_2x,
	input	wire	[1:0]	phy_power_down,
	output	wire			phy_phy_status_2x,
	output	wire			phy_pwrpresent,

	input	wire			phy_tx_oneszeros,
	input	wire	[1:0]	phy_tx_deemph,
	input	wire	[2:0]	phy_tx_margin,
	input	wire			phy_tx_swing,
	input	wire			phy_rx_polarity,
	input	wire			phy_rx_termination,
	input	wire			phy_rate,
	input	wire			phy_elas_buf_mode
);
	// PIPE 3.0 Spec: https://www.intel.in/content/dam/doc/white-paper/usb3-phy-interface-pci-express-paper.pdf
	// USB 3.0 Spec: https://www.usb3.com/whitepapers/USB%203%200%20(11132008)-final.pdf
	// ECP5 SERDES/PCS Usage Guide: https://www.latticesemi.com/-/media/LatticeSemi/Documents/ApplicationNotes/EH/TN1261.ashx?document_id=50463
	
	

	wire clk_250mhz;
	wire clk_125mhz;
	assign phy_clk_250mhz = clk_250mhz;
	assign phy_clk_125mhz = clk_125mhz;
	
	wire txd_ldr;
	wire txd_ldr_en;
	wire rxd_ldr;
	
	wire pcie_done_s;
	wire pcie_con_s;
	

	///////////////////////////////////////////////////////////////////////////
	// Generate LFPS signaling
	///////////////////////////////////////////////////////////////////////////
	
	// PIPE 3.0, section 6.10
	wire lfps_tx_en = (phy_power_down != 2'b00) && (phy_tx_elecidle == 1'b0);
	
	// USB 3.0, section 6.9.1
	reg [2:0] lfps_tx_period_counter;
	
	always_ff @(posedge clk_250mhz) begin
		if (lfps_tx_en) begin
			lfps_tx_period_counter <= lfps_tx_period_counter + 1;
		end 
	end
	
	// generate LFPS signal with 32ns tPeriod
	wire lfps_tx_signal = lfps_tx_period_counter[2];
	
	// bypass SERDES and transmit LFPS when needed
	// ECP5 SERDES/PCS Usage Guide, Figure 19
	assign txd_ldr = lfps_tx_signal;
	assign txd_ldr_en = lfps_tx_en;
	
	

	///////////////////////////////////////////////////////////////////////////
	// Detect LFPS signaling
	///////////////////////////////////////////////////////////////////////////
		
	// double sync rxd_ldr and detect rising edge
	// ECP5 SERDES/PCS Usage Guide, Figure 19
	reg rxd_ldr_q0, rxd_ldr_q1, rxd_ldr_q2;
	always_ff @(posedge clk_250mhz) begin
		{rxd_ldr_q0, rxd_ldr_q1, rxd_ldr_q2} <= {rxd_ldr, rxd_ldr_q0, rxd_ldr_q1};
	end
	
	wire rxd_ldr_rising_edge = (rxd_ldr_q2 == 1'b0) && (rxd_ldr_q1 == 1'b1);
	
	// need to be able to detect LFPS with 20 - 100 ns tPeriod
	// USB 3.0, section 6.9.1
	reg [4:0] lfps_rx_period_counter;
	wire lfps_rx_period_timeout = lfps_rx_period_counter > 25;
	reg lfps_rx_det;
	
	always_ff @(posedge clk_250mhz) begin
		// count the current LFPS RX tPeriod until we see the end of a period or
		// the max tPeriod passes
		if (rxd_ldr_rising_edge || lfps_rx_period_timeout) begin
			lfps_rx_period_counter <= 0;
		
		end else begin
			lfps_rx_period_counter <= lfps_rx_period_counter + 1;
		end
		
		// if we detect a tPeriod cycle then set the detect bit, if we timeout
		// then reset the detect bit.  for all other cases, keep the same value.
		if (rxd_ldr_rising_edge) begin
			lfps_rx_det <= 1;
		end else if (lfps_rx_period_timeout) begin
			lfps_rx_det <= 0;
		end
	end
	
	
	
	///////////////////////////////////////////////////////////////////////////
	// RX Detect
	///////////////////////////////////////////////////////////////////////////
	/*
	The PIPE 3.0 spec has a simple process for performing RX detect operations.
	It requires that the PHY be in P2 or P3 and phy_tx_detrx_lpbk is asserted
	until the result is sent back from the PHY. See the "PIPE 3.0 Specification"
	section 6.8 for details.
	
	The ECP5 SERDES/PCS requires a little bit more sequencing to make this 
	happen.  The rx_det_state state machine is used to perform this sequencing.
	See the "ECP5 and ECP5-5G SERDES/PCS Usage Guide" pages 31 and 32 for
	details.
	*/
	
	// detect request to initiate rx detect operation
	// PIPE 3.0, section 6.8
	wire perform_rx_detect = phy_tx_detrx_lpbk && phy_power_down[1];
	
	// state machine to sequence the rx detect procedure on the ECP5 SERDES/PCS
	// ECP5 SERDES/PCS Usage Guide, Table 12, Figure 17
	reg [5:0] tdets_timer;
	reg	[5:0] rx_det_state;
	parameter [5:0]	
		RX_DET_IDLE = 0,
		RX_DET_TDET = 1,
		RX_DET_PCIE_CT = 2,
		RX_DET_WAIT = 3,
		RX_DET_DONE = 4;
	
	reg tdets_timer;
	reg pcie_ct;
	reg return_rx_detect_result;
	reg far_end_receiver_detected;
	
	always_ff @(posedge clk_250mhz) begin
		tdets_timer <= 0;
		pcie_ct <= 0;
		return_rx_detect_result <= 0;
		far_end_receiver_detected <= 0;
				
		case (rx_det_state)
			// wait for rx_detect operation to be requested
			RX_DET_IDLE : begin
				if (perform_rx_detect) begin
					rx_det_state <= RX_DET_TDET;
				end
			end
			
			// wait at least 120ns for TX driver to be ready
			RX_DET_TDET : begin
				tdets_timer <= tdets_timer + 1;
				
				if (tdets_timer[5]) begin
					rx_det_state <= RX_DET_PCIE_CT;
				end
			end
			
			// tell the SERDES/PCS to initiate rx detect operation
			RX_DET_PCIE_CT : begin
				pcie_ct <= 1;
				
				if (pcie_done_s == 1'b0) begin
					rx_det_state <= RX_DET_WAIT;
				end
			end
			
			// wait until rx detect operation completes
			RX_DET_WAIT : begin
				if (pcie_done_s == 1'b1) begin
					rx_det_state <= RX_DET_DONE;
				end
			end
			
			// return the rx detect result to the MAC
			RX_DET_DONE : begin
				return_rx_detect_result <= 1;
				far_end_receiver_detected <= pcie_con_s;
				rx_det_state <= RX_DET_IDLE;
			end
		endcase
	end
	
	always_ff @(posedge clk_250mhz) begin
		if (return_rx_detect_result) begin
			if (far_end_receiver_detected) begin
				phy_phy_status_2x <= 1'b1;
				phy_rx_status_2x <= 3'b011;
			end else begin
				phy_phy_status_2x <= 1'b1;
				phy_rx_status_2x <= 3'b000;
			end
		end else begin
			phy_phy_status_2x <= 1'b0;
			phy_rx_status_2x <= 3'b000;
		end
	end
endmodule