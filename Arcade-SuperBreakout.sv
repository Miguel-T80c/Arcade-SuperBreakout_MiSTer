//============================================================================
//  SuperBreakout port to MiSTer
//  Copyright (c) 2019 Alan Steremberg - alanswx
//
//   
//============================================================================


module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [11:0] VIDEO_ARX,
	output [11:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler

	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

        input         CLK_AUDIO, // 24.576 MHz
        output [15:0] AUDIO_L,
        output [15:0] AUDIO_R,
        output        AUDIO_S,    // 1 - signed audio samples, 0 - unsigned

        //High latency DDR3 RAM interface
        //Use for non-critical time purposes
        output        DDRAM_CLK,
        input         DDRAM_BUSY,
        output  [7:0] DDRAM_BURSTCNT,
        output [28:0] DDRAM_ADDR,
        input  [63:0] DDRAM_DOUT,
        input         DDRAM_DOUT_READY,
        output        DDRAM_RD,
        output [63:0] DDRAM_DIN,
        output  [7:0] DDRAM_BE,
        output        DDRAM_WE,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	output	USER_OSD,
	output	[1:0] USER_MODE,
	input	[7:0] USER_IN,
	output	[7:0] USER_OUT
);

assign VGA_F1    = 0;
assign VGA_SCALER= 0;

wire         CLK_JOY = CLK_50M;         //Assign clock between 40-50Mhz
wire   [2:0] JOY_FLAG  = {status[30],status[31],status[29]}; //Assign 3 bits of status (31:29) o (63:61)
wire         JOY_CLK, JOY_LOAD, JOY_SPLIT, JOY_MDSEL;
wire   [5:0] JOY_MDIN  = JOY_FLAG[2] ? {USER_IN[6],USER_IN[3],USER_IN[5],USER_IN[7],USER_IN[1],USER_IN[2]} : '1;
wire         JOY_DATA  = JOY_FLAG[1] ? USER_IN[5] : '1;
assign       USER_OUT  = JOY_FLAG[2] ? {3'b111,JOY_SPLIT,3'b111,JOY_MDSEL} : JOY_FLAG[1] ? {6'b111111,JOY_CLK,JOY_LOAD} : '1;
assign       USER_MODE = JOY_FLAG[2:1] ;
assign       USER_OSD  = joydb_1[10] & joydb_1[6];

assign LED_DISK  = 0;
assign LED_POWER = 0;
assign LED_USER  = ioctl_download;

assign {FB_PAL_CLK, FB_FORCE_BLANK, FB_PAL_ADDR, FB_PAL_DOUT, FB_PAL_WR} = '0;

wire [1:0] ar = status[15:14];


assign VIDEO_ARX = (!ar) ? ((status[2] ) ? 8'd4 : 8'd3) : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? ((status[2] ) ? 8'd3 : 8'd4) : 12'd0;


/////////////////////////////////////////////////////////

wire clk_sys, clk_vid;

pll pll (
	.refclk(CLK_50M),
	.rst(0),
	.outclk_0(clk_vid), // 48 MHz
	.outclk_1(clk_sys)  // 12 MHz
);

/////////////////////////////////////////////////////////

`include "build_id.v"
localparam CONF_STR = {
	"A.SBRKOUT;;",
	"-;",
	"H0OEF,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"H0O2,Orientation,Vert,Horz;",
	"O35,Scandoubler Fx,None,HQ2x,CRT 25%,CRT 50%,CRT 75%;",  
	"-;",
	"OUV,UserIO Joystick,Off,DB9MD,DB15 ;",
	"OT,UserIO Players, 1 Player,2 Players;",
	"-;",
	"OHI,Control,Buttons,Analog Stick,Paddle;",
	"-;",
	"OAB,Language,English,German,French,Spanish;",
	"OC,Balls,3,5;",
	"O68,Bonus,200,400,600,900,1200,1600,2000,None;",
	"OJK,Level,Progresive,Cavity,Double;",//DE
	"OL,Test,Off,On;",//F
	"OG,Color,On,Off;",
	"-;",
	"R0,Reset;",
	"J1,Serve,Start 1P,Start 2P,Coin;",
	"jn,A,Start,Select,R;",
	"V,v",`BUILD_DATE
};


