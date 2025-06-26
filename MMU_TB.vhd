----------------------------------------------------------------------------
--
--  Memory Management Unit
--
--  This is the implementation of a memory management unit. This MMU divides
--  memory into segments of 2KB. Each segment is mapped to a block 
--  of physical addresses that are also power of 2 in size. A CPU/OS loads 
--  MMU registers with values from the table. This MMU contains four sets of 
--  segment registers currently cached in the MMU. 
--
--  There are two main modes of functionality, CS and !CS (active low). The
--  CS mode reads and writes data between the DB and the Seg Regs based on 
--  indexing from the lowest bits of the LAB. LAB(5 downto 4) determine the 
--  which MMU set of Seg Regs, and LAB(3 downto 2) determine the specific 
--  Seg Reg of the group. If a write happens onto a WP then there is a 
--  ProtFault. The F bit of the status bits of the Seg Regs also updates
--  to reflect this. When a Read or Write happens (active low write), the
--  the U bit also updates, and when a Write exclusively happens the D bit
--  updates. 
--
--  When !CS, the LAB is used to calculate the PAB. The PAB is determined by 
--  first finding a hit. This is when the LAB top 22 bits are masked and matched
--  to the logical start of any of the MMU Seg Regs. If there is no hit the PAB 
--  is defaulted, and a SegFault is reported. If there is a match, the Physical 
--  start address from the corresponding Seg Reg is pulled and concatenated with 
--  the index bits (the bottom 10 bits of the LAB masked) to go to the correct 
--  location. 
--
--  There are four registers for each segment and the MMU occupies
--  16 words of memory. The starting physical address is at offset 0, starting
--  logical address is at offset 1, logical address mask at offset 2, index/
--  status register is at offset 3 wihtin each block of four addresses for the 
--  segment registers.
--
--  A reset signal is implemented to allow for an initialization of the MMU Seg Regs.
--
--  
--  Revision History:
--  June 25 Nerissa Finnen  Initial Implementation := CS = 0 works
--  June 26 Nerissa Finnen  Fine Tuning := CS = 1 works, added more tests
--
----------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;
use std.textio.all;

entity MMU_TB is
end MMU_TB;

