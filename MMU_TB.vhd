library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity MMU_TB is
end MMU_TB;

architecture behavior of MMU_TB is
    -- Component Declaration
    component MMU
    port (
        RESET : in    STD_LOGIC;    --Reset the system to initialize the MMU Seg Regs (active high)
        LAB :   in    STD_LOGIC_VECTOR(31 downto 0);    --logical address bus
        RW  :   in    STD_LOGIC;    --Read/write signal (high/low)
        CS  :   in    STD_LOGIC;    --Chip select signal (active low)
        CLK :   in    STD_LOGIC;    --Clock
        DB  :   inout    STD_LOGIC_VECTOR(31 downto 0) := (others => 'Z');    --CPU databus
        PAB :   out   STD_LOGIC_VECTOR(41 downto 0);    --physical address bus  
        SegFault :  out STD_LOGIC;  --active low, indicates there is no matching segment(logical address)
        ProtFault : out STD_LOGIC  --active low, indicates there was an attempt to write to a write protected segment
    );
    end component;

    -- Signals
    signal reset : std_logic := '0';
    signal lab   : std_logic_vector(31 downto 0);
    signal rw    : std_logic := '1'; 
    signal cs    : std_logic := '1';
    signal clk   : std_logic := '0';
    signal db    : std_logic_vector(31 downto 0);
    signal pab   : std_logic_vector(41 downto 0);
    signal segfault : std_logic;
    signal protfault : std_logic;
    signal db_hold    : std_logic_vector(31 downto 0) := (others => 'Z');

    -- Clock period
    constant clk_period : time := 10 ns;
begin
    -- Instantiate MMU
    uut: MMU port map (
        RESET => reset,
        LAB => lab,
        RW => rw,
        CS => cs,
        CLK => clk,
        DB => db,
        PAB => pab,
        SegFault => segfault,
        ProtFault => protfault
    );

    -- Clock process
    clk_process: process
    begin
        clk <= '0';
        wait for clk_period/2;
        clk <= '1';
        wait for clk_period/2;
    end process;

    db <= db_hold when ((cs = '0') AND (rw = '0')) else (others => 'Z');
    -- Test stimulus
    stim_proc: process
    begin
        wait for clk_period;



        -- 1. Initialize Segment 0 (CS=0, RW=0)
        report "Writing to Segment 0 registers";
        cs <= '0';  -- Register mode
        rw <= '0';  -- Write mode
        
        -- Write Physical Base (offset 0)
        lab <= x"00000000";  -- Segment 0, offset 0
        db_hold  <= x"80000000";  -- Physical Base = 0x80000000
        wait for clk_period;
        
        -- Write Logical Base (offset 1)
        lab <= x"00000004";
        db_hold  <= x"00400000";  -- Logical Base = 0x00400000 (22-bit: 0x004000)
        wait for clk_period;
        
        -- Write Mask (offset 2)
        lab <= x"00000008";
        db_hold  <= x"FFFFF000";  -- 4KB mask
        wait for clk_period;
        
        -- Write Index/Status (offset 3)
  --      lab <= x"0000000B";
  --      db  <= x"E0001234";  -- Valid(1) + RO(1) + Index 0x1234
   --     wait for clk_period;

        -- 2. Verify writes (CS=0, RW=1)
        report "Reading back Segment 0 registers";
        rw <= '1';  -- Read mode
        
        -- Read Physical Base
        lab <= x"00000000";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db = x"80000000" report "Physical Base read error" severity error;
        
        -- Read Logical Base
        lab <= x"00000004";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db(21 downto 0) = x"004000" report "Logical Base read error" severity error;
        report "Testbench complete";
        wait;
    end process;
end behavior;