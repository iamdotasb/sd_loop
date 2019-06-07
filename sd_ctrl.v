`timescale 1ns / 1ps
`include "../f_card_para/f_card_para.v"
////////////////////////////////////////////////////////////////////////////////
// Company		: WNL
// Engineer		: Diego L
// Create Date	: 2016.01.09
// Design Name	: Sd Ctrl
// Module Name	: sd_ctrl
// Project Name	: Fgpa_led
// Target Device: Cyclone EP1C3T144C8 
// Tool versions: Quartus II 8.1
// Description	: �ù�������sdcard״̬��
//					
// Revision		: V1.0
// Additional Comments	:  
// 
////////////////////////////////////////////////////////////////////////////////
module sd_ctrl(
			clk,rst_n,
			spi_cs_n,
			spi_tx_en,spi_tx_rdy,spi_rx_en,spi_rx_rdy,
			spi_tx_db,spi_rx_db,
			sd_dout,sd_fifowr,sd_fiford,/*sd_rd_en,sd_wr_en,*/sdwrad_clr,
			ff_din,sd_test
		);

input clk;		//FPAG����ʱ���ź�50MHz
input rst_n;	//FPGA���븴λ�ź�

output spi_cs_n;	//SPI���豸ʹ���źţ������豸����

output spi_tx_en;		//SPI���ݷ���ʹ���źţ�����Ч
input spi_tx_rdy;		//SPI���ݷ�����ɱ�־λ������Ч
output spi_rx_en;		//SPI���ݽ���ʹ���źţ�����Ч
input spi_rx_rdy;		//SPI���ݽ�����ɱ�־λ������Ч
output[7:0] spi_tx_db;	//SPI���ݷ��ͼĴ���
input[7:0] spi_rx_db;	//SPI���ݽ��ռĴ���

output[7:0] sd_dout;	//��SD�����Ĵ�����FIFO����
output sd_fifowr;		//sd��������д��FIFOʹ���źţ�����Ч
output sd_fiford;		//sd�������ݶ�ȡFIFOʹ���źţ�����Ч
//input sd_rd_en;
//input sd_wr_en;
output sdwrad_clr;		//SDRAMд��������ź����㸴λ�źţ�����Ч

input[7:0] ff_din;
output reg sd_test;

/*��������*/
//���ڲ�ͬ��SD���ļ�ϵͳ�п���ΪFAT16/32���洢����СҲ�п��ܲ�ͬ���ճ��������ݵ�ַ�Ĳ�ͬ
//�ù���û�ж��ļ�ϵͳ��������ƣ�������Ҫ�����winhex�¶�����ʹ�õ�SD�������²������������
//Ҫ��SD��ʹ��ǰ��ø�ʽ����Ȼ�����10��800*600��8λͼƬ
parameter	P0_ADDR		= 32'h4040,//32'hEC_8000,//14718880//1C12F4000,//32'h0004_6600,		//��һ��ͼƬP0����������ַ
			P_MEM		= 32'h7_8000,//32'h0007_5800,		//һ��800*600��8λͼƬ��ʽ��SD������ռ�õĵ�ַ�ռ�
			LAST_ADDR	= 32'h41_0000,//1C17A4000;//32'h004d_d600;		//10��ͼƬ�����һ����ַ
			P0_WR_ADDR	    = 32'h4080,//32'hF4_0000,
			LAST_WR_ADDR	= 32'hFB_8000;
//assign sdwrad_clr = done_5s;
//------------------------------------------------------
//SD�ϵ��ʼ��
//	1. �ʵ���ʱ�ȴ�SD����
//	2. ����74+��spi_clk���ұ���spi_cs_n=1,spi_mosi=1 
//	3. ����CMD0����ȴ���ӦR1=8'h01: ������λ��IDLE״̬
//	4. ����CMD1����ȴ���ӦR1=8'h00: ����ĳ�ʼ������
//	5. ����CMD16����ȴ���ӦR1=8'h00: ����һ�ζ�дBLOCK�ĳ���Ϊ512���ֽ�
//SD���ݶ�ȡ����
//	1. ��������CMD17
//	2. ���ն�������ʼ����0xfe
//	3. ��ȡ512Byte�����Լ�2Byte��CRC
//------------------------------------------------------
//�ϵ���ʱ�ȴ�����
reg[10:0] delay_cnt;	//10bit��ʱ��������������1000��40ns*1000=40us	

always @(posedge clk or negedge rst_n)
	if(!rst_n) delay_cnt <= 11'd0;
	else if(delay_cnt < 11'd2000) delay_cnt <= delay_cnt+1'b1;
	
wire delay_done = (delay_cnt == 11'd2000);	//40us��ʱʱ����ɱ�־λ������Ч	

//------------------------------------------------------
//sd״̬������
reg[3:0] sdinit_cstate;		//sd��ʼ����ǰ״̬�Ĵ���
reg[3:0] sdinit_nstate;		//sd��ʼ����һ״̬�Ĵ���

parameter	SDINIT_RST	= 4'd0,		//��λ�ȴ�״̬
			SDINIT_CLK	= 4'd1,		//74+ʱ�Ӳ���״̬
			SDINIT_CMD0 = 4'd2,		//����CMD0����״̬
			SDINIT_CMD55 = 4'd3,	//����CMD55����״̬
			SDINIT_ACMD41 = 4'd4,	//����ACMD41����״̬
			SDINIT_CMD1 = 4'd5,		//����CMD1����״̬
			SDINIT_CMD16 = 4'd6,	//����CMD16����״̬
			SD_IDLE 	= 4'd7,		//sd��ʼ�������������״̬
			SD_RD_PT	= 4'd8,		//sd��ȡPartition Table
			SD_RD_BPB	= 4'd9,		//sd��ȡ������״̬
			SD_DELAY	= 4'd10,	//sd���������ʱ�ȴ�״̬
			SDINIT_CMD8 = 4'd11,	//sd�����������һЩ�������
			SDINIT_CMD58= 4'd12,	//sd״̬�����SD������״̬
			SDINIT_CMD58_OK = 4'd13,
			SD_WR_PT	= 4'd14,		//sd��ȡPartition Table
			SD_WR_BPB	= 4'd15;		//sd��ȡ������״̬

//״̬ת��
always @(posedge clk or negedge rst_n)
	if(!rst_n) 
`ifndef SIM	
	    sdinit_cstate <= SDINIT_RST;
`else
        sdinit_cstate <= SD_IDLE;
`endif
	else sdinit_cstate <= sdinit_nstate;

//״̬����
wire cmd_rdy;
reg cmd_ok;
reg[31:0] arg_r;	//��ʼ������ַ�Ĵ���
reg[31:0] arg_wr_r;	//��ʼ������ַ�Ĵ���(д��)
wire done_5s;
reg[4:0] cmd_cstate;	//�������ǰ״̬�Ĵ���
reg[4:0] cmd_nstate;	//����������һ״̬�Ĵ���

parameter	CMD_IDLE	= 5'd0,		//������ͣ��ȴ�״̬
			CMD_NCLK	= 5'd1,		//�ϵ��ʼ��ʱ��Ҫ����74+CLK״̬
			CMD_CLKS	= 5'd2,		//����8��CLK״̬
			CMD_STAR	= 5'd3,		//������ʼ�ֽ�״̬
			CMD_ARG1	= 5'd4,		//����arg[31:24]״̬
			CMD_ARG2	= 5'd5,		//����arg[23:16]״̬
			CMD_ARG3	= 5'd6,		//����arg[15:8]״̬
			CMD_ARG4	= 5'd7,		//����arg[7:0]״̬
			CMD_END		= 5'd8,		//���ͽ����ֽ�״̬
			CMD_RES		= 5'd9,		//������Ӧ�ֽ�
			CMD_CLKE	= 5'd10,	//����8��CLK״̬
			CMD_RD		= 5'd11,	//��512Byte״̬
			CMD_DELAY	= 5'd12,	//��д���������ʱ�ȴ�״̬
			CMD_CSH 	= 5'd13,	//T0ʱ��CS���ߣ�����8������clk
			CMD_WRCLK 	= 5'd14,    //дǰ����80��CLK״̬
			CMD_WR      = 5'd15,    //д512Byte״̬
			CMD_WRDONE  = 5'd16;    //��ȡд����״̬

//------------------------------------------------------
//SD����CMD���Ϳ���
//	1. ����8��ʱ������
//  2. SD��ƬѡCS����,��Ƭѡ��Ч
//  3. ��������6���ֽ�����
//	4. ����1���ֽ���Ӧ����
//	5. SD��ƬѡCS����,���ر�SD��
/*		�����ܹ�6���ֽ������ʽ:
        0 -- start bit 
        1 -- host
        bit5-0 --  command
        bit31-0 -- argument
        bit6-0 -- CRC7
        1 -- end bit   
*/
//------------------------------------------------------
//����sd����״̬������
reg[5:0] cmd;	//��������Ĵ���
reg[31:0] arg;	//���Ͳ����Ĵ���
reg[7:0] crc;	//����CRCУ����

reg spi_cs_nr;	//SPI���豸ʹ���źţ������豸����
reg spi_tx_enr;	//SPI���ݷ���ʹ���źţ�����Ч
reg spi_rx_enr;	//SPI���ݽ���ʹ���źţ�����Ч
reg[7:0] spi_tx_dbr;	//SPI���ݷ��ͼĴ���
reg[7:0] spi_rx_dbr;	//SPI���ݽ��ռĴ���
reg[6:0] nclk_cnt;		//74+CLK�������ڼ�����
reg[9:0] wrclk_cnt;		//д��80CLK�������ڼ�����
reg[7:0] wrdone_cnt;    //�ظ���ȡд����ɼ�����
reg[7:0] wait_cnt8;		//�����������ȴ�������
reg[9:0] cnt512;	//��ȡ512B������
reg[11:0] retry_rep;		//�ظ���ȡrespone������
reg[7:0] retry_cmd;		//�ظ���ǰ���������
			
always @(sdinit_cstate or retry_rep or delay_done or nclk_cnt 
			or cmd_rdy or spi_rx_dbr or arg or arg_r or arg_wr_r or done_5s 
			or cmd_ok) begin
	case(sdinit_cstate)
		SDINIT_RST: begin
			if(delay_done) sdinit_nstate <= SDINIT_CLK;	//�ϵ��40us��ʱ��ɣ�����74+CLK״̬
			else sdinit_nstate <= SDINIT_RST;	//�ȴ��ϵ��40us��ʱ���
		end
		SDINIT_CLK:	begin
			if(cmd_rdy) sdinit_nstate <= SDINIT_CMD0;	//74+CLK���
			else sdinit_nstate <= SDINIT_CLK;
		end
		SDINIT_CMD0: begin
			if(cmd_rdy && (spi_rx_dbr == 8'h01)) sdinit_nstate <= SDINIT_CMD8;//sdinit_nstate <= SDINIT_CMD55;
			else sdinit_nstate <= SDINIT_CMD0;
		end
		SDINIT_CMD8: begin		//sdhcv2.0����		
			if(cmd_rdy && (cmd_ok == 1'b1)) sdinit_nstate <= SDINIT_CMD58;
			else sdinit_nstate <= SDINIT_CMD8;
		end
		SDINIT_CMD58: begin		//sdhcv2.0����		
			if(cmd_rdy && (cmd_ok == 8'h01)) sdinit_nstate <= SDINIT_CMD55;
			else sdinit_nstate <= SDINIT_CMD58;
		end
		SDINIT_CMD55: begin
			if(cmd_rdy && (spi_rx_dbr == 8'h01)) sdinit_nstate <= SDINIT_ACMD41;
			else sdinit_nstate <= SDINIT_CMD55;
		end
		SDINIT_ACMD41: begin
			if(retry_rep == 12'hfff) sdinit_nstate <= SDINIT_CMD55;	///////////��Ӧ��ʱ������IDLE���·������� 
			else if(cmd_rdy && spi_rx_dbr != 8'h00) sdinit_nstate <= SDINIT_CMD55; 
			else if(cmd_rdy && spi_rx_dbr == 8'h00) sdinit_nstate <= SDINIT_CMD58_OK;
			else sdinit_nstate <= SDINIT_ACMD41;	
		end
		SDINIT_CMD58_OK: begin		//sdhcv2.0����		
			if(cmd_rdy && (cmd_ok == 8'h01)) sdinit_nstate <= SD_IDLE;
			else sdinit_nstate <= SDINIT_CMD58_OK;
		end
	/*	SDINIT_CMD1: begin
			if(cmd_rdy) sdinit_nstate <= SDINIT_CMD16;
			else sdinit_nstate <= SDINIT_CMD1;
		end*/
		SDINIT_CMD16: begin
			if(cmd_rdy && (spi_rx_dbr == 8'h00)) sdinit_nstate <= SD_IDLE;
			else sdinit_nstate <= SDINIT_CMD16;
		end
		SD_IDLE: sdinit_nstate <= SD_RD_PT;
`ifdef JUST_RD			
		SD_RD_PT: begin
			if(cmd_rdy) sdinit_nstate <= SD_RD_BPB;
			else sdinit_nstate <= SD_RD_PT;
		end	
		SD_RD_BPB: begin
			if(cmd_rdy && arg == arg_r+P_MEM-32'h0000_0200) sdinit_nstate <= SD_DELAY;
			else sdinit_nstate <= SD_RD_BPB;
		end		
`else
        SD_RD_PT: begin
			if(cmd_rdy) sdinit_nstate <= SD_WR_PT;//t
			else sdinit_nstate <= SD_RD_PT;
		end	
        SD_RD_BPB: begin
			if(cmd_rdy && arg == arg_r+P_MEM-32'h0000_0200) sdinit_nstate <= SD_WR_PT;
			else sdinit_nstate <= SD_RD_BPB;
		end
		SD_WR_PT: begin
			if(cmd_rdy) sdinit_nstate <= SD_RD_PT;//t
			else sdinit_nstate <= SD_WR_PT;
		end
		SD_WR_BPB: begin
		    if(cmd_rdy && arg == arg_wr_r+P_MEM-32'h0000_0200)
			sdinit_nstate <= SD_RD_PT;
			else sdinit_nstate <= SD_WR_BPB;
		end
`endif
        SD_DELAY: begin
			if(done_5s) sdinit_nstate <= SD_RD_PT;	//��ʾ��һ��ͼƬ
			else sdinit_nstate <= SD_DELAY;
		end
	default: sdinit_nstate <= SDINIT_RST;
	endcase
end

//���ݿ���
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
			cmd <= 6'd0;	//��������Ĵ���
			arg <= 32'd0;	//���Ͳ����Ĵ���
			crc <= 8'd0;	//����CRCУ����
			//sd_test <= 1'b1;
		end
	else
		case(sdinit_nstate)
			SDINIT_CMD0: begin
				cmd <= 6'd0;	//��������Ĵ���CMD0
				arg <= 32'h00000000;	//���Ͳ����Ĵ���	
				crc <= 8'h95;	//����CMD0 CRCУ����				
			end		
			SDINIT_CMD8: begin
				cmd <= 6'd8;
				arg <= 32'h000001aa;
				crc <= 8'h87;
			end
			SDINIT_CMD58: begin
				cmd <= 6'd58;
				arg <= 32'h00000000;
				crc <= 8'h01;
			end
			SDINIT_CMD58_OK: begin
				cmd <= 6'd58;
				arg <= 32'h00000000;
				crc <= 8'h01;
			end
			SDINIT_CMD55: begin
				cmd <= 6'd55;	//��������Ĵ���CMD55
				arg <= 32'h00000000;	//���Ͳ����Ĵ���
				crc <= 8'hff;	//����CRCУ����		
			end
			SDINIT_ACMD41: begin
				cmd <= 6'd41;	//��������Ĵ���ACMD41
				arg <= 32'h40000000;	//���Ͳ����Ĵ���
				crc <= 8'hff;	//����CRCУ����		
			end	
			SDINIT_CMD1: begin
				cmd <= 6'd1;	//��������Ĵ���
				arg <= 32'd0;	//���Ͳ����Ĵ���
				//crc <= 8'hff;	//����CRCУ����					
			end
			SDINIT_CMD16: begin
				cmd <= 6'd16;	//��������Ĵ���CMD16
				arg <= 32'd512;	//���Ͳ����Ĵ���512Byte		????????????????????????????
				crc <= 8'hff;	                			
			end	
			SD_IDLE: begin
				cmd <= 6'd0;	
				if(cmd_rdy) arg <= P0_ADDR;//32'h0004_6600;	//��bmp0���ݴ�ŵĵ�1������ַ
				crc <= 8'hff;	 
                //sd_test <= 1'b0;				
			end		
			SD_RD_PT: begin
				cmd <= 6'd17;	//��������CMD17		
				arg_r <= arg;
				if(cmd_rdy) arg <= P0_ADDR;
				//if(cmd_rdy) arg <= arg+32'h0000_0200;
				crc <= 8'hff;	
			end
`ifdef JUST_RD			
			SD_RD_BPB: begin
				cmd <= 6'd17;	//��������CMD17
				if(cmd_rdy) arg <= arg+32'h0000_0200;	//������ȡbmp���ݴ�ŵĵ�2-03ABH����	 ?????????????
				crc <= 8'hff;	
			end			
`else
            SD_RD_BPB: begin
				cmd <= 6'd17;	//��������CMD17
				if(cmd_rdy) begin
				    if(arg == arg_r + P_MEM - 32'h0000_0200) arg <= P0_WR_ADDR;
				    else arg <= arg+32'h0000_0200;
				end
				crc <= 8'hff;	
			end
			SD_WR_PT: begin
			    cmd <= 6'd24;
				arg_wr_r <= arg;
				if(cmd_rdy) arg <= P0_WR_ADDR;
				crc <= 8'hff;	
				//sd_test <= 1'b0;
            end		
            SD_WR_BPB: begin	
                cmd <= 6'd24;
                if(cmd_rdy) begin
				    if(arg == arg_wr_r + P_MEM - 32'h0000_0200) arg <= P0_ADDR;
				    else arg <= arg+32'h0000_0200;
                end
                crc <= 8'hff;					
			end
`endif
            SD_DELAY: begin
				cmd <= 6'd0;
				//arg <= 32'h0004_6600;	//��ȡbmp���ݴ�ŵĵ�1����	
				//arg <= 32'h000b_be00;
				if(sdwrad_clr) begin	//��ʾ��һ��ͼƬ,�̶�10��ͼƬѭ����ʾ
					if(arg == LAST_ADDR-32'h0000_0200) arg <= P0_ADDR;//32'h0004_6600;
					else arg <= arg_r+P_MEM;
				end
			end
		default: begin
					cmd <= 6'd0;	//��������Ĵ���
					arg <= 32'd0;	//���Ͳ����Ĵ���			
				end
		endcase
end

//------------------------------------------------------
//2009.05.19	���5.4s��ʱ�л�ͼƬָ��
reg[27:0] cnt5s;	//5.4s��ʱ������

	//5.4s����
always @(posedge clk or negedge rst_n)
	if(!rst_n) cnt5s <= 28'd0;
	else if(sdinit_nstate == SD_DELAY) cnt5s <= cnt5s+1'b1;
	else cnt5s <= 28'd0;

//wire sdwrad_clr = (sdinit_nstate == SD_DELAY);
wire sdwrad_clr = (cnt5s == 28'hffffff0);	//SDRAMд��������ź����㸴λ�źţ�����Ч
assign done_5s = (cnt5s == 28'hfffffff);	//5.4s��ʱ��������Чһ��ʱ������

assign spi_cs_n = spi_cs_nr;
assign spi_tx_en = spi_tx_enr;
assign spi_rx_en = spi_rx_enr;
assign spi_tx_db = spi_tx_dbr;
assign sd_dout = spi_rx_dbr;
	//ÿ����һ���ֽ����ݣ���λ�ø�һ��ʱ�����ڣ���512B
assign sd_fifowr = (spi_rx_rdy & ~spi_rx_enr & (cmd_cstate == CMD_RD) & (cnt512 < 10'd513));

assign sd_fiford = (spi_tx_rdy & ~spi_tx_enr & ((cmd_cstate == CMD_WRCLK & wrclk_cnt == `WR_RDY_CLK) | cmd_cstate == CMD_WR) & (cnt512 < 10'd512));

wire cmd_clk = (sdinit_cstate == SDINIT_CLK);	//�����ϵ��ʼ��ʱ��74+CLK����״̬��־λ
wire cmd_en = ((sdinit_cstate == SDINIT_CMD0) | (sdinit_cstate == SDINIT_CMD8) | 
 (sdinit_cstate == SDINIT_CMD58) | (sdinit_cstate == SDINIT_CMD55) | (sdinit_cstate == SDINIT_ACMD41)
		/*(sdinit_cstate == SDINIT_CMD1) | (sdinit_cstate == SDINIT_CMD16)*/
		| (sdinit_cstate == SDINIT_CMD58_OK));	//�����ʹ�ܱ�־λ,����Ч
wire cmd_rdboot_en = (sdinit_cstate == SD_RD_BPB) | (sdinit_cstate == SD_RD_PT);	//��ȡSD������ʹ���źţ�����Ч	
assign cmd_rdy = ((cmd_nstate == CMD_CLKE) & spi_tx_rdy & spi_tx_enr);	//�������ɱ�־λ,����Ч
wire cmd_wr_en = (sdinit_cstate == SD_WR_BPB) | (sdinit_cstate == SD_WR_PT);

//״̬ת��
always @(posedge clk or negedge rst_n)
	if(!rst_n) begin
`ifndef	SIM
	    cmd_cstate <= CMD_IDLE;
`else
        cmd_cstate <= CMD_IDLE;
`endif
	end
	else cmd_cstate <= cmd_nstate;

//״̬����
always @(cmd_cstate or wait_cnt8 or cmd_clk or cmd_en or spi_tx_rdy or spi_rx_rdy or nclk_cnt or retry_rep
			or sdinit_cstate or spi_tx_enr or spi_rx_enr or cmd_rdboot_en or cnt512 or spi_rx_dbr
			or cmd_ok or cmd_wr_en or wrclk_cnt or wrdone_cnt) begin
	case(cmd_cstate)
			CMD_IDLE: begin
				if(wait_cnt8 == 8'hff)
					if(cmd_clk) cmd_nstate <= CMD_NCLK;
					else if(cmd_en | cmd_rdboot_en | cmd_wr_en) cmd_nstate <= CMD_CSH;
					else cmd_nstate <= CMD_IDLE; 
				else cmd_nstate <= CMD_IDLE;
			end
			CMD_NCLK: begin
				if(spi_tx_rdy && (nclk_cnt == 7'd11) && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_CLKE;
				else cmd_nstate <= CMD_NCLK;
			end
			CMD_CSH: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_CLKS;
				else cmd_nstate <= CMD_CSH;
			end			
			CMD_CLKS: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_STAR;
				else cmd_nstate <= CMD_CLKS;
			end
			CMD_STAR: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_ARG1;
				else cmd_nstate <= CMD_STAR;
			end
			CMD_ARG1: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_ARG2;
				else cmd_nstate <= CMD_ARG1;
			end
			CMD_ARG2: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_ARG3;
				else cmd_nstate <= CMD_ARG2;
			end
			CMD_ARG3: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_ARG4;
				else cmd_nstate <= CMD_ARG3;
			end
			CMD_ARG4: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) begin				
				    //if(!cmd_wr_en) 
					    cmd_nstate <= CMD_END;
					//else cmd_nstate <= CMD_RES;
				end
				else cmd_nstate <= CMD_ARG4;
			end
			CMD_END: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_RES;
				else cmd_nstate <= CMD_END;
			end
			CMD_RES: begin
				if(retry_rep == 12'hfff) cmd_nstate <= CMD_IDLE;	//��Ӧ��ʱ������IDLE���·�������
				else if(spi_rx_rdy && (!spi_tx_enr & !spi_rx_enr)) begin
					case(sdinit_cstate) 		
						SD_RD_PT,SD_RD_BPB: 
									if(spi_rx_dbr == 8'hfe) cmd_nstate <= CMD_RD;	//���յ�RD�������ʼ�ֽ�8'hfe,������ȡ�����512B
									else cmd_nstate <= CMD_RES; 	
						SDINIT_CMD8:
									if(cmd_ok == 1'd0) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//������ȷ��Ӧ,������ǰ����
						SDINIT_CMD58:
									if(cmd_ok == 1'd0) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//������ȷ��Ӧ,������ǰ����		
						SDINIT_CMD58_OK:
									if(cmd_ok == 1'd0) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//������ȷ��Ӧ,������ǰ����										
						SDINIT_CMD0,SDINIT_CMD55,SDINIT_ACMD41,SDINIT_CMD16:
									if(spi_rx_dbr == 8'hff) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//������ȷ��Ӧ,������ǰ����
						SD_WR_PT,SD_WR_BPB:
						            if(spi_rx_dbr == 8'h00) cmd_nstate <= CMD_WRCLK;
									else cmd_nstate <= CMD_RES;
									//���յ�WR����ķ�������8'h00��ʾ���ճɹ�
						default: cmd_nstate <= CMD_CLKE;
						endcase					
				end
				/*else if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) begin
				    if(sdinit_cstate == SD_WR_BPB || sdinit_cstate == SD_WR_PT) begin
					    cmd_nstate <= CMD_WR;
					end
					else cmd_nstate <= CMD_CLKE;
				end*/
				else cmd_nstate <= CMD_RES;			
			end
			CMD_CLKE: begin
				if(spi_tx_rdy && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_IDLE;
				else cmd_nstate <= CMD_CLKE;
			end
			CMD_RD: begin
				if(cnt512 == 10'd514) cmd_nstate <= CMD_DELAY;	//ֱ����ȡ512�ֽ�+2�ֽ�CRC���
				else cmd_nstate <= CMD_RD;
			end
			CMD_WRCLK: begin
				if(spi_tx_rdy && (wrclk_cnt == `WR_RDY_CLK) && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_WR;
				else cmd_nstate <= CMD_WRCLK;
			end
			CMD_WR: begin
				if(cnt512 == 10'd515) cmd_nstate <= CMD_WRDONE;	//ֱ��д��512�ֽ�+2�ֽ�CRC���
				else cmd_nstate <= CMD_WR;
			end
			CMD_WRDONE: begin
				if(wrdone_cnt == 8'hff) cmd_nstate <= CMD_IDLE;	//��Ӧ��ʱ������IDLE���·�������
				else if(spi_rx_rdy && (!spi_tx_enr & !spi_rx_enr)) begin
`ifndef SIM				
				    if(spi_rx_dbr == 8'hff) cmd_nstate <= CMD_DELAY;
`else
                    if(spi_rx_dbr == 8'h00) cmd_nstate <= CMD_DELAY;
`endif					
					    else cmd_nstate <= CMD_WRDONE;
				end
			    else cmd_nstate <= CMD_WRDONE;
            end				
			CMD_DELAY: begin
				cmd_nstate <= CMD_CLKE;
			end
		default: ;
		endcase
end

reg[2:0] spi_rx_db_cnt;

//���ݿ���
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
			spi_cs_nr <= 1'b1;
			spi_tx_enr <= 1'b0;
			spi_rx_enr <= 1'b0;
			spi_tx_dbr <= 8'hff;
			nclk_cnt <= 7'd0;	//74+CLK�������ڼ���������
			wrclk_cnt <= 10'd0;	//д��80CLK�������ڼ���������
			wait_cnt8 <= 8'hff;	//�����������ȴ�������			
			cnt512 <= 10'd0;
			retry_rep <= 12'd0;
			retry_cmd <= 8'd0;	//��ǰCMD���ʹ�������������
			spi_rx_db_cnt <= 3'd0;
			cmd_ok <= 1'b0;		
            wrdone_cnt <= 8'd0;			
			sd_test <= 1'b1;
		end
	else 
		case(cmd_nstate)
			CMD_IDLE: begin
				wait_cnt8 <= wait_cnt8+1'b1;
				if(wait_cnt8 > 8'hfd) begin	
					if(cmd_clk) begin
						spi_cs_nr <= 1'b1;
						spi_tx_enr <= 1'b0;
						spi_rx_enr <= 1'b0;
						spi_tx_dbr <= 8'hff;
						cnt512 <= 10'd0;
						end/*
					else if(cmd_en | cmd_rdboot_en) begin
						cnt512 <= 10'd0;
						//spi_cs_nr <= 1'b1;
						spi_cs_nr <= 1'b0;	//SD��ƬѡCS����
						spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
						spi_rx_enr <= 1'b0;
						spi_tx_dbr <= {2'b01,cmd};	//��ʼ�ֽ������������ݷ��ͼĴ���						
						end*/
					end
				else begin
					spi_cs_nr <= 1'b1;
					spi_tx_enr <= 1'b0;
					spi_rx_enr <= 1'b0;
					spi_tx_dbr <= 8'hff;
					cnt512 <= 10'd0;	
					retry_rep <= 12'd0;	
					spi_rx_db_cnt <= 3'd0;
					cmd_ok <= 1'b0;			
                    wrdone_cnt <= 8'd0;						
					end
			end
			CMD_NCLK: begin
				if(spi_tx_rdy) begin
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					if(spi_tx_enr) nclk_cnt <= nclk_cnt+1'b1;	//74+CLK�������ڼ���������
					end
				else if(!spi_tx_enr) spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����		                    						
			end			
			CMD_CSH: begin
				if(spi_tx_rdy) begin/*Ϊ��һ����CMD_CLKS��׼��*/
					spi_cs_nr <= 1'b0;  //SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;	
				end
				else begin
					spi_cs_nr <= 1'b1;	//SD��ƬѡCS����
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;		
				end
			end
			CMD_CLKS: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= {2'b01,cmd};	//��ʼ�ֽ������������ݷ��ͼĴ���
					end
				else begin
					//spi_cs_nr <= 1'b1;
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;				
					end
			end
			CMD_STAR: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[31:24];	//arg[31:24]�����������ݷ��ͼĴ���   ?????
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG1: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[23:16];	//arg[23:16]�����������ݷ��ͼĴ���  ??????
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG2: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[15:8];	//arg[15:8]�����������ݷ��ͼĴ���     ???????
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG3: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[7:0];	//arg[7:0]�����������ݷ��ͼĴ���	 ??????				
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG4: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= crc;	//����CRCУ����		//8'h95;	//������RESET��Ч��CRCЧ����
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;					
					end
			end	
			CMD_END: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) begin
						spi_tx_dbr <= 8'hff;
						retry_cmd <= retry_cmd+1'b1;	//��ǰCMD���ʹ�����������1
						end
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;					
					end
			end						
			CMD_RES: begin
				if(spi_rx_rdy) begin
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b0;	
					spi_rx_enr <= 1'b0;	//SPI����ʹ�ܹر�
					spi_tx_dbr <= 8'hff;					
					spi_rx_dbr <= spi_rx_db;	//����SPI��Ӧ�ֽ�����
					if(sdinit_cstate == SDINIT_CMD8 && !spi_rx_en) begin	/*��������ж�*/
							if((spi_rx_db_cnt == 3'd0) && (spi_rx_dbr == 8'h01)) begin
									spi_rx_db_cnt <= 3'd1;												
								end
							else if((spi_rx_db_cnt == 3'd1) && (spi_rx_dbr == 8'h00)) begin
									spi_rx_db_cnt <= 3'd2;		
								end
							else if((spi_rx_db_cnt == 3'd2) && (spi_rx_dbr == 8'h00)) begin
									spi_rx_db_cnt <= 3'd3;
								end
							else if((spi_rx_db_cnt == 3'd3) && (spi_rx_dbr == 8'h01)) begin
									spi_rx_db_cnt <= 3'd4;
								end
							else if((spi_rx_db_cnt == 3'd4) && (spi_rx_dbr == 8'haa)) begin
									spi_rx_db_cnt <= 3'd0;
									cmd_ok <= 1'b1;
								end
							else begin
									spi_rx_db_cnt <= 3'd0;
									cmd_ok <= 1'b0;
								end			
						end
					else if(sdinit_cstate == SDINIT_CMD58 && !spi_rx_en) begin
							if((spi_rx_db_cnt == 3'd0) && (spi_rx_dbr == 8'h01)) begin
									spi_rx_db_cnt <= 3'd1;												
								end
							else if((spi_rx_db_cnt == 3'd1) && (spi_rx_dbr == 8'h00)) begin
									spi_rx_db_cnt <= 3'd2;		
								end
							else if(spi_rx_db_cnt == 3'd2) begin
									spi_rx_db_cnt <= 3'd3;
								end
							else if(spi_rx_db_cnt == 3'd3) begin
									spi_rx_db_cnt <= 3'd4;
								end
							else if(spi_rx_db_cnt == 3'd4) begin
									spi_rx_db_cnt <= 3'd0;
									cmd_ok <= 1'b1;
								end
							else begin
									spi_rx_db_cnt <= 3'd0;
									cmd_ok <= 1'b0;
								end			
						end		
					else if(sdinit_cstate == SDINIT_CMD58_OK && !spi_rx_en) begin
							if((spi_rx_db_cnt == 3'd0) && (spi_rx_dbr == 8'h00)) begin
									spi_rx_db_cnt <= 3'd1;												
								end
							else if((spi_rx_db_cnt == 3'd1) && (spi_rx_dbr == 8'hc0)) begin
									spi_rx_db_cnt <= 3'd2;		
								end
							else if(spi_rx_db_cnt == 3'd2) begin
									spi_rx_db_cnt <= 3'd3;
								end
							else if(spi_rx_db_cnt == 3'd3) begin
									spi_rx_db_cnt <= 3'd4;
								end
							else if(spi_rx_db_cnt == 3'd4) begin
									spi_rx_db_cnt <= 3'd0;
									cmd_ok <= 1'b1;
								end
							else begin
									spi_rx_db_cnt <= 3'd0;
									cmd_ok <= 1'b0;
								end			
						end	
					if(spi_rx_enr) retry_rep <= retry_rep+1'b1;					
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч	
					spi_tx_enr <= 1'b0;	//SPI����ʹ�ܿ���	
					spi_rx_enr <= 1'b1;	//SPI����ʹ�ܿ���		
                    nclk_cnt <= 7'd0;					
					end
			end
			CMD_CLKE: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b1;
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= 8'hff;
					retry_cmd <= 8'd0;	//��ǰCMD���ʹ�������������
					end
				else begin
					spi_cs_nr <= 1'b1;
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;
					spi_tx_dbr <= 8'hff;
					wait_cnt8 <= 4'd0;
					end
			end
			CMD_RD: begin
				if(spi_tx_rdy /*&& sd_rd_en*/) begin
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b0;	
					spi_rx_enr <= 1'b0;		//SPI����ʹ����ʱ�ر�
					spi_tx_dbr <= 8'hff;			
					spi_rx_dbr <= spi_rx_db;	//����SPI��Ӧ�ֽ�����
					if(spi_rx_enr) cnt512 <= cnt512+1'b1;	                    			
				end
				else begin
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b0;	
					spi_rx_enr <= 1'b1;	//SPI����ʹ�ܿ���
					spi_tx_dbr <= 8'hff;							
				end
			end
			CMD_WRCLK: begin
				if(spi_tx_rdy) begin
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�		                   						
					if(spi_tx_enr) begin
					    wrclk_cnt <= wrclk_cnt+1'b1;	//д��80CLK�������ڼ���������
					    if(wrclk_cnt == `WR_RDY_CLK - 1'b1) spi_tx_dbr <= 8'hfe;	//д��ʼ�ȷ���FE				        				
						end
					end
				else if(!spi_tx_enr) spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����		                    						
			end	
			CMD_WR: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;					
					if(spi_tx_enr) begin
					    if(10'd0 <= cnt512 && 10'd512 > cnt512) spi_tx_dbr <= ff_din;//��FF��ȡд����
						else spi_tx_dbr <= 8'hff;  //д������2λcrcУ��
					    cnt512 <= cnt512+1'b1;	
					    end
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b1;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b0;		
                    wrclk_cnt <= 10'd0;	//д��80CLK��������0                    				
					end
			end
			CMD_WRDONE: begin
				if(spi_rx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ��ʱ�ر�
					spi_rx_enr <= 1'b0;
					spi_tx_dbr <= 8'd0;					
					spi_rx_dbr <= spi_rx_db;	//����SPI��Ӧ�ֽ�����
					if(spi_rx_enr) wrdone_cnt <= wrdone_cnt + 1'b1;					
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD��ƬѡCS��Ч
					spi_tx_enr <= 1'b0;	//SPI����ʹ����Чλ����
					spi_rx_enr <= 1'b1;	//SPI����ʹ�ܿ���			
                    sd_test <= 1'b1;						
					end
			end
			CMD_DELAY: begin
				spi_cs_nr <= 1'b1;
				spi_tx_enr <= 1'b0;
				spi_rx_enr <= 1'b0;
				spi_tx_dbr <= 8'hff;
                wrdone_cnt <= 8'd0;		
                sd_test <= 1'b0;					
			end
		default: begin
			spi_cs_nr <= 1'b1;
			spi_tx_enr <= 1'b0;
			spi_rx_enr <= 1'b0;
			spi_tx_dbr <= 8'hff;
		end
		endcase
end

//------------------------------------------------------
//


//------------------------------------------------------
//















endmodule
