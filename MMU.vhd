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
--  June 17 2025    Nerissa Finnen  Initial Implementation
--  June 25 2025    Nerissa Finnen  Implementation
--
----------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
--use ieee.std_logic_textio.all;
--use std.textio.all;

ENTITY MMU IS
    PORT (
        RESET : in    STD_LOGIC;    --Reset the system to initialize the MMU Seg Regs (active high)
        LAB :   in    STD_LOGIC_VECTOR(31 downto 0);    --logical address bus
        RW  :   in    STD_LOGIC;    --Read/write signal (high/low)
        CS  :   in    STD_LOGIC;    --Chip select signal (active low)
        CLK :   in    STD_LOGIC;    --Clock
        DB  :   inout    STD_LOGIC_VECTOR(31 downto 0);    --CPU databus
        PAB :   out   STD_LOGIC_VECTOR(41 downto 0);    --physical address bus  
        SegFault :  out STD_LOGIC;  --active low, indicates there is no matching segment(logical address)
        ProtFault : out STD_LOGIC  --active low, indicates there was an attempt to write to a write protected segment
    );
END MMU;
ARCHITECTURE Structural OF MMU IS
--CONSTANTS
    CONSTANT U  : integer := 31;    --segment has been used (read/written)
    CONSTANT D  : integer := 30;    --segment is dirty (written into)
    CONSTANT WP : integer := 29;    --segment is write protected => not controlled by MMU
    CONSTANT F  : integer := 28;    --segment generated a protection fault
    CONSTANT E  : integer := 27;    --segment enabled => not controlled by MMU
    CONSTANT REG_SIZE   :   integer := 32;  --size of the segment registers
    CONSTANT PHYSICAL_ADDRESS_INDEX : integer := 0; --In the array the physical address is at 0 offset
    CONSTANT LOGICAL_ADDRESS_INDEX : integer := 1;  --In the array the logical address is at 1 offset
    CONSTANT MASK_INDEX : integer := 2;             --In the array the mask is at 2 offset
    CONSTANT INDEX_STATUS_INDEX : integer := 3;     --In the array the index/status is at 3 offset
    CONSTANT LAB_MASK : STD_LOGIC_VECTOR(31 downto 0) := "11111111111111111111110000000000"; --Mask the logical stuff
    CONSTANT PHYSICAL_BASE_ALIGNED_ONE : STD_LOGIC_VECTOR(31 downto 0) := "00000000000000000000100000000000"; --2KB aligned (2048)
    CONSTANT PHYSICAL_BASE_ALIGNED_TWO : STD_LOGIC_VECTOR(31 downto 0) := "00000000000000000001000000000000"; --4KB  (4096)
    CONSTANT PHYSICAL_BASE_ALIGNED_THREE : STD_LOGIC_VECTOR(31 downto 0) := "00000000000000000001100000000000"; --6KB (6114)
    CONSTANT PHYSICAL_BASE_ALIGNED_FOUR : STD_LOGIC_VECTOR(31 downto 0) := "00000000000000000010000000000000"; --8KB  (8192)
    CONSTANT LOGICAL_BASE_ONE :STD_LOGIC_VECTOR(31 downto 0) := "0000000000100000000000" & "0000000000"; --2KB in 22 high bits, padded 0s in lower bits
    CONSTANT LOGICAL_BASE_TWO : STD_LOGIC_VECTOR(31 downto 0) := "0000000001000000000000" & "0000000000"; --4KB in 22 high bits, padded 0s in lower bits
    CONSTANT LOGICAL_BASE_THREE : STD_LOGIC_VECTOR(31 downto 0) := "0000000001000000000000" & "0000000000"; --6KB in 22 high bits, padded with 0s in lower bits
    CONSTANT LOGICAL_BASE_FOUR : STD_LOGIC_VECTOR(31 downto 0) := "0000000010000000000000" & "0000000000"; --8KB in 22 high bits, padded 0s in lower bits
    CONSTANT DEFAULT_PAB : STD_LOGIC_VECTOR(41 downto 0) := "000000000000000000000000000000000000000000"; --All zeros if invalid
    CONSTANT DEFAULT_INDEX_STATUS : STD_LOGIC_VECTOR(31 downto 0) := "00000000000000000000000000000000"; --Empty index/status reg

--SIGNALS
    TYPE MMU_SEGMENT_REGISTERS IS ARRAY (0 to 3) of STD_LOGIC_VECTOR(REG_SIZE - 1 DOWNTO 0);    --array of segment registers
    --index 0 is the physical address
    --index 1 is the segment from the LAB from "and-ing" with the mask
    --index 2 is the mask which masks only the top 22 bits for the segment, and when "not-ed" gives the offset instead when "and-ed"
    --with the LAB
    --index 3 is the segment index (16- bit low) and + 5 bits (high) of status 
    SIGNAL MMU_SEG_ONE : MMU_SEGMENT_REGISTERS; --set 1 of segment register
    SIGNAL MMU_SEG_TWO : MMU_SEGMENT_REGISTERS; --set 2 of segment register
    SIGNAL MMU_SEG_THREE : MMU_SEGMENT_REGISTERS; --set 3 of segment register
    SIGNAL MMU_SEG_FOUR : MMU_SEGMENT_REGISTERS; --set 4 of segment register
    SIGNAL LAB_SEGMENT : STD_LOGIC_VECTOR(31 downto 0); --Holds the segment after masking
    SIGNAL LAB_INDEX : STD_LOGIC_VECTOR(31 downto 0); --Holds the index after masking
    SIGNAL WP_SEG_REG : STD_LOGIC; --Record the WP for ProtFault protection checking
    SIGNAL D_SEG_REG : STD_LOGIC; --Record the D for ProtFault protections checking
    SIGNAL MMU_INDEX : integer; --Which MMU register to access for ProtFault
    SIGNAL DB_HOLD :STD_LOGIC_VECTOR(31 downto 0); --Interim bus to update the DB

BEGIN


DB <= DB_HOLD when (CS = '0' AND RW = '1') else (others => 'Z');

--Update MMU actions with the clock
Process(CLK) 
BEGIN
IF rising_edge(CLK) THEN
    --Procedure: Reset
    --Initialize the Seg Regs
    --report "DB" severity warning;
    IF (RESET = '1') THEN
        MMU_SEG_ONE(PHYSICAL_ADDRESS_INDEX) <= PHYSICAL_BASE_ALIGNED_ONE;
        MMU_SEG_ONE(LOGICAL_ADDRESS_INDEX) <= LOGICAL_BASE_ONE;
        MMU_SEG_ONE(MASK_INDEX) <= LAB_MASK;
        MMU_SEG_ONE(INDEX_STATUS_INDEX) <= DEFAULT_INDEX_STATUS;     

        MMU_SEG_TWO(PHYSICAL_ADDRESS_INDEX) <= PHYSICAL_BASE_ALIGNED_TWO;
        MMU_SEG_TWO(LOGICAL_ADDRESS_INDEX) <= LOGICAL_BASE_TWO;
        MMU_SEG_TWO(MASK_INDEX) <= LAB_MASK;
        MMU_SEG_TWO(INDEX_STATUS_INDEX) <= DEFAULT_INDEX_STATUS;  

        MMU_SEG_THREE(PHYSICAL_ADDRESS_INDEX) <= PHYSICAL_BASE_ALIGNED_THREE;
        MMU_SEG_THREE(LOGICAL_ADDRESS_INDEX) <= LOGICAL_BASE_THREE;
        MMU_SEG_THREE(MASK_INDEX) <= LAB_MASK;
        MMU_SEG_THREE(INDEX_STATUS_INDEX) <= DEFAULT_INDEX_STATUS;  

        MMU_SEG_FOUR(PHYSICAL_ADDRESS_INDEX) <= PHYSICAL_BASE_ALIGNED_FOUR;
        MMU_SEG_FOUR(LOGICAL_ADDRESS_INDEX) <= LOGICAL_BASE_FOUR;
        MMU_SEG_FOUR(MASK_INDEX) <= LAB_MASK;
        MMU_SEG_FOUR(INDEX_STATUS_INDEX) <= DEFAULT_INDEX_STATUS;      
    ELSE
    END IF;

    --Procedure: CS high
    --This is when chip select is inactive
    --Does not read/write into the registers
    --Checks LAB matches and generates the PAB upon hit
    IF CS = '1' THEN
        --Assign the LAB segment and LAB index
        LAB_SEGMENT <= LAB AND LAB_MASK;
        LAB_INDEX <= LAB AND (NOT LAB_MASK);

        --Procedure: SegFault
        --Segment match -> no Segment Fault
        --Calculate the PAB
        IF std_match(LAB_SEGMENT, MMU_SEG_ONE(LOGICAL_ADDRESS_INDEX)) THEN
            SegFault <= '1';
            PAB <= MMU_SEG_ONE(PHYSICAL_ADDRESS_INDEX) & LAB_INDEX(9 downto 0);

        ELSIF std_match(LAB_SEGMENT, MMU_SEG_TWO(LOGICAL_ADDRESS_INDEX)) THEN
            SegFault <= '1';
            PAB <= MMU_SEG_TWO(PHYSICAL_ADDRESS_INDEX) & LAB_INDEX(9 downto 0);

        ELSIF std_match(LAB_SEGMENT, MMU_SEG_THREE(LOGICAL_ADDRESS_INDEX)) THEN 
            SegFault <= '1';
            PAB <= MMU_SEG_THREE(PHYSICAL_ADDRESS_INDEX) & LAB_INDEX(9 downto 0);

        ELSIF std_match(LAB_SEGMENT, MMU_SEG_FOUR(LOGICAL_ADDRESS_INDEX)) THEN
            SegFault <= '1';
            PAB <= MMU_SEG_FOUR(PHYSICAL_ADDRESS_INDEX) & LAB_INDEX(9 downto 0);

        ELSE
        --No segment match -> Segment Fault
        --Set PAB to arbitrary default address
            PAB <= DEFAULT_PAB;
            SegFault <= '0';
        END IF;

    --Procedure: CS low
    --This is when chip select is active
    --Reads and Writes the DB and the Seg Regs onto each other based on LAB indexing
    --LAB indexes starting at 0, MMU segs index starting at 
    --my b
    ELSE
        PAB <= DEFAULT_PAB;
        IF RW = '1' THEN
            --Read
            --Write the Seg Reg onto the DB
            --Update the U bit to indicate a Read
            IF std_match(LAB(5 downto 4), "00") THEN
                MMU_SEG_ONE(INDEX_STATUS_INDEX)(U) <= '1';
                DB_HOLD <= MMU_SEG_ONE(to_integer(unsigned(LAB(3 downto 2))));

            ELSIF std_match(LAB(5 downto 4), "01") THEN
                MMU_SEG_TWO(INDEX_STATUS_INDEX)(U) <= '1';
                DB_HOLD <= MMU_SEG_TWO(to_integer(unsigned(LAB(3 downto 2))));

            ELSIF std_match(LAB(5 downto 4), "10") THEN 
                MMU_SEG_THREE(INDEX_STATUS_INDEX)(U) <= '1';
                DB_HOLD <= MMU_SEG_THREE(to_integer(unsigned(LAB(3 downto 2))));

            ELSIF std_match(LAB(5 downto 4), "11") THEN 
                MMU_SEG_FOUR(INDEX_STATUS_INDEX)(U) <= '1';
                DB_HOLD <= MMU_SEG_FOUR(to_integer(unsigned(LAB(3 downto 2))));

            ELSE
            END IF;
        ELSE
            --Write
            --Write the DB onto the Index/Status reg
            --Update the U bit to indicate a Write
            --Update the D bit to indicate dirty (a write)
            --Record the WP bit to check the ProtFault
            --Record the D bit too for ProtFault
            IF std_match(LAB(5 downto 4), "00") THEN
                MMU_SEG_ONE(to_integer(unsigned(LAB(3 downto 2)))) <= DB;
                MMU_SEG_ONE(INDEX_STATUS_INDEX)(U) <= '1';
                MMU_SEG_ONE(INDEX_STATUS_INDEX)(D) <= '1';
                WP_SEG_REG <= MMU_SEG_ONE(INDEX_STATUS_INDEX)(WP);
                D_SEG_REG <= '1';
                --report "DB" & to_hstring(DB);

            ELSIF std_match(LAB(5 downto 4), "00") THEN
                MMU_SEG_TWO(to_integer(unsigned(LAB(3 downto 2)))) <= DB;
                MMU_SEG_TWO(INDEX_STATUS_INDEX)(U) <= '1';
                MMU_SEG_TWO(INDEX_STATUS_INDEX)(D) <= '1';
                WP_SEG_REG <= MMU_SEG_ONE(INDEX_STATUS_INDEX)(WP);
                D_SEG_REG <= '1';

            ELSIF std_match(LAB(5 downto 4), "00") THEN 
                MMU_SEG_THREE(to_integer(unsigned(LAB(3 downto 2)))) <= DB;
                MMU_SEG_THREE(INDEX_STATUS_INDEX)(U) <= '1';
                MMU_SEG_THREE(INDEX_STATUS_INDEX)(D) <= '1';
                WP_SEG_REG <= MMU_SEG_ONE(INDEX_STATUS_INDEX)(WP);
                D_SEG_REG <= '1';

            ELSIF std_match(LAB(5 downto 4), "00") THEN 
                MMU_SEG_FOUR(to_integer(unsigned(LAB(3 downto 2)))) <= DB;
                MMU_SEG_FOUR(INDEX_STATUS_INDEX)(U) <= '1';
                MMU_SEG_FOUR(INDEX_STATUS_INDEX)(D) <= '1';
                WP_SEG_REG <= MMU_SEG_ONE(INDEX_STATUS_INDEX)(WP);
                D_SEG_REG <= '1';

            ELSE
            END IF;
        END IF;

        --Procedure: ProtFault
        --If D is 1, and WP is true -> ProtFault, F <= 1 to the corresponding MMU Seg Reg
        IF ((D_SEG_REG = '1') AND (WP_SEG_REG = '1')) THEN
            ProtFault <= '0';

            IF std_match(LAB(5 downto 4), "00") THEN
                MMU_SEG_ONE(INDEX_STATUS_INDEX)(F) <= '1';

            ELSIF std_match(LAB(5 downto 4), "01") THEN
                MMU_SEG_TWO(INDEX_STATUS_INDEX)(F) <= '1';

            ELSIF std_match(LAB(5 downto 4), "10") THEN
                MMU_SEG_THREE(INDEX_STATUS_INDEX)(F) <= '1';

            ELSIF std_match(LAB(5 downto 4), "11") THEN
                MMU_SEG_FOUR(INDEX_STATUS_INDEX)(F) <= '1';

            --Do nothing 
            ELSE
            END IF;

        ELSE 
        --No protection fault -> F <= 0
            ProtFault <= '1';

            IF std_match(LAB(5 downto 4), "00") THEN
                MMU_SEG_ONE(INDEX_STATUS_INDEX)(F) <= '0';

            ELSIF std_match(LAB(5 downto 4), "01") THEN
                MMU_SEG_TWO(INDEX_STATUS_INDEX)(F) <= '0';

            ELSIF std_match(LAB(5 downto 4), "10") THEN
                MMU_SEG_THREE(INDEX_STATUS_INDEX)(F) <= '0';

            ELSIF std_match(LAB(5 downto 4), "11") THEN
                MMU_SEG_FOUR(INDEX_STATUS_INDEX)(F) <= '0';

            --Do nothing 
            ELSE
            END IF;
        END IF;
    END IF;

END IF;
END Process;
END Structural;