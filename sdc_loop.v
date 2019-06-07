`timescale 1ns / 1ps
`include "../f_card_para/f_card_para.v"
////////////////////////////////////////////////////////////////////////////////
// Company		: WNL
// Engineer		: Diego L
// Create Date	: 2019.1.6
// Design Name	: Sdcard Data
// Module Name	: sdcard_data
// Project Name	: Fgpa_led
// Target Device: Cyclone EP1C3T144C8 
// Tool versions: Quartus II 9.1
// Description	: 该工程用于sdcard读写回环测试
//					
// Revision		: V1.0
// Additional Comments	:  
// 
////////////////////////////////////////////////////////////////////////////////
module sdc_loop(
                clk,rst_n,
                spi_miso,spi_mosi,spi_clk,spi_cs_n,
                led_run
`ifdef SIM				
				,ffsdc_din,ffsdc_wrreq,ffsdc_rdreq,ffsdc_dout,ffsdc_used	,
                spi_tx_db,spi_rx_db	
`endif				
);
input clk;		//FPAG输入时钟信号50MHz
input rst_n;	//FPGA输入复位信号

input spi_miso;		//SPI主机输入从机输出数据信号
output spi_mosi;	//SPI主机输出从机输入数据信号
output spi_clk;		//SPI时钟信号，由主机产生
output spi_cs_n;	//SPI从设备使能信号，由主设备控制
output led_run;

`ifndef SIM
wire[7:0] ffsdc_din;	//SD卡FIFO写入数据
wire ffsdc_wrreq;		//SD卡FIFO写请求信号，高有效
wire ffsdc_rdreq;		//SD卡FIFO读请求信号，高有效
wire[7:0] ffsdc_dout;	//SD卡FIFO读出数据
wire[8:0] ffsdc_used;	    //SD卡数据写入缓存FIFO已用存储空间数量
`else
output[7:0] ffsdc_din;	//SD卡FIFO写入数据
output ffsdc_wrreq;		//SD卡FIFO写请求信号，高有效
output ffsdc_rdreq;		//SD卡FIFO读请求信号，高有效
output[7:0] ffsdc_dout;	//SD卡FIFO读出数据
output[8:0] ffsdc_used;
output[7:0] spi_tx_db;
input[7:0] spi_rx_db;
`endif
wire ffsdc_clr;

`ifdef FIFO_CTRL
reg sdc_rd_en;		//FIFO不满，sd卡读使能信号
reg sdc_wr_en;    
//assign sdc_rd_en = (ffsdc_used < 9'd504);
//assign sdc_wr_en = (ffsdc_used > 9'd16);	//检测FIFO大于8位数据，就启动SD写入

reg[3:0] cs_sdwr;	
reg[3:0] ns_sdwr;

parameter SDWR_IDLE  = 4'd0,
          SDWR_RD    = 4'd1,
		  SDWR_WR    = 4'd2;
		  
always @(posedge clk or negedge rst_n)
	if(!rst_n) cs_sdwr <= SDWR_IDLE;
	else cs_sdwr <= ns_sdwr;	

always @(cs_sdwr or ffsdc_used)	
    case(cs_sdwr)
	    SDWR_IDLE: begin
            if(ffsdc_used == 9'd0) ns_sdwr = SDWR_RD;		
            else ns_sdwr = SDWR_IDLE;			
		end
		SDWR_RD: begin
		    if(ffsdc_used == 9'd511) ns_sdwr = SDWR_WR;
			else ns_sdwr = SDWR_RD;
		end
		SDWR_WR: begin
		    if(ffsdc_used == 9'd0) ns_sdwr = SDWR_RD;
			else ns_sdwr = SDWR_WR;
		end
		default: cs_sdwr = SDWR_IDLE;
	endcase

always @(posedge clk or negedge rst_n)
    if(!rst_n) begin
			sdc_rd_en <= 1'b0;
			sdc_wr_en <= 1'b0;
			ffsdc_rdreq <= 1'b0;
	    end
	else
	    case(ns_sdwr)
		    SDWR_RD: begin
			    sdc_rd_en <= 1'b1;
				sdc_wr_en <= 1'b0;
				ffsdc_rdreq <= 1'b1;
			end
	        SDWR_WR: begin
                sdc_rd_en <= 1'b0;
				sdc_wr_en <= 1'b1;			
				ffsdc_rdreq <= 1'b0;
			end
			default: begin
			    sdc_rd_en <= 1'b0;
				sdc_wr_en <= 1'b0;
				ffsdc_rdreq <= 1'b0;
			end
		endcase
`endif
		
//例化SD卡数据读写缓存FIFO模块
sdc_fifo			sdc_fifo_inst(
					.aclr(ffsdc_clr),
					.data(ffsdc_din),
					.rdclk(clk),
					.rdreq(ffsdc_rdreq),
					.wrclk(clk),
					.wrreq(ffsdc_wrreq),//sd卡写准备好,sd内部，一有8位数据即置为1
					.q(ffsdc_dout),
					.wrusedw(ffsdc_used)					
					);
					
//sd控制模块
sdcard_ctrl		uut_sdcartctrl(
`ifdef SIM	
                    .spi_tx_db(spi_tx_db),
					.spi_rx_db(spi_rx_db),
`endif						
					.clk(clk),
					.rst_n(rst_n),
					.spi_miso(spi_miso),
					.spi_mosi(spi_mosi),
					.spi_clk(spi_clk),
					.spi_cs_n(spi_cs_n),
					.sd_dout(ffsdc_din),
					.sd_fifowr(ffsdc_wrreq),
					.sd_fiford(ffsdc_rdreq),
					//.sd_rd_en(sdc_rd_en),//add
					//.sd_wr_en(sdc_wr_en),
					.sdwrad_clr(ffsdc_clr),
					.ff_din(ffsdc_dout),
					.sd_test(led_run)		
				);
				
endmodule