wire [31:0] status;
wire  [1:0] buttons;
wire        forced_scandoubler;
wire        direct_video;

wire        ioctl_download;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire  [7:0] ioctl_data;

wire [10:0] ps2_key;
wire  [7:0] paddle;
//wire [24:0] ps2_mouse;

wire [15:0] joystick_0_USB, joystick_1_USB;
wire [15:0] joy = joystick_0 | joystick_1;
wire  [7:0] joya;

wire [21:0] gamma_bus;

// CO S2 S1 F1 U D L R 
wire [31:0] joystick_0 = joydb_1ena ? {joydb_1[11]|(joydb_1[10]&joydb_1[5]),joydb_1[9],joydb_1[10],joydb_1[4:0]} : joystick_0_USB;
wire [31:0] joystick_1 = joydb_2ena ? {joydb_2[11]|(joydb_2[10]&joydb_2[5]),joydb_2[10],joydb_2[9],joydb_2[4:0]} : joydb_1ena ? joystick_0_USB : joystick_1_USB;

wire [15:0] joydb_1 = JOY_FLAG[2] ? JOYDB9MD_1 : JOY_FLAG[1] ? JOYDB15_1 : '0;
wire [15:0] joydb_2 = JOY_FLAG[2] ? JOYDB9MD_2 : JOY_FLAG[1] ? JOYDB15_2 : '0;
wire        joydb_1ena = |JOY_FLAG[2:1]              ;
wire        joydb_2ena = |JOY_FLAG[2:1] & JOY_FLAG[0];

//----BA 9876543210
//----MS ZYXCBAUDLR
reg [15:0] JOYDB9MD_1,JOYDB9MD_2;
joy_db9md joy_db9md
(
  .clk       ( CLK_JOY    ), //40-50MHz
  .joy_split ( JOY_SPLIT  ),
  .joy_mdsel ( JOY_MDSEL  ),
  .joy_in    ( JOY_MDIN   ),
  .joystick1 ( JOYDB9MD_1 ),
  .joystick2 ( JOYDB9MD_2 )	  
);

//----BA 9876543210
//----LS FEDCBAUDLR
reg [15:0] JOYDB15_1,JOYDB15_2;
joy_db15 joy_db15
(
  .clk       ( CLK_JOY   ), //48MHz
  .JOY_CLK   ( JOY_CLK   ),
  .JOY_DATA  ( JOY_DATA  ),
  .JOY_LOAD  ( JOY_LOAD  ),
  .joystick1 ( JOYDB15_1 ),
  .joystick2 ( JOYDB15_2 )	  
);

hps_io #(.STRLEN(($size(CONF_STR)>>3) )) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),

	.conf_str(CONF_STR),
	.joystick_0(joystick_0_USB),
	.joystick_1(joystick_1_USB),

	.joystick_analog_0(joya),
	.paddle_0(paddle),

	.buttons(buttons),
	.status(status),
	.status_menumask(direct_video),
	.forced_scandoubler(forced_scandoubler),
	.gamma_bus(gamma_bus),
	.direct_video(direct_video),

	.ioctl_download(ioctl_download),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_data),

	.joy_raw(joydb_1[5:0] | joydb_2[5:0])
);




wire m_left	   =   joy[1];
wire m_right   =   joy[0];
wire m_serve   =   joy[4] | ~USER_IN[3];

wire m_select1 = status[19]; //Select level Double
wire m_select2 = status[20]; //Select level Progresive

wire m_start1  =  joy[5];
wire m_start2  =  joy[6];
wire m_coin    =  joy[7];

/*
-- Configuration DIP switches, these can be brought out to external switches if desired
-- See Super Breakout manual page 13 for complete information. Active low (0 = On, 1 = Off)
--    1 	2							Language				(00 - English)
--   			3	4					Coins per play		(10 - 1 Coin, 1 Play) 
--						5				3/5 Balls			(1 - 3 Balls)
--							6	7	8	Bonus play			(011 - 600 Progressive, 400 Cavity, 600 Double)
		
SW2 <= "00101011";
*/

wire [7:0] SW1 = {status[11:10],1'b1,1'b0,status[12],status[8:6]};

wire [1:0] steer0;
joy2quad steerjoy2quad0
(
	.CLK(clk_sys),
	//.clkdiv('d22500),
	.clkdiv('d5500),
	
	.right(m_right),
	.left(m_left),

	.steer(steer0)
);

reg use_io = 0; // 1 - use encoder on USER_IN[1:0] pins
always @(posedge clk_sys) begin
reg [1:0] old_io;
reg [1:0] old_steer;

	if (~|JOY_FLAG[2:1]) old_io <= USER_IN[1:0];
	if(old_io != USER_IN[1:0]) use_io <= 1;
	
	old_steer <= steer0;
	if(old_steer != steer0) use_io <= 0;
end

/*			Pot_Comp1_I	: in  std_logic;	-- If you want to use a pot instead, this goes to the output of the comparator
			Serve_LED_O	: out std_logic;	-- Serve button LED (Active low)
			Counter_O	: out std_logic;	-- Coin counter output (Active high)
*/
wire videowht;
wire [7:0] audio1;

wire reset = RESET | status[0] | buttons[1];

super_breakout super_breakout(
	.Reset_n(~reset),

	.dn_addr(ioctl_addr[16:0]),
	.dn_data(ioctl_data),
	.dn_wr(ioctl_wr),

	.Video_O(videowht),
	.Video_RGB(videorgb),

	.Audio_O(audio1),
	.Coin1_I(~m_coin),
	.Coin2_I(1'b1),
	
	.Start1_I(~m_start1),
	.Start2_I(~m_start2),
	
	.Serve_I(~m_serve),
	.Select1_I(~m_select1),
	.Select2_I(~m_select2),
	.Slam_I(1),
	.Test_I(~status[21]),
	.Enc_A(use_io ? USER_IN[1] : steer0[1]),
	.Enc_B(use_io ? USER_IN[0] : steer0[0]),
	.Paddle(status[17] ? (joya ^ 8'h80) : status[18] ? paddle : 8'h00),
	.Lamp1_O(),
	.Lamp2_O(),
	.hs_O(hs),
	.vs_O(vs),
	.hblank_O(hblank),
	.vblank_O(vblank),
	.clk_12(clk_sys),
	.clk_6_O(ce_pix),
	.SW1_I(SW1)
);
			
///////////////////////////////////////////////////

wire hs,vs,hblank,vblank;

wire ce_pix;
wire [8:0] videorgb;
wire [2:0] r,g;
wire [2:0] b;
assign r={3{videowht}};
assign g={3{videowht}};
assign b={3{videowht}};

wire no_rotate = status[2] | direct_video;

reg HBlank, VBlank;
always @(posedge clk_sys) begin
	reg [10:0] hcnt, vcnt;
	reg old_hbl, old_vbl;

	if(ce_pix) begin
		hcnt <= hcnt + 1'd1;
		old_hbl <= hblank;
		if(old_hbl & ~hblank) begin
			hcnt <= 0;
			
			vcnt <= vcnt + 1'd1;
			old_vbl <= vblank;
			if(old_vbl & ~vblank) vcnt <= 0;
		end
		
		if (hcnt == 37)  HBlank <= 0;
		if (hcnt == 292) HBlank <= 1;
		
		if (vcnt == 0)   VBlank <= 0;
		if (vcnt == 224) VBlank <= 1;
	end
end


arcade_video #(255,9) arcade_video
(
	.*,

	.clk_video(clk_vid),
	.RGB_in(~status[16]?videorgb:{r,g,b}),
	.HSync(hs),
	.VSync(vs),
	
	.fx(status[5:3])
);
wire rotate_ccw = 1;
screen_rotate screen_rotate (.*);

reg mute;
always @(posedge clk_sys) begin
	integer cnt;

	mute <= 0;
	if(cnt < 24000000) begin
		mute <= 1;
		cnt <= cnt + 1;
	end

	if(reset) cnt <= 0;
end

assign AUDIO_L={mute ? 8'd0 : audio1, 8'd0};
assign AUDIO_R=AUDIO_L;
assign AUDIO_S = 0;
wire scrap;

endmodule
