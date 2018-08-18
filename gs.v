/*

  -----------------------------------------------------------------------------
   General Sound
  -----------------------------------------------------------------------------
   18.08.2018	Reworked first verilog version
  
   CPU: Z80 @ 28MHz
   ROM: 32K
   RAM: 128KB+
   INT: 37.5KHz
  
   #xxBB Command register - регистр команд, доступный для записи
   #xxBB Status register - регистр состояния, доступный для чтения
  		bit 7 флаг данных
  		bit <6:1> Не определен
  		bit 0 флаг команд. Этот регистр позволяет определить состояние GS, в частности можно ли прочитать или записать очередной байт данных, или подать очередную команду, и т.п.
   #xxB3 Data register - регистр данных, доступный для записи. В этот регистр Спектрум записывает данные, например, это могут быть аргументы команд.
   #xxB3 Output register - регистр вывода, доступный для чтения. Из этого регистра Спектрум читает данные, идущие от GS
  
   Внутренние порта:
   #xx00 "расширенная память" - регистр доступный для записи
  		bit <3:0> переключают страницы по 32Kb, страница 0 - ПЗУ
  		bit <7:0> не используются
  
   порты 1 - 5 "обеспечивают связь с SPECTRUM'ом"
   #xx01 чтение команды General Sound'ом
  		bit <7:0> код команды
   #xx02 чтение данных General Sound'ом
  		bit <7:0> данные
   #xx03 запись данных General Sound'ом для SPECTRUM'a
  		bit <7:0> данные
   #xx04 чтение слова состояния General Sound'ом
  		bit 0 флаг команд
  		bit 7 флаг данных
   #xx05 сбрасывает бит D0 (флаг команд) слова состояния
  
   порты 6 - 9 "регулировка громкости" в каналах 1 - 4
   #xx06 "регулировка громкости" в канале 1
  		bit <5:0> громкость
  		bit <7:6> не используются
   #xx07 "регулировка громкости" в канале 2
  		bit <5:0> громкость
  		bit <7:6> не используются
   #xx08 "регулировка громкости" в канале 3
  		bit <5:0> громкость
  		bit <7:6> не используются
   #xx09 "регулировка громкости" в канале 4
  		bit <5:0> громкость
  		bit <7:6> не используются
  
   #xx0A устанавливает бит 7 слова состояния не равным биту 0 порта #xx00
   #xx0B устанавливает бит 0 слова состояния равным биту 5 порта #xx06
  
  Распределение памяти
  #0000 - #3FFF  -  первые 16Kb ПЗУ
  #4000 - #7FFF  -  первые 16Kb первой страницы ОЗУ
  #8000 - #FFFF  -  листаемые страницы по 32Kb
                    страница 0  - ПЗУ,
                    страница 1  - первая страница ОЗУ
                    страницы 2... ОЗУ
  
  Данные в каналы заносятся при чтении процессором ОЗУ по адресам  #6000 - #7FFF автоматически.

*/

module gs #(parameter PAGES=4, ROMFILE="gs105a.mif")
(
   input         RESET,
   input         CLK,
   input         CE,

   input  [15:0] A,
   input   [7:0] DI,
   output  [7:0] DO,
   input         WR_n,
   input         RD_n,
   input         IORQ_n,

	input             MUTE,
   output reg [14:0] OUTL,
   output reg [14:0] OUTR
);

// port #xxBB : #xxB3
assign DO = A[3] ? {bit7, 6'b111111, bit0} : port_03;

// CPU
reg         int_n;
wire        cpu_m1_n;
wire        cpu_mreq_n;
wire        cpu_iorq_n;
wire        cpu_rd_n;
wire        cpu_wr_n;
wire [15:0] cpu_a_bus;
wire  [7:0] cpu_do_bus;

T80pa cpu
(
	.RESET_n(~RESET),
	.CLK(CLK),
	.CEN_p(CE),
	.CEN_n(1),
	.WAIT_n(1),
	.INT_n(int_n),
	.NMI_n(1),
	.BUSRQ_n(1),
	.M1_n(cpu_m1_n),
	.MREQ_n(cpu_mreq_n),
	.IORQ_n(cpu_iorq_n),
	.RD_n(cpu_rd_n),
	.WR_n(cpu_wr_n),
	.A(cpu_a_bus),
	.DO(cpu_do_bus),
	.DI(cpu_di_bus)
);


// INT#
always @(posedge CLK) begin
	reg [9:0] cnt;

	if(CE) begin
		cnt <= cnt + 1'b1;
		if (cnt == 746) begin // 37.48kHz
			cnt <= 0;
			int_n <= 0;
		end
	end

	if (~cpu_iorq_n & ~cpu_m1_n) int_n <= 1;
end


reg bit7;
reg bit0;
always @(posedge CLK) begin
	if (~cpu_iorq_n & cpu_m1_n) begin
		case(cpu_a_bus[3:0])
			'h2: bit7 <= 0;
			'h3: bit7 <= 1;
			'h5: bit0 <= 0;
			'hA: bit7 <= ~port_00[0];
			'hB: bit0 <=  port_09[5];
		endcase
	end
	else if (~IORQ_n) begin
		if (A[7:0] == 8'hB3) begin
			if (~RD_n) bit7 <= 0;
			if (~WR_n) bit7 <= 1;
		end
		if (A[7:0] == 8'hBB && ~WR_n) bit0 <= 1;
	end
end


reg [7:0] port_BB;
reg [7:0] port_B3;
always @(posedge CLK) begin
	if (RESET) begin
		port_BB <= 0;
		port_B3 <= 0;
	end
	else if (~IORQ_n && ~WR_n) begin
		if(A[7:0] == 8'hBB) port_BB <= DI;
		if(A[7:0] == 8'hB3) port_B3 <= DI;
	end
end


reg [7:0] ch_a;
reg [7:0] ch_b;
reg [7:0] ch_c;
reg [7:0] ch_d;

reg [3:0] port_00;
reg [7:0] port_03;
reg [5:0] port_06;
reg [5:0] port_07;
reg [5:0] port_08;
reg [5:0] port_09;

always @(posedge CLK) begin
	if (RESET) begin
		port_00 <= 0;
		port_03 <= 0;
	end
	else begin
		if (~cpu_iorq_n & ~cpu_wr_n) begin
			case(cpu_a_bus[3:0])
				0: port_00 <= cpu_do_bus[3:0];
				3: port_03 <= cpu_do_bus;
				6: port_06 <= cpu_do_bus[5:0];
				7: port_07 <= cpu_do_bus[5:0];
				8: port_08 <= cpu_do_bus[5:0];
				9: port_09 <= cpu_do_bus[5:0];
			endcase
		end

		if (~cpu_mreq_n && ~cpu_rd_n && cpu_a_bus[15:13] == 3) begin
			case(cpu_a_bus[9:8])
				0: ch_a <= mem_do;
				1: ch_b <= mem_do;
				2: ch_c <= mem_do;
				3: ch_d <= mem_do;
			endcase
		end
	end

	if(MUTE) {ch_a,ch_b,ch_c,ch_d} <= 0;
end

wire [7:0] cpu_di_bus =
	(~cpu_mreq_n) ? mem_do : 
	(~cpu_iorq_n && cpu_a_bus[3:0] == 1) ? port_BB : 
	(~cpu_iorq_n && cpu_a_bus[3:0] == 2) ? port_B3 : 
	(~cpu_iorq_n && cpu_a_bus[3:0] == 4) ? {bit7, 6'b111111, bit0} : 
	8'hFF;

wire [7:0] mem_do;
dpram #(.ADDRWIDTH(19), .NUMWORDS((PAGES+1)*32768), .MEM_INIT_FILE(ROMFILE)) mem
(
	.clock(CLK),
	.address_a(cpu_a_bus[15] ? {port_00, cpu_a_bus[14:0]} : {3'b000, cpu_a_bus[14], 1'b0, cpu_a_bus[13:0]}),
	.wren_a(~cpu_wr_n & ~cpu_mreq_n & (cpu_a_bus[15] ? |port_00 : cpu_a_bus[14])),
	.data_a(cpu_do_bus),
	.q_a(mem_do)
);

reg [13:0] out_a,out_b,out_c,out_d;
always @(posedge CLK) begin
	if(CE) begin
		out_a <= ch_a * port_06;
		out_b <= ch_b * port_07;
		out_c <= ch_c * port_08;
		out_d <= ch_d * port_09;
	end
end

always @(posedge CLK) begin
	if(CE) begin
		OUTL <= {1'b0, out_a} + {1'b0, out_b};
		OUTR <= {1'b0, out_c} + {1'b0, out_d};
	end
end

endmodule
