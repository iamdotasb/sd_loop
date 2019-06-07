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
// Description	: 该工程用于sdcard状态机
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

input clk;		//FPAG输入时钟信号50MHz
input rst_n;	//FPGA输入复位信号

output spi_cs_n;	//SPI从设备使能信号，由主设备控制

output spi_tx_en;		//SPI数据发送使能信号，高有效
input spi_tx_rdy;		//SPI数据发送完成标志位，高有效
output spi_rx_en;		//SPI数据接收使能信号，高有效
input spi_rx_rdy;		//SPI数据接收完成标志位，高有效
output[7:0] spi_tx_db;	//SPI数据发送寄存器
input[7:0] spi_rx_db;	//SPI数据接收寄存器

output[7:0] sd_dout;	//从SD读出的待放入FIFO数据
output sd_fifowr;		//sd读出数据写入FIFO使能信号，高有效
output sd_fiford;		//sd读出数据读取FIFO使能信号，高有效
//input sd_rd_en;
//input sd_wr_en;
output sdwrad_clr;		//SDRAM写控制相关信号清零复位信号，高有效

input[7:0] ff_din;
output reg sd_test;

/*参数设置*/
//由于不同的SD卡文件系统有可能为FAT16/32，存储量大小也有可能不同，照成了其数据地址的不同
//该工程没有对文件系统管理做设计，所以需要大家在winhex下读出所使用的SD卡的以下参数后进行设置
//要求SD卡使用前最好格式化，然后放入10幅800*600的8位图片
parameter	P0_ADDR		= 32'h4040,//32'hEC_8000,//14718880//1C12F4000,//32'h0004_6600,		//第一幅图片P0的首扇区地址
			P_MEM		= 32'h7_8000,//32'h0007_5800,		//一副800*600的8位图片格式在SD卡中所占用的地址空间
			LAST_ADDR	= 32'h41_0000,//1C17A4000;//32'h004d_d600;		//10幅图片的最后一个地址
			P0_WR_ADDR	    = 32'h4080,//32'hF4_0000,
			LAST_WR_ADDR	= 32'hFB_8000;
//assign sdwrad_clr = done_5s;
//------------------------------------------------------
//SD上电初始化
//	1. 适当延时等待SD就绪
//	2. 发送74+个spi_clk，且保持spi_cs_n=1,spi_mosi=1 
//	3. 发送CMD0命令并等待响应R1=8'h01: 将卡复位到IDLE状态
//	4. 发送CMD1命令并等待响应R1=8'h00: 激活卡的初始化进程
//	5. 发送CMD16命令并等待响应R1=8'h00: 设置一次读写BLOCK的长度为512个字节
//SD数据读取操作
//	1. 发送命令CMD17
//	2. 接收读数据起始令牌0xfe
//	3. 读取512Byte数据以及2Byte的CRC
//------------------------------------------------------
//上电延时等待计数
reg[10:0] delay_cnt;	//10bit延时计数器，计数到1000即40ns*1000=40us	

always @(posedge clk or negedge rst_n)
	if(!rst_n) delay_cnt <= 11'd0;
	else if(delay_cnt < 11'd2000) delay_cnt <= delay_cnt+1'b1;
	
wire delay_done = (delay_cnt == 11'd2000);	//40us延时时间完成标志位，高有效	

//------------------------------------------------------
//sd状态机控制
reg[3:0] sdinit_cstate;		//sd初始化当前状态寄存器
reg[3:0] sdinit_nstate;		//sd初始化下一状态寄存器

parameter	SDINIT_RST	= 4'd0,		//复位等待状态
			SDINIT_CLK	= 4'd1,		//74+时钟产生状态
			SDINIT_CMD0 = 4'd2,		//发送CMD0命令状态
			SDINIT_CMD55 = 4'd3,	//发送CMD55命令状态
			SDINIT_ACMD41 = 4'd4,	//发送ACMD41命令状态
			SDINIT_CMD1 = 4'd5,		//发送CMD1命令状态
			SDINIT_CMD16 = 4'd6,	//发送CMD16命令状态
			SD_IDLE 	= 4'd7,		//sd初始化完成正常工作状态
			SD_RD_PT	= 4'd8,		//sd读取Partition Table
			SD_RD_BPB	= 4'd9,		//sd读取启动区状态
			SD_DELAY	= 4'd10,	//sd操作完毕延时等待状态
			SDINIT_CMD8 = 4'd11,	//sd配置命令，配置一些物理参数
			SDINIT_CMD58= 4'd12,	//sd状态命令，令SD卡反馈状态
			SDINIT_CMD58_OK = 4'd13,
			SD_WR_PT	= 4'd14,		//sd读取Partition Table
			SD_WR_BPB	= 4'd15;		//sd读取启动区状态

//状态转移
always @(posedge clk or negedge rst_n)
	if(!rst_n) 
`ifndef SIM	
	    sdinit_cstate <= SDINIT_RST;
`else
        sdinit_cstate <= SD_IDLE;
`endif
	else sdinit_cstate <= sdinit_nstate;

//状态控制
wire cmd_rdy;
reg cmd_ok;
reg[31:0] arg_r;	//起始扇区地址寄存器
reg[31:0] arg_wr_r;	//起始扇区地址寄存器(写入)
wire done_5s;
reg[4:0] cmd_cstate;	//发送命令当前状态寄存器
reg[4:0] cmd_nstate;	//发送命令下一状态寄存器

parameter	CMD_IDLE	= 5'd0,		//无命令发送，等待状态
			CMD_NCLK	= 5'd1,		//上电初始化时需要产生74+CLK状态
			CMD_CLKS	= 5'd2,		//产生8个CLK状态
			CMD_STAR	= 5'd3,		//发送起始字节状态
			CMD_ARG1	= 5'd4,		//发送arg[31:24]状态
			CMD_ARG2	= 5'd5,		//发送arg[23:16]状态
			CMD_ARG3	= 5'd6,		//发送arg[15:8]状态
			CMD_ARG4	= 5'd7,		//发送arg[7:0]状态
			CMD_END		= 5'd8,		//发送结束字节状态
			CMD_RES		= 5'd9,		//接收响应字节
			CMD_CLKE	= 5'd10,	//产生8个CLK状态
			CMD_RD		= 5'd11,	//读512Byte状态
			CMD_DELAY	= 5'd12,	//读写操作完成延时等待状态
			CMD_CSH 	= 5'd13,	//T0时刻CS拉高，并送8个周期clk
			CMD_WRCLK 	= 5'd14,    //写前产生80个CLK状态
			CMD_WR      = 5'd15,    //写512Byte状态
			CMD_WRDONE  = 5'd16;    //读取写结束状态

//------------------------------------------------------
//SD命令CMD发送控制
//	1. 发送8个时钟脉冲
//  2. SD卡片选CS拉低,即片选有效
//  3. 连续发送6个字节命令
//	4. 接收1个字节响应数据
//	5. SD卡片选CS拉高,即关闭SD卡
/*		发送总共6个字节命令格式:
        0 -- start bit 
        1 -- host
        bit5-0 --  command
        bit31-0 -- argument
        bit6-0 -- CRC7
        1 -- end bit   
*/
//------------------------------------------------------
//发送sd命令状态机控制
reg[5:0] cmd;	//发送命令寄存器
reg[31:0] arg;	//发送参数寄存器
reg[7:0] crc;	//发送CRC校验码

reg spi_cs_nr;	//SPI从设备使能信号，由主设备控制
reg spi_tx_enr;	//SPI数据发送使能信号，高有效
reg spi_rx_enr;	//SPI数据接收使能信号，高有效
reg[7:0] spi_tx_dbr;	//SPI数据发送寄存器
reg[7:0] spi_rx_dbr;	//SPI数据接收寄存器
reg[6:0] nclk_cnt;		//74+CLK发送周期计数器
reg[9:0] wrclk_cnt;		//写卡80CLK发送周期计数器
reg[7:0] wrdone_cnt;    //重复读取写卡完成计数器
reg[7:0] wait_cnt8;		//命令操作间隔等待计数器
reg[9:0] cnt512;	//读取512B计数器
reg[11:0] retry_rep;		//重复读取respone计数器
reg[7:0] retry_cmd;		//重复当前命令计数器
			
always @(sdinit_cstate or retry_rep or delay_done or nclk_cnt 
			or cmd_rdy or spi_rx_dbr or arg or arg_r or arg_wr_r or done_5s 
			or cmd_ok) begin
	case(sdinit_cstate)
		SDINIT_RST: begin
			if(delay_done) sdinit_nstate <= SDINIT_CLK;	//上电后40us延时完成，进入74+CLK状态
			else sdinit_nstate <= SDINIT_RST;	//等待上电后40us延时完成
		end
		SDINIT_CLK:	begin
			if(cmd_rdy) sdinit_nstate <= SDINIT_CMD0;	//74+CLK完成
			else sdinit_nstate <= SDINIT_CLK;
		end
		SDINIT_CMD0: begin
			if(cmd_rdy && (spi_rx_dbr == 8'h01)) sdinit_nstate <= SDINIT_CMD8;//sdinit_nstate <= SDINIT_CMD55;
			else sdinit_nstate <= SDINIT_CMD0;
		end
		SDINIT_CMD8: begin		//sdhcv2.0新增		
			if(cmd_rdy && (cmd_ok == 1'b1)) sdinit_nstate <= SDINIT_CMD58;
			else sdinit_nstate <= SDINIT_CMD8;
		end
		SDINIT_CMD58: begin		//sdhcv2.0新增		
			if(cmd_rdy && (cmd_ok == 8'h01)) sdinit_nstate <= SDINIT_CMD55;
			else sdinit_nstate <= SDINIT_CMD58;
		end
		SDINIT_CMD55: begin
			if(cmd_rdy && (spi_rx_dbr == 8'h01)) sdinit_nstate <= SDINIT_ACMD41;
			else sdinit_nstate <= SDINIT_CMD55;
		end
		SDINIT_ACMD41: begin
			if(retry_rep == 12'hfff) sdinit_nstate <= SDINIT_CMD55;	///////////响应超时，返回IDLE重新发起命令 
			else if(cmd_rdy && spi_rx_dbr != 8'h00) sdinit_nstate <= SDINIT_CMD55; 
			else if(cmd_rdy && spi_rx_dbr == 8'h00) sdinit_nstate <= SDINIT_CMD58_OK;
			else sdinit_nstate <= SDINIT_ACMD41;	
		end
		SDINIT_CMD58_OK: begin		//sdhcv2.0新增		
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
			if(done_5s) sdinit_nstate <= SD_RD_PT;	//显示下一幅图片
			else sdinit_nstate <= SD_DELAY;
		end
	default: sdinit_nstate <= SDINIT_RST;
	endcase
end

//数据控制
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
			cmd <= 6'd0;	//发送命令寄存器
			arg <= 32'd0;	//发送参数寄存器
			crc <= 8'd0;	//发送CRC校验码
			//sd_test <= 1'b1;
		end
	else
		case(sdinit_nstate)
			SDINIT_CMD0: begin
				cmd <= 6'd0;	//发送命令寄存器CMD0
				arg <= 32'h00000000;	//发送参数寄存器	
				crc <= 8'h95;	//发送CMD0 CRC校验码				
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
				cmd <= 6'd55;	//发送命令寄存器CMD55
				arg <= 32'h00000000;	//发送参数寄存器
				crc <= 8'hff;	//发送CRC校验码		
			end
			SDINIT_ACMD41: begin
				cmd <= 6'd41;	//发送命令寄存器ACMD41
				arg <= 32'h40000000;	//发送参数寄存器
				crc <= 8'hff;	//发送CRC校验码		
			end	
			SDINIT_CMD1: begin
				cmd <= 6'd1;	//发送命令寄存器
				arg <= 32'd0;	//发送参数寄存器
				//crc <= 8'hff;	//发送CRC校验码					
			end
			SDINIT_CMD16: begin
				cmd <= 6'd16;	//发送命令寄存器CMD16
				arg <= 32'd512;	//发送参数寄存器512Byte		????????????????????????????
				crc <= 8'hff;	                			
			end	
			SD_IDLE: begin
				cmd <= 6'd0;	
				if(cmd_rdy) arg <= P0_ADDR;//32'h0004_6600;	//送bmp0数据存放的第1扇区地址
				crc <= 8'hff;	 
                //sd_test <= 1'b0;				
			end		
			SD_RD_PT: begin
				cmd <= 6'd17;	//发送命令CMD17		
				arg_r <= arg;
				if(cmd_rdy) arg <= P0_ADDR;
				//if(cmd_rdy) arg <= arg+32'h0000_0200;
				crc <= 8'hff;	
			end
`ifdef JUST_RD			
			SD_RD_BPB: begin
				cmd <= 6'd17;	//发送命令CMD17
				if(cmd_rdy) arg <= arg+32'h0000_0200;	//连续读取bmp数据存放的第2-03ABH扇区	 ?????????????
				crc <= 8'hff;	
			end			
`else
            SD_RD_BPB: begin
				cmd <= 6'd17;	//发送命令CMD17
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
				//arg <= 32'h0004_6600;	//读取bmp数据存放的第1扇区	
				//arg <= 32'h000b_be00;
				if(sdwrad_clr) begin	//显示下一幅图片,固定10幅图片循环显示
					if(arg == LAST_ADDR-32'h0000_0200) arg <= P0_ADDR;//32'h0004_6600;
					else arg <= arg_r+P_MEM;
				end
			end
		default: begin
					cmd <= 6'd0;	//发送命令寄存器
					arg <= 32'd0;	//发送参数寄存器			
				end
		endcase
end

//------------------------------------------------------
//2009.05.19	添加5.4s定时切换图片指令
reg[27:0] cnt5s;	//5.4s定时计数器

	//5.4s计数
always @(posedge clk or negedge rst_n)
	if(!rst_n) cnt5s <= 28'd0;
	else if(sdinit_nstate == SD_DELAY) cnt5s <= cnt5s+1'b1;
	else cnt5s <= 28'd0;

//wire sdwrad_clr = (sdinit_nstate == SD_DELAY);
wire sdwrad_clr = (cnt5s == 28'hffffff0);	//SDRAM写控制相关信号清零复位信号，高有效
assign done_5s = (cnt5s == 28'hfffffff);	//5.4s定时到，高有效一个时钟周期

assign spi_cs_n = spi_cs_nr;
assign spi_tx_en = spi_tx_enr;
assign spi_rx_en = spi_rx_enr;
assign spi_tx_db = spi_tx_dbr;
assign sd_dout = spi_rx_dbr;
	//每接收一个字节数据，该位置高一个时钟周期，共512B
assign sd_fifowr = (spi_rx_rdy & ~spi_rx_enr & (cmd_cstate == CMD_RD) & (cnt512 < 10'd513));

assign sd_fiford = (spi_tx_rdy & ~spi_tx_enr & ((cmd_cstate == CMD_WRCLK & wrclk_cnt == `WR_RDY_CLK) | cmd_cstate == CMD_WR) & (cnt512 < 10'd512));

wire cmd_clk = (sdinit_cstate == SDINIT_CLK);	//进入上电初始化时的74+CLK产生状态标志位
wire cmd_en = ((sdinit_cstate == SDINIT_CMD0) | (sdinit_cstate == SDINIT_CMD8) | 
 (sdinit_cstate == SDINIT_CMD58) | (sdinit_cstate == SDINIT_CMD55) | (sdinit_cstate == SDINIT_ACMD41)
		/*(sdinit_cstate == SDINIT_CMD1) | (sdinit_cstate == SDINIT_CMD16)*/
		| (sdinit_cstate == SDINIT_CMD58_OK));	//命令发送使能标志位,高有效
wire cmd_rdboot_en = (sdinit_cstate == SD_RD_BPB) | (sdinit_cstate == SD_RD_PT);	//读取SD启动区使能信号，高有效	
assign cmd_rdy = ((cmd_nstate == CMD_CLKE) & spi_tx_rdy & spi_tx_enr);	//命令发送完成标志位,高有效
wire cmd_wr_en = (sdinit_cstate == SD_WR_BPB) | (sdinit_cstate == SD_WR_PT);

//状态转移
always @(posedge clk or negedge rst_n)
	if(!rst_n) begin
`ifndef	SIM
	    cmd_cstate <= CMD_IDLE;
`else
        cmd_cstate <= CMD_IDLE;
`endif
	end
	else cmd_cstate <= cmd_nstate;

//状态控制
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
				if(retry_rep == 12'hfff) cmd_nstate <= CMD_IDLE;	//响应超时，返回IDLE重新发起命令
				else if(spi_rx_rdy && (!spi_tx_enr & !spi_rx_enr)) begin
					case(sdinit_cstate) 		
						SD_RD_PT,SD_RD_BPB: 
									if(spi_rx_dbr == 8'hfe) cmd_nstate <= CMD_RD;	//接收到RD命令的起始字节8'hfe,立即读取后面的512B
									else cmd_nstate <= CMD_RES; 	
						SDINIT_CMD8:
									if(cmd_ok == 1'd0) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//产生正确响应,结束当前命令
						SDINIT_CMD58:
									if(cmd_ok == 1'd0) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//产生正确响应,结束当前命令		
						SDINIT_CMD58_OK:
									if(cmd_ok == 1'd0) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//产生正确响应,结束当前命令										
						SDINIT_CMD0,SDINIT_CMD55,SDINIT_ACMD41,SDINIT_CMD16:
									if(spi_rx_dbr == 8'hff) cmd_nstate <= CMD_RES;	
									else cmd_nstate <= CMD_CLKE;	//产生正确响应,结束当前命令
						SD_WR_PT,SD_WR_BPB:
						            if(spi_rx_dbr == 8'h00) cmd_nstate <= CMD_WRCLK;
									else cmd_nstate <= CMD_RES;
									//接收到WR命令的反馈数据8'h00表示接收成功
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
				if(cnt512 == 10'd514) cmd_nstate <= CMD_DELAY;	//直到读取512字节+2字节CRC完成
				else cmd_nstate <= CMD_RD;
			end
			CMD_WRCLK: begin
				if(spi_tx_rdy && (wrclk_cnt == `WR_RDY_CLK) && (!spi_tx_enr & !spi_rx_enr)) cmd_nstate <= CMD_WR;
				else cmd_nstate <= CMD_WRCLK;
			end
			CMD_WR: begin
				if(cnt512 == 10'd515) cmd_nstate <= CMD_WRDONE;	//直到写入512字节+2字节CRC完成
				else cmd_nstate <= CMD_WR;
			end
			CMD_WRDONE: begin
				if(wrdone_cnt == 8'hff) cmd_nstate <= CMD_IDLE;	//响应超时，返回IDLE重新发起命令
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

//数据控制
always @(posedge clk or negedge rst_n) begin
	if(!rst_n) begin
			spi_cs_nr <= 1'b1;
			spi_tx_enr <= 1'b0;
			spi_rx_enr <= 1'b0;
			spi_tx_dbr <= 8'hff;
			nclk_cnt <= 7'd0;	//74+CLK发送周期计数器清零
			wrclk_cnt <= 10'd0;	//写卡80CLK发送周期计数器清零
			wait_cnt8 <= 8'hff;	//命令操作间隔等待计数器			
			cnt512 <= 10'd0;
			retry_rep <= 12'd0;
			retry_cmd <= 8'd0;	//当前CMD发送次数计数器清零
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
						spi_cs_nr <= 1'b0;	//SD卡片选CS拉高
						spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
						spi_rx_enr <= 1'b0;
						spi_tx_dbr <= {2'b01,cmd};	//起始字节命令送人数据发送寄存器						
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
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					if(spi_tx_enr) nclk_cnt <= nclk_cnt+1'b1;	//74+CLK发送周期计数器工作
					end
				else if(!spi_tx_enr) spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启		                    						
			end			
			CMD_CSH: begin
				if(spi_tx_rdy) begin/*为下一命令CMD_CLKS做准备*/
					spi_cs_nr <= 1'b0;  //SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;	
				end
				else begin
					spi_cs_nr <= 1'b1;	//SD卡片选CS拉高
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;		
				end
			end
			CMD_CLKS: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= {2'b01,cmd};	//起始字节命令送人数据发送寄存器
					end
				else begin
					//spi_cs_nr <= 1'b1;
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;				
					end
			end
			CMD_STAR: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[31:24];	//arg[31:24]命令送人数据发送寄存器   ?????
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG1: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[23:16];	//arg[23:16]命令送人数据发送寄存器  ??????
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG2: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[15:8];	//arg[15:8]命令送人数据发送寄存器     ???????
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG3: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= arg[7:0];	//arg[7:0]命令送人数据发送寄存器	 ??????				
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;					
					end
			end
			CMD_ARG4: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= crc;	//发送CRC校验码		//8'h95;	//仅仅对RESET有效的CRC效验码
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;					
					end
			end	
			CMD_END: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) begin
						spi_tx_dbr <= 8'hff;
						retry_cmd <= retry_cmd+1'b1;	//当前CMD发送次数计数器增1
						end
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;					
					end
			end						
			CMD_RES: begin
				if(spi_rx_rdy) begin
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b0;	
					spi_rx_enr <= 1'b0;	//SPI接收使能关闭
					spi_tx_dbr <= 8'hff;					
					spi_rx_dbr <= spi_rx_db;	//接收SPI响应字节数据
					if(sdinit_cstate == SDINIT_CMD8 && !spi_rx_en) begin	/*命令接收判断*/
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
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效	
					spi_tx_enr <= 1'b0;	//SPI发送使能开启	
					spi_rx_enr <= 1'b1;	//SPI接收使能开启		
                    nclk_cnt <= 7'd0;					
					end
			end
			CMD_CLKE: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b1;
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					if(spi_tx_enr) spi_tx_dbr <= 8'hff;
					retry_cmd <= 8'd0;	//当前CMD发送次数计数器清零
					end
				else begin
					spi_cs_nr <= 1'b1;
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;
					spi_tx_dbr <= 8'hff;
					wait_cnt8 <= 4'd0;
					end
			end
			CMD_RD: begin
				if(spi_tx_rdy /*&& sd_rd_en*/) begin
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b0;	
					spi_rx_enr <= 1'b0;		//SPI接收使能暂时关闭
					spi_tx_dbr <= 8'hff;			
					spi_rx_dbr <= spi_rx_db;	//接收SPI响应字节数据
					if(spi_rx_enr) cnt512 <= cnt512+1'b1;	                    			
				end
				else begin
					spi_cs_nr <= 1'b0;
					spi_tx_enr <= 1'b0;	
					spi_rx_enr <= 1'b1;	//SPI接收使能开启
					spi_tx_dbr <= 8'hff;							
				end
			end
			CMD_WRCLK: begin
				if(spi_tx_rdy) begin
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭		                   						
					if(spi_tx_enr) begin
					    wrclk_cnt <= wrclk_cnt+1'b1;	//写卡80CLK发送周期计数器工作
					    if(wrclk_cnt == `WR_RDY_CLK - 1'b1) spi_tx_dbr <= 8'hfe;	//写开始先发送FE				        				
						end
					end
				else if(!spi_tx_enr) spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启		                    						
			end	
			CMD_WR: begin
				if(spi_tx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;					
					if(spi_tx_enr) begin
					    if(10'd0 <= cnt512 && 10'd512 > cnt512) spi_tx_dbr <= ff_din;//从FF读取写数据
						else spi_tx_dbr <= 8'hff;  //写结束带2位crc校验
					    cnt512 <= cnt512+1'b1;	
					    end
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b1;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b0;		
                    wrclk_cnt <= 10'd0;	//写卡80CLK计数器清0                    				
					end
			end
			CMD_WRDONE: begin
				if(spi_rx_rdy) begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位暂时关闭
					spi_rx_enr <= 1'b0;
					spi_tx_dbr <= 8'd0;					
					spi_rx_dbr <= spi_rx_db;	//接收SPI响应字节数据
					if(spi_rx_enr) wrdone_cnt <= wrdone_cnt + 1'b1;					
					end
				else begin
					spi_cs_nr <= 1'b0;	//SD卡片选CS有效
					spi_tx_enr <= 1'b0;	//SPI发送使能有效位开启
					spi_rx_enr <= 1'b1;	//SPI接收使能开启			
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