architecture behavior of MMU_TB is
    -- Component Declaration
    component MMU
    port (
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
    signal lab   : std_logic_vector(31 downto 0);
    signal rw    : std_logic; 
    signal cs    : std_logic;
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

        --==========================================================================
        -- 1. Initialize Segment 1 (CS=0, RW=0)
        --==========================================================================
        report "Enabling Writing Mode";
        cs <= '0';  -- Register mode
        rw <= '0';  -- Write mode

        report "Writing to Segment 1 registers";
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
        lab <= x"0000000C";
        db_hold  <= "00101000" & x"001234";  -- Valid(1) + RO(1) + Index 0x1234
        wait for clk_period;

        --==========================================================================
        -- 2. Initialize Segment 2 (CS=0, RW=0)
        --==========================================================================
        report "Writing to Segment 2 registers";
        -- Write Physical Base (offset 0)
        lab <= x"00000010";  -- Segment 1, offset 0
        db_hold  <= x"80000000";  -- Physical Base = 0x80000000
        wait for clk_period;
        
        -- Write Logical Base (offset 1)
        lab <= x"00000014";
        db_hold  <= x"00000000";  -- Logical Base = 0x00000000
        wait for clk_period;
        
        -- Write Mask (offset 2)
        lab <= x"00000018";
        db_hold  <= x"FFFFF800";  -- 4KB mask
        wait for clk_period;
        
        -- Write Index/Status (offset 3)
        lab <= x"0000001C";
        db_hold  <= "00001000" & x"001234";  -- Valid(1) + RO(1) + Index 0x1234
        wait for clk_period;

        --==========================================================================
        -- 3. Initialize Segment 3 (CS=0, RW=0)
        --==========================================================================
        report "Writing to Segment 3 registers";
        -- Write Physical Base (offset 0)
        lab <= x"00000020";  -- Segment 2, offset 0
        db_hold  <= x"80000000";  -- Physical Base = 0x80000000
        wait for clk_period;
        
        -- Write Logical Base (offset 1)
        lab <= x"00000024";
        db_hold  <= x"00400000";  -- Logical Base = 0x00400000 (22-bit: 0x004000)
        wait for clk_period;
        
        -- Write Mask (offset 2)
        lab <= x"00000028";
        db_hold  <= x"FFFFF800";  -- 4KB mask
        wait for clk_period;
        
        -- Write Index/Status (offset 3)
        lab <= x"0000002C";
        db_hold  <= "00101000" & x"001234";  -- Valid(1) + RO(1) + Index 0x1234
        wait for clk_period;

        --==========================================================================
        -- 4. Initialize Segment 4 (CS=0, RW=0)
        --==========================================================================
        report "Writing to Segment 4 registers";
        -- Write Physical Base (offset 0)
        lab <= x"00000030";  -- Segment 4, offset 0
        db_hold  <= x"00010000";  
        wait for clk_period;
        
        -- Write Logical Base (offset 1)
        lab <= x"00000034";
        db_hold  <= x"10010000"; 
        wait for clk_period;
        
        -- Write Mask (offset 2)
        lab <= x"00000038";
        db_hold  <= x"FFFF0000";  
        wait for clk_period;
        
        -- Write Index/Status (offset 3)
        lab <= x"0000003C";
        db_hold  <= "00011000" & x"001234";  -- Valid(1) + RO(1) + Index 0x1234
        wait for clk_period;

        --==========================================================================
        -- 5. Verify writes (CS=0, RW=1)
        --==========================================================================
        rw <= '1';  -- Read mode
        
        --==========================================================================
        -- 6. Verify Segment 1
        --==========================================================================
        report "Reading back Segment 1 registers";
        -- Read Physical Base
        lab <= x"00000000";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db = x"80000000" report "Physical Base read error" severity error;
        
        -- Read Logical Base
        lab <= x"00000004";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db(31 downto 10) = "0000000001000000000000" report "Logical Base read error" severity error;

          -- Read Mask
        lab <= x"00000008";
        wait for clk_period;
        assert db(31 downto 10) = "1111111111111111111100" report "Mask read error" severity error;
        
        -- Read Index/Status
        lab <= x"0000000C";
        wait for clk_period;
        assert db(31 downto 27) = "00101" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        --==========================================================================
        -- 7. Verify Segment 2
        --==========================================================================
        report "Reading back Segment 2 registers";
        -- Read Physical Base
        lab <= x"00000010";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db = x"80000000" report "Physical Base read error" severity error;
        
        -- Read Logical Base
        lab <= x"00000014";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db(31 downto 10) = "0000000000000000000000" report "Logical Base read error" severity error;

          -- Read Mask
        lab <= x"00000018";
        wait for clk_period;
        assert db(31 downto 10) = "1111111111111111111110" report "Mask read error" severity error;
        
        -- Read Index/Status
        lab <= x"0000001C";
        wait for clk_period;
        assert db(31 downto 27) = "00001" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        --==========================================================================
        -- 7. Verify Segment 3
        --==========================================================================
        report "Reading back Segment 3 registers";
        -- Read Physical Base
        lab <= x"00000020";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db = x"80000000" report "Physical Base read error" severity error;
        
        -- Read Logical Base
        lab <= x"00000024";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db(31 downto 10) = "0000000001000000000000" report "Logical Base read error" severity error;

          -- Read Mask
        lab <= x"00000028";
        wait for clk_period;
        assert db(31 downto 10) = "1111111111111111111110" report "Mask read error" severity error;
        
        -- Read Index/Status
        lab <= x"0000002C";
        wait for clk_period;
        assert db(31 downto 27) = "00101" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        --==========================================================================
        -- 8. Verify Segment 4
        --==========================================================================
        report "Reading back Segment 4 registers";
        -- Read Physical Base
        lab <= x"00000030";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db = x"00010000" report "Physical Base read error" severity error;
        
        -- Read Logical Base
        lab <= x"00000034";
        db_hold <= (others => 'Z');
        wait for clk_period;
        assert db(31 downto 10) = "0001000000000001000000" report "Logical Base read error" severity error;

          -- Read Mask
        lab <= x"00000038";
        wait for clk_period;
        assert db(31 downto 10) = "1111111111111111000000" report "Mask read error" severity error;
        
        -- Read Index/Status
        lab <= x"0000003C";
        wait for clk_period;
        assert db(31 downto 27) = "00011" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        --==========================================================================    
        -- 9. Test address translation (CS=1)
        --==========================================================================
        report "Testing address translation";
        cs <= '1';  -- Translation mode
        
        -- Valid access (within Segment 1 and 3)
        lab <= x"00400004";  -- Logical address
        wait for clk_period;       

        assert pab = "10" & x"0000000004" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;

        -- Valid access (within Segment 2)
        lab <= x"00000003";  -- Logical address
        wait for clk_period;     

        assert pab = "10" & x"0000000003" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;

        -- Valid access (within Segment 1 and 3)
        lab <= x"00400009";  -- Logical address
        wait for clk_period;    

        assert pab = "10" & x"0000000009" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;

        -- Valid access (within Segment 3 and 1, should just return 1)
        lab <= x"1001000A";  -- Logical address
        wait for clk_period;       

        assert pab = x"0001000002" & "10" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;
        
        --==========================================================================    
        -- 10. Testing Faults (CS=1) 
        --==========================================================================
        -- Segment Fault
        report "Testing segment fault";
        lab <= x"12345678";
        wait for clk_period;
        assert pab = "000000000000000000000000000000000000000000" report "Translation error" severity error;
        assert segfault = '0' report "Missing segfault" severity error;
        assert protfault = '1' report "Missing protfault" severity error;

        -- Protection Fault 
        report "Testing protection fault";
        lab <= x"00400800";  -- Valid address
        rw <= '0';           -- Write attempt
        wait for clk_period;
        assert pab = "000000000000000000000000000000000000000000" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;
        assert protfault = '0' report "Missing protfault" severity error;

        lab <= x"00000003";  -- Logical address
        wait for clk_period;          

        assert pab = "10" & x"0000000003" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;
        assert protfault = '1' report "Missing protfault" severity error;

        -- Valid access (within Segment 1 and 3)
        lab <= x"00400009";  -- Logical address
        wait for clk_period;        

        assert pab = "000000000000000000000000000000000000000000" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;
        assert protfault = '0' report "Missing protfault" severity error;

        -- Valid access (within Segment 3 and 1, should just return 1)
        lab <= x"1001000A";  -- Logical address
        wait for clk_period;          

        assert pab = x"0001000002" & "10" report "Translation error" severity error;
        assert segfault = '1' report "Unexpected fault" severity error;
        assert protfault = '1' report "Missing protfault" severity error;

        --==========================================================================    
        -- 11. Read Updated Status bits I AM HERE
        --==========================================================================
        cs <= '0';
        rw <= '1';

        -- Read Index/Status (Segment 1)
        lab <= x"0000000C";
        wait for clk_period;
        assert db(31 downto 27) = "00111" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        -- Read Index/Status (Segment 2)
        lab <= x"0000001C";
        wait for clk_period;
        assert db(31 downto 27) = "11001" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        -- Read Index/Status (Segment 3)
        -- This is anticipated as the first access triggers (Segment 1 before
        -- Segment 3) and updates the F bit there, but not here.
        lab <= x"0000002C";
        wait for clk_period;
        assert db(31 downto 27) = "00101" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        -- Read Index/Status (Segment 4)
        -- Initially had a written F bit, this overwrote it when there's no
        -- protfault.
        lab <= x"0000003C";
        wait for clk_period;
        assert db(31 downto 27) = "11001" and db(15 downto 0) = x"1234" 
            report "Index/Status read error" severity error;

        report "Testbench complete";
        wait;
    end process;
end behavior;