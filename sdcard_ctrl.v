`timescale 1ns / 1ps
`include "../f_card_para/f_card_para.v"
////////////////////////////////////////////////////////////////////////////////
// Company		: WNL
// Engineer		: Diego L
// Create Date	: 2016.01.09
// Design Name	: Sdcard Ctrl
// Module Name	: sdcard_ctrl
// Project Name	: Fgpa_led
// Target Device: Cyclone EP1C3T144C8 
// Tool versions: Quartus II 8.1
// Description	: �ù�������sdcard����
//					
// Revision		: V1.0
// Additional Comments	:  
// 
////////////////////////////////////////////////////////////////////////////////
module sdcard_ctrl(
`ifdef SIM	
            spi_tx_db,spi_rx_db,
`endif				
			clk,rst_n,
			spi_miso,spi_mosi,spi_clk,spi_cs_n,
			sd_dout,sd_fifowr,sd_fiford,/*sd_rd_en,sd_wr_en,*/sdwrad_clr,
            ff_din,sd_test
			);

input clk;		//FPAG����ʱ���ź�50MHz
input rst_n;	//FPGA���븴λ�ź�

input spi_miso;		//SPI��������ӻ���������ź�
output spi_mosi;	//SPI��������ӻ����������ź�
output spi_clk;		//SPIʱ���źţ�����������
output spi_cs_n;	//SPI���豸ʹ���źţ������豸����

output[7:0] sd_dout;	//��SD�����Ĵ�����FIFO����
output sd_fifowr;		//sd��������д��FIFOʹ���źţ�����Ч
output sd_fiford;		//sd�������ݶ�ȡFIFOʹ���źţ�����Ч
//input sd_rd_en;
//input sd_wr_en;
output sdwrad_clr;		//SDRAMд��������ź����㸴λ�źţ�����Ч

input[7:0] ff_din;
output sd_test;
//output[3:0] led;	//����ʹ��

//----------------------------------------------------------------
wire spi_tx_en;		//SPI���ݷ���ʹ���źţ�����Ч
wire spi_tx_rdy;		//SPI���ݷ�����ɱ�־λ������Ч
wire spi_rx_en;		//SPI���ݽ���ʹ���źţ�����Ч
wire spi_rx_rdy;		//SPI���ݽ�����ɱ�־λ������Ч
`ifndef SIM
wire[7:0] spi_tx_db;	//SPI���ݷ��ͼĴ���
wire[7:0] spi_rx_db;	//SPI���ݽ��ռĴ���
`else
output[7:0] spi_tx_db;	//SPI���ݷ��ͼĴ���
input[7:0] spi_rx_db;	//SPI���ݽ��ռĴ���
`endif

//----------------------------------------------------------------
//����SPI�������ģ��
spi_ctrl		uut_spictrl(
`ifndef SIM
                    .spi_rx_db(spi_rx_db),
`endif					
					.clk(clk),
					.rst_n(rst_n),
					.spi_miso(spi_miso),
					.spi_mosi(spi_mosi),
					.spi_clk(spi_clk),
					.spi_tx_en(spi_tx_en),
					.spi_tx_rdy(spi_tx_rdy),
					.spi_rx_en(spi_rx_en),
					.spi_rx_rdy(spi_rx_rdy),
					.spi_tx_db(spi_tx_db)
				);

//����SD�������ģ��
sd_ctrl			uut_sdctrl(
					.clk(clk),
					.rst_n(rst_n),
					.spi_cs_n(spi_cs_n),
					.spi_tx_en(spi_tx_en),
					.spi_tx_rdy(spi_tx_rdy),
					.spi_rx_en(spi_rx_en),
					.spi_rx_rdy(spi_rx_rdy),
					.spi_tx_db(spi_tx_db),
					.spi_rx_db(spi_rx_db),
					.sd_dout(sd_dout),
					.sd_fifowr(sd_fifowr),
					.sd_fiford(sd_fiford),
					//.sd_rd_en(sd_rd_en),
					//.sd_wr_en(sd_wr_en),
					.sdwrad_clr(sdwrad_clr),
					.ff_din(ff_din),
					.sd_test(sd_test)
				);

endmodule