----------------------------------------------------------------------------
--
--  Memory Management Unit
--
--  This is the implementation of a memory management unit. This MMU divides
--  memory into segments of 1024 words. Each segment is mapped to a block 
--  of physical addresses that are also power of 2 in size. A CPU/OS loads 
--  MMU registers with values from the table. This MMU contains four sets of 
--  segment registers currently cached in the MMU. These can be read or 
--  written into with the LAB, CS, and DB. The system uses a segmented 
--  system to assign the logical addresses to the physical addresses. The 
--  logical address bus is masked to derive the segment size and logical 
--  address that when added together provide the physical starting address
--  the segment index to give the entry into the segment table and the status
--  the status. There are four registers for each segment and the MMU occupies
--  16 words of memory. The starting physical address is at offset 0, starting
--  logical addres is at offset 1, logical address mask at offset 2, index/
--  status register is at offset 3 wihtin each block of four addresses for the 
--  segment registers.
--  
--  Revision History:
--  June 17 2025    Nerissa Finnen  Initial Implementation
--
----------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;
USE work.array_type_pkg.ALL;

ENTITY MMU IS
    PORT (
        LAB :   in    STD_LOGIC_VECTOR(31 downto 0);    --logical address bus
        RW  :   in    STD_LOGIC;    --Read/write signal (high/low)
        RWout   :   out    STD_LOGIC;    --Read/write signal (high/low)
        PAB :   out   STD_LOGIC_VECTOR(41 downto 0);    --physical address bus  
        CLK :   in    STD_LOGIC;    --Clock
        DB  :   inout    STD_LOGIC_VECTOR(31 downto 0);    --CPU databus
        CS  :   in    STD_LOGIC;    --Chip select signal (active low)
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

--SIGNALS
    TYPE MMU_SEGMENT_REGISTERS IS ARRAY (0 to 4) of STD_LOGIC_VECTOR(REG_SIZE - 1 DOWNTO 0);    --array of segment registers
    SIGNAL MMU_SEG_ONE : MMU_SEGMENT_REGISTERS;   --set 1 of segment register
    SIGNAL MMU_SEG_TWO : MMU_SEGMENT_REGISTERS;   --set 2 of segment register
    SIGNAL MMU_SEG_THREE : MMU_SEGMENT_REGISTERS; --set 3 of segment register
    SIGNAL MMU_SEG_FOUR : MMU_SEGMENT_REGISTERS;  --set 4 of segment register
BEGIN

--Update MMU actions with the clock
Process(CLK) 
IF rising_edge(CLK) THEN
    --Procedure: CS high
    --This is when chip select is inactive. When it is low it does not read/write into the registers
    --Instead it wants to check if LAB matches one of the caches.
    IF CS = '1' THEN
    --Procedure: SegFault
        --Here I would check in any of my segment registers matches the LAB when masked 
        --If it does there is no segment fault (SegFault is 0), otherwise there is (SegFault is 1)
        --If there is no segment fault then:
        --I think I can compute the PAB and then the DB would be written to that location
        --This means the LAB was stored in the cache and now I can quickly look it up
        --I can update the status bit of the segment that was read to read
        --I set RWout to RW and memory does his thing!!!
        --Otherwise (there is a segment fault) I do nothing

    --Procedure: ProtFault
        --I check if RW is 0, and if WP is true. This would mean that a write was attempted even
        --though WP was selected. I can set F to true to show a protection fault was generated
        --I also set ProtFault to true
        --Else, ProtFault is false and I do nothing

    --Procedure: CS low
    --This is when chip select is active. This wants to read and write to the DB based on 
    --Cache and RW. In order to determine the correct places to read and write, I use the LAB
    --to properly index the segment registers. 
    --When I have indexed, I write to the location, PAB, by calculating the location from the 
    --index segment register by using the mask to give me the index to add to the logical starting
    --address and add these to the physical address to get the PAB location. 
    ELSE
        IF RW = '1' THEN
            --I want to read, so I pull the data out of the cache and put it on the databus
            --I update the RWout to RW
        else
            --I want to write, so I keep the databus
            --I update the RWout to RW
        END IF;

    END IF;

END IF;
END Process;






--
END Structural;